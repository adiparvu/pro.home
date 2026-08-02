import XCTest
@testable import PRVIO

// The socket-wait law, finally under test. Three consecutive field
// regressions rode this exact loop — the join timebox burned on a dead
// socket (b1197), the cancelled wait that busy-spun a family-wide freeze
// (b1198), the rewritten listener that skipped the wait (b1200) — and none
// of them could be caught in CI because the loop was welded to the live
// socket. RealtimeSocketWait put it behind a seam; these tests pin every
// shipped failure mode. Timings use generous margins: CI simulators jitter.
@MainActor
final class RealtimeSocketWaitTests: XCTestCase {

    /// Scripted socket: the test flips its state; the wait observes it.
    final class FakeSocket: RealtimeSocketing {
        var connected = false
        var disconnected = true
        var kicks = 0
        var isConnected: Bool { connected }
        var isDisconnected: Bool { disconnected }
        func kickConnect() { kicks += 1 }
    }

    func testAlreadyConnectedReturnsImmediatelyWithoutKicking() async {
        let socket = FakeSocket()
        socket.connected = true
        socket.disconnected = false
        let start = Date()
        await RealtimeSocketWait.wait(on: socket, seconds: 5,
                                      tickNanoseconds: 10_000_000,
                                      isBackgrounded: { false })
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(socket.kicks, 0, "the happy path must cost nothing")
    }

    func testDisconnectedSocketGetsExactlyOneKick() async {
        let socket = FakeSocket()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            socket.connected = true
        }
        await RealtimeSocketWait.wait(on: socket, seconds: 5,
                                      tickNanoseconds: 10_000_000,
                                      isBackgrounded: { false })
        // The chat-first cold entry (b1199): nothing else may ever connect
        // the socket, so the wait must nudge it — once.
        XCTAssertEqual(socket.kicks, 1)
        XCTAssertTrue(socket.isConnected)
    }

    func testReturnsPromptlyOnceSocketConnects() async {
        let socket = FakeSocket()
        let start = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            socket.connected = true
        }
        await RealtimeSocketWait.wait(on: socket, seconds: 10,
                                      tickNanoseconds: 10_000_000,
                                      isBackgrounded: { false })
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.05, "must actually wait for the socket")
        XCTAssertLessThan(elapsed, 3.0, "must not run to the deadline once connected")
    }

    /// THE b1198 pin: a cancelled wait EXITS. The shipped bug swallowed the
    /// sleep's CancellationError with `try?`, every tick collapsed to ~0ms,
    /// and the loop spun hot until the 20s deadline while writing observable
    /// state — the family-wide freeze. Cancellation must end the wait in
    /// milliseconds, long before the deadline.
    func testCancellationExitsInsteadOfBusySpinning() async {
        let socket = FakeSocket()   // never connects
        let start = Date()
        let waiter = Task { @MainActor in
            await RealtimeSocketWait.wait(on: socket, seconds: 20,
                                          tickNanoseconds: 500_000_000,
                                          isBackgrounded: { false })
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
        waiter.cancel()
        _ = await waiter.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0,
                          "a cancelled wait must exit, not spin to the 20s deadline")
    }

    func testDeadlineBoundsTheWait() async {
        let socket = FakeSocket()   // never connects
        let start = Date()
        await RealtimeSocketWait.wait(on: socket, seconds: 0.15,
                                      tickNanoseconds: 20_000_000,
                                      isBackgrounded: { false })
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.1, "must honor the budget")
        XCTAssertLessThan(elapsed, 3.0, "must stop at the deadline")
    }

    func testBackgroundStandsTheWaitDown() async {
        let socket = FakeSocket()   // never connects
        let start = Date()
        await RealtimeSocketWait.wait(on: socket, seconds: 10,
                                      tickNanoseconds: 10_000_000,
                                      isBackgrounded: { true })
        // The 0x8BADF00D law: no socket vigil while backgrounded.
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}

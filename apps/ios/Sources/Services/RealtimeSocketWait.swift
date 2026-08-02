import Foundation
import Supabase

// MARK: - The bounded socket wait, as a TESTED law (b1197 + b1198)
//
// Three consecutive field regressions rode the same twenty lines: the join
// timebox burned on a dead socket (b1197), the cancelled wait busy-spun a
// 20-second invalidation storm and froze every phone in the family (b1198),
// and the rewritten listener missed the wait entirely (b1200). The loop is
// now ONE function behind a seam, and the failure modes that shipped are
// pinned by unit tests — the socket itself is fakeable, so cancellation,
// deadline and reconnect finally run in CI instead of on the family.

/// The seam: exactly what the wait needs to know about a socket, nothing
/// more. Production adapts the shared realtime client; tests script it.
@MainActor
protocol RealtimeSocketing {
    var isConnected: Bool { get }
    var isDisconnected: Bool { get }
    /// Fire-and-forget connect nudge (the SDK ignores it mid-connect).
    func kickConnect()
}

/// The production adapter over the shared anon realtime client.
@MainActor
struct LiveRealtimeSocket: RealtimeSocketing {
    var isConnected: Bool { realtimeAnon.status == .connected }
    var isDisconnected: Bool { realtimeAnon.status == .disconnected }
    func kickConnect() { Task { await realtimeAnon.connect() } }
}

@MainActor
enum RealtimeSocketWait {
    /// Waits (bounded) for a live socket before a join clock starts.
    ///
    /// The laws baked in, each one paid for in the field:
    ///  - already connected → return immediately (zero cost on the happy
    ///    path);
    ///  - fully disconnected → kick the connect ONCE: on a chat-first cold
    ///    entry nothing else may ever connect the socket, because
    ///    connectOnSubscribe fires from the very join this wait is holding
    ///    back (b1199);
    ///  - a cancelled sleep EXITS (`catch { return }`) — `try?` here is how
    ///    b1198 froze every phone in the family: the swallowed
    ///    CancellationError collapsed every tick to ~0ms and the loop spun
    ///    hot until the deadline;
    ///  - the background stands the wait down (the 0x8BADF00D law).
    /// `isBackgrounded` is @MainActor and has NO default on purpose: a
    /// default-argument closure is evaluated in a nonisolated context, so
    /// `{ AppLifecycle.isBackgrounded }` there is a compile error — the
    /// call sites pass it explicitly.
    static func wait(on socket: RealtimeSocketing,
                     seconds: TimeInterval,
                     tickNanoseconds: UInt64 = 500_000_000,
                     isBackgrounded: @MainActor () -> Bool) async {
        guard !socket.isConnected else { return }
        if socket.isDisconnected { socket.kickConnect() }
        let deadline = Date().addingTimeInterval(seconds)
        while !socket.isConnected, Date() < deadline, !isBackgrounded() {
            do { try await Task.sleep(nanoseconds: tickNanoseconds) }
            catch { return }
        }
    }
}

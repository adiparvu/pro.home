import XCTest
@testable import PRVIO

// Unit tests for the pending chat-reply queue in SharedDataStore — replies
// typed on a notification, parked in the App Group and drained by the app on
// its next beat. Run with Cmd+U (PRVIOTests scheme).
//
// The queue-entry contract under test (append → pop, through the REAL
// coordinated-file queue; the store exposes no per-test suite, so each test
// drains the shared queue before and after itself):
//   - target "group" (the default) stores the bare text — byte-identical to
//     the legacy text-only form, so old drains still understand new entries,
//   - "dm:<uid>" / "grp:<gid>" targets round-trip intact,
//   - a bare legacy string decodes to target "group",
//   - ":" inside the text is never mistaken for a target marker (the real
//     separator is the untypeable U+001F).
final class PendingChatReplyTests: XCTestCase {

    /// Legacy UserDefaults key — the pre-coordination on-disk location the
    /// store still drains from (a frozen contract, mirrored here on purpose).
    private let legacyKey = "prvio.pending.chatReplies"

    override func setUpWithError() throws {
        // Start from an empty queue (drains anything a previous test — or the
        // host app itself — left behind).
        _ = SharedDataStore.popPendingChatReplies()

        // The queue lives in the App Group container; if this environment
        // can't provide one, append/pop are silent no-ops — skip honestly
        // rather than fail on infrastructure.
        SharedDataStore.appendPendingChatReply("canary")
        guard !SharedDataStore.popPendingChatReplies().isEmpty else {
            throw XCTSkip("App Group container unavailable in this test environment")
        }
    }

    override func tearDown() {
        _ = SharedDataStore.popPendingChatReplies()
        UserDefaults(suiteName: SharedDataStore.suiteName)?.removeObject(forKey: legacyKey)
        super.tearDown()
    }

    // MARK: - Group target (the default)

    func testGroupTargetRoundTrip() {
        SharedDataStore.appendPendingChatReply("hello family")
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, "group")
        XCTAssertEqual(popped.first?.text, "hello family")
    }

    func testExplicitGroupTargetMatchesDefault() {
        SharedDataStore.appendPendingChatReply("hi", target: "group")
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, "group")
        XCTAssertEqual(popped.first?.text, "hi")
    }

    // MARK: - Targeted replies

    func testDMTargetRoundTrip() {
        let target = "dm:9A2B4C6D-1111-2222-3333-444455556666"
        SharedDataStore.appendPendingChatReply("hi", target: target)
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, target)
        XCTAssertEqual(popped.first?.text, "hi")
    }

    func testSubgroupTargetRoundTrip() {
        let target = "grp:0F0E0D0C-AAAA-BBBB-CCCC-DDDDEEEEFFFF"
        SharedDataStore.appendPendingChatReply("hi", target: target)
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, target)
        XCTAssertEqual(popped.first?.text, "hi")
    }

    // MARK: - Legacy compatibility

    func testLegacyBareStringDecodesAsGroup() throws {
        // A pre-coordination build queued bare strings in UserDefaults — the
        // store drains that location into the file queue on first touch.
        let ud = try XCTUnwrap(UserDefaults(suiteName: SharedDataStore.suiteName))
        ud.set(["plain old reply"], forKey: legacyKey)
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, "group")
        XCTAssertEqual(popped.first?.text, "plain old reply")
    }

    // MARK: - ":" in text is not a target marker

    func testColonInGroupTextIsNotMistakenForTarget() {
        SharedDataStore.appendPendingChatReply("dm: are you coming?")
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, "group")
        XCTAssertEqual(popped.first?.text, "dm: are you coming?")
    }

    func testColonInTargetedTextSurvivesRoundTrip() {
        SharedDataStore.appendPendingChatReply("call me: 5pm", target: "dm:peer-id")
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.count, 1)
        XCTAssertEqual(popped.first?.target, "dm:peer-id")
        XCTAssertEqual(popped.first?.text, "call me: 5pm")
    }

    // MARK: - Queue semantics

    func testPopDrainsInOrderAndEmptiesQueue() {
        SharedDataStore.appendPendingChatReply("first")
        SharedDataStore.appendPendingChatReply("second", target: "dm:peer")
        SharedDataStore.appendPendingChatReply("third", target: "grp:club")
        let popped = SharedDataStore.popPendingChatReplies()
        XCTAssertEqual(popped.map(\.text), ["first", "second", "third"])
        XCTAssertEqual(popped.map(\.target), ["group", "dm:peer", "grp:club"])
        XCTAssertTrue(SharedDataStore.popPendingChatReplies().isEmpty,
                      "pop must drain the queue")
    }
}

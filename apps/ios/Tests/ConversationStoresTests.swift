import XCTest
@testable import PRVIO

// Unit tests for ConversationClearStore and ChatMuteStore — UserDefaults-backed
// pure logic behind "clear conversation" (with cross-device cutoff sync) and
// per-conversation muting. No UI or network. Run with Cmd+U (PRVIOTests scheme).
//
// Cutoffs are driven through applyRemote(_:iso:) rather than clear(_:) so the
// tests stay pure — clear(_:) intentionally spawns a background sync Task.
final class ConversationStoresTests: XCTestCase {

    private struct Item { let date: Date? }

    private func freshID() -> String { "test.conv.\(UUID().uuidString)" }

    // MARK: - ConversationClearStore: cutoff storage

    func testClearedAtNilWhenUnset() {
        XCTAssertNil(ConversationClearStore.clearedAt(freshID()))
    }

    func testResetRemovesCutoff() {
        let id = freshID()
        ConversationClearStore.applyRemote(id, iso: "2026-01-01T00:00:00Z")
        XCTAssertNotNil(ConversationClearStore.clearedAt(id))
        ConversationClearStore.reset(id)
        XCTAssertNil(ConversationClearStore.clearedAt(id))
    }

    // MARK: - ConversationClearStore: applyRemote

    func testApplyRemoteIgnoresNilAndGarbage() {
        let id = freshID()
        ConversationClearStore.applyRemote(id, iso: nil)
        XCTAssertNil(ConversationClearStore.clearedAt(id))
        ConversationClearStore.applyRemote(id, iso: "not a date")
        XCTAssertNil(ConversationClearStore.clearedAt(id))
    }

    func testApplyRemoteSetsCutoff() throws {
        let id = freshID()
        ConversationClearStore.applyRemote(id, iso: "2026-01-01T00:00:00Z")
        let expected = ISODate.date(from: "2026-01-01T00:00:00Z")!
        let cleared = try XCTUnwrap(ConversationClearStore.clearedAt(id))
        XCTAssertEqual(cleared.timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 0.0001)
    }

    func testApplyRemoteOnlyAdvancesForward() throws {
        let id = freshID()
        ConversationClearStore.applyRemote(id, iso: "2026-06-01T00:00:00Z")
        let mid = ISODate.date(from: "2026-06-01T00:00:00Z")!

        // Earlier cutoff must be ignored (never move backward).
        ConversationClearStore.applyRemote(id, iso: "2026-01-01T00:00:00Z")
        let afterEarlier = try XCTUnwrap(ConversationClearStore.clearedAt(id))
        XCTAssertEqual(afterEarlier.timeIntervalSince1970,
                       mid.timeIntervalSince1970, accuracy: 0.0001)

        // Later cutoff advances it forward.
        ConversationClearStore.applyRemote(id, iso: "2026-12-01T00:00:00Z")
        let later = ISODate.date(from: "2026-12-01T00:00:00Z")!
        let afterLater = try XCTUnwrap(ConversationClearStore.clearedAt(id))
        XCTAssertEqual(afterLater.timeIntervalSince1970,
                       later.timeIntervalSince1970, accuracy: 0.0001)
    }

    // MARK: - ConversationClearStore: filter

    func testFilterNoCutoffKeepsEverything() {
        let id = freshID()
        let items = [Item(date: Date(timeIntervalSince1970: 0)), Item(date: Date())]
        XCTAssertEqual(ConversationClearStore.filter(items, convId: id, date: { $0.date }).count, 2)
    }

    func testFilterKeepsNewerDropsOlderAndKeepsNilDates() {
        let id = freshID()
        ConversationClearStore.applyRemote(id, iso: "2026-06-01T00:00:00Z")
        let cutoff = ISODate.date(from: "2026-06-01T00:00:00Z")!

        let newer = Item(date: cutoff.addingTimeInterval(86_400))   // 1 day after → kept
        let older = Item(date: cutoff.addingTimeInterval(-86_400))  // 1 day before → dropped
        let undated = Item(date: nil)                                // no date → kept

        let result = ConversationClearStore.filter([newer, older, undated],
                                                   convId: id, date: { $0.date })
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.date == older.date })
    }

    // MARK: - ChatMuteStore

    func testNotMutedByDefault() {
        XCTAssertFalse(ChatMuteStore.isMuted(freshID()))
    }

    func testMuteAndUnmute() {
        let id = freshID()
        ChatMuteStore.setMuted(id, true)
        XCTAssertTrue(ChatMuteStore.isMuted(id))
        ChatMuteStore.setMuted(id, false)
        XCTAssertFalse(ChatMuteStore.isMuted(id))
    }

    func testMuteIsPerConversation() {
        let a = freshID()
        let b = freshID()
        ChatMuteStore.setMuted(a, true)
        XCTAssertTrue(ChatMuteStore.isMuted(a))
        XCTAssertFalse(ChatMuteStore.isMuted(b))
        // Cleanup so the shared muted-set doesn't accumulate test ids.
        ChatMuteStore.setMuted(a, false)
    }
}

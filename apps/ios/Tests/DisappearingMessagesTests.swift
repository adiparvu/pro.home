import XCTest
@testable import PRVIO

// Unit tests for ChatDisappearStore — the disappearing-messages TTL store and
// its view-level expiry filter. Pure logic (UserDefaults + array filtering),
// no UI or network. Run in Xcode with Cmd+U (PRVIOTests scheme).
//
// Each test uses a unique conversation id so the UserDefaults-backed cases
// stay isolated from one another and from real app data.
final class DisappearingMessagesTests: XCTestCase {

    private struct Item { let date: Date? }

    private func freshID() -> String { "test.disappear.\(UUID().uuidString)" }

    // MARK: - TTL storage

    func testTTLDefaultsToZero() {
        // An id that was never configured reads back as 0 (Off).
        XCTAssertEqual(ChatDisappearStore.ttl(freshID()), 0)
    }

    func testTTLRoundTrip() {
        let id = freshID()
        ChatDisappearStore.setTTL(id, 604_800)
        XCTAssertEqual(ChatDisappearStore.ttl(id), 604_800)
    }

    // MARK: - Label lookup

    func testLabelForKnownDurations() {
        let id = freshID()
        ChatDisappearStore.setTTL(id, 86_400)
        XCTAssertEqual(ChatDisappearStore.label(id), "24 hours")
        ChatDisappearStore.setTTL(id, 604_800)
        XCTAssertEqual(ChatDisappearStore.label(id), "7 days")
        ChatDisappearStore.setTTL(id, 7_776_000)
        XCTAssertEqual(ChatDisappearStore.label(id), "90 days")
    }

    func testLabelForZeroIsOff() {
        let id = freshID()
        XCTAssertEqual(ChatDisappearStore.label(id), "Off")
    }

    func testLabelForUnknownTTLFallsBackToOff() {
        // A stored TTL that doesn't match any preset option falls back to "Off".
        let id = freshID()
        ChatDisappearStore.setTTL(id, 12_345)
        XCTAssertEqual(ChatDisappearStore.label(id), "Off")
    }

    // MARK: - Expiry filter

    func testFilterOffReturnsEverything() {
        // TTL 0 (Off) is a passthrough — nothing is filtered.
        let id = freshID()
        let items = [Item(date: Date(timeIntervalSince1970: 0)),  // ancient
                     Item(date: Date())]
        let result = ChatDisappearStore.filter(items, convId: id, date: { $0.date })
        XCTAssertEqual(result.count, 2)
    }

    func testFilterKeepsRecentDropsOld() {
        let id = freshID()
        ChatDisappearStore.setTTL(id, 86_400) // 24h window
        let recent = Item(date: Date())
        let old = Item(date: Date().addingTimeInterval(-2 * 86_400)) // 2 days ago
        let result = ChatDisappearStore.filter([recent, old], convId: id, date: { $0.date })
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result.first?.date)
    }

    func testFilterKeepsItemsWithNilDate() {
        // Items without a resolvable timestamp are treated as .distantFuture,
        // so they're never expired out.
        let id = freshID()
        ChatDisappearStore.setTTL(id, 86_400)
        let noDate = Item(date: nil)
        let old = Item(date: Date().addingTimeInterval(-10 * 86_400))
        let result = ChatDisappearStore.filter([noDate, old], convId: id, date: { $0.date })
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.date)
    }

    func testFilterKeepsItemExactlyAtCutoff() {
        // Boundary: an item dated right at the cutoff (>= comparison) is kept.
        let id = freshID()
        ChatDisappearStore.setTTL(id, 1_000)
        // Slightly inside the window to avoid clock-tick flakiness at the exact edge.
        let atEdge = Item(date: Date().addingTimeInterval(-990))
        let result = ChatDisappearStore.filter([atEdge], convId: id, date: { $0.date })
        XCTAssertEqual(result.count, 1)
    }
}

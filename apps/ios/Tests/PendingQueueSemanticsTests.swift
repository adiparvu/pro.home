import XCTest
@testable import PRVIO

// Unit tests for the drain-law queue semantics (P0) — written after the
// card-payment loss, so the exact failure that shipped is pinned forever:
// a queue entry may leave its queue only once the app could actually act on
// it. The expense queue is the strictest tier (peek → confirm), and the
// chat-mutation journal (P0b) records failed writes for replay.
//
// Same environment contract as PendingChatReplyTests: the queues live in
// the App Group container; where the test host can't provide one, skip
// honestly instead of failing on infrastructure.
final class PendingQueueSemanticsTests: XCTestCase {

    override func setUpWithError() throws {
        _ = SharedDataStore.popPendingChatMutations()
        SharedDataStore.removePendingExpenses(
            ids: Set(SharedDataStore.peekPendingExpenses().map(\.id)))

        SharedDataStore.appendPendingChatMutation("canary")
        guard !SharedDataStore.popPendingChatMutations().isEmpty else {
            throw XCTSkip("App Group container unavailable in this test environment")
        }
    }

    override func tearDown() {
        _ = SharedDataStore.popPendingChatMutations()
        SharedDataStore.removePendingExpenses(
            ids: Set(SharedDataStore.peekPendingExpenses().map(\.id)))
        super.tearDown()
    }

    private func expense(_ id: UUID = UUID(), merchant: String = "Lidl",
                         amount: Double = 12.5) -> SharedDataStore.PendingExpense {
        SharedDataStore.PendingExpense(id: id, merchant: merchant, amount: amount,
                                       card: "Visa", note: nil, date: "2026-08-01")
    }

    // MARK: - Expense queue: peek is non-destructive, removal is explicit

    func testPeekDoesNotDrain() {
        SharedDataStore.appendPendingExpense(expense())
        XCTAssertEqual(SharedDataStore.peekPendingExpenses().count, 1)
        // The regression that lost real payments: a second read must still
        // see the entry — peeking is not popping.
        XCTAssertEqual(SharedDataStore.peekPendingExpenses().count, 1)
    }

    func testRemoveConfirmsOnlyTheLandedIds() {
        let landed = expense(merchant: "Kaufland")
        let failed = expense(merchant: "OMV")
        SharedDataStore.appendPendingExpense(landed)
        SharedDataStore.appendPendingExpense(failed)
        SharedDataStore.removePendingExpenses(ids: [landed.id])
        let left = SharedDataStore.peekPendingExpenses()
        XCTAssertEqual(left.map(\.id), [failed.id])
    }

    func testRemoveWithNoIdsIsANoOp() {
        SharedDataStore.appendPendingExpense(expense())
        SharedDataStore.removePendingExpenses(ids: [])
        XCTAssertEqual(SharedDataStore.peekPendingExpenses().count, 1)
    }

    func testIdenticalTapsStayDistinctByEntryId() {
        // Two same-shop-same-amount-same-day taps are two REAL payments —
        // the embedded id keeps them distinct in the unique-append store.
        SharedDataStore.appendPendingExpense(expense(merchant: "Profi", amount: 5))
        SharedDataStore.appendPendingExpense(expense(merchant: "Profi", amount: 5))
        XCTAssertEqual(SharedDataStore.peekPendingExpenses().count, 2)
    }

    func testDuplicateAppendOfTheSameEntryCollapses() {
        let e = expense()
        SharedDataStore.appendPendingExpense(e)
        SharedDataStore.appendPendingExpense(e)
        XCTAssertEqual(SharedDataStore.peekPendingExpenses().count, 1)
    }

    // MARK: - Chat mutation journal (P0b)

    func testFlagIntentRoundTripsWithAbsoluteValue() throws {
        let id = UUID()
        ChatMutationJournal.recordFlag(rpc: "dm_set_pin", messageId: id, value: true)
        let raw = SharedDataStore.popPendingChatMutations()
        XCTAssertEqual(raw.count, 1)
        let entry = try JSONDecoder().decode(ChatMutationJournal.self,
                                             from: Data(raw[0].utf8))
        XCTAssertEqual(entry.kind, .flag)
        XCTAssertEqual(entry.messageId, id)
        XCTAssertEqual(entry.rpc, "dm_set_pin")
        XCTAssertEqual(entry.value, true)
    }

    func testReactionIntentCarriesEverythingReplayNeeds() throws {
        let msg = UUID(), prop = UUID(), user = UUID()
        ChatMutationJournal.recordReaction(messageId: msg, propertyId: prop,
                                           userId: user, reactorName: "Adi",
                                           emoji: "❤️", insertNew: true)
        let raw = SharedDataStore.popPendingChatMutations()
        let entry = try JSONDecoder().decode(ChatMutationJournal.self,
                                             from: Data(raw[0].utf8))
        XCTAssertEqual(entry.kind, .reaction)
        XCTAssertEqual(entry.propertyId, prop)
        XCTAssertEqual(entry.userId, user)
        XCTAssertEqual(entry.emoji, "❤️")
        XCTAssertEqual(entry.insertNew, true)
    }

    func testEditAndTombstoneCarryTheirTable() throws {
        let id = UUID()
        ChatMutationJournal.recordEdit(table: "messages", messageId: id,
                                       body: "corectat", editedAtISO: "2026-08-01T10:00:00Z")
        ChatMutationJournal.recordTombstone(table: "messages", messageId: id)
        let entries = try SharedDataStore.popPendingChatMutations().map {
            try JSONDecoder().decode(ChatMutationJournal.self, from: Data($0.utf8))
        }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].kind, .edit)
        XCTAssertEqual(entries[0].body, "corectat")
        XCTAssertEqual(entries[1].kind, .tombstone)
        XCTAssertTrue(entries.allSatisfy { $0.table == "messages" })
    }

    func testIdenticalIntentRecordedTwiceCollapses() {
        let id = UUID()
        // Same JSON (createdAt differs per record) — so two records of the
        // same tombstone are two entries ONLY if their payloads differ;
        // the unique-append still collapses byte-identical requeues, which
        // is what replayAll produces when a replay fails.
        ChatMutationJournal.recordTombstone(table: "messages", messageId: id)
        let raw = SharedDataStore.popPendingChatMutations()
        SharedDataStore.appendPendingChatMutation(raw[0])
        SharedDataStore.appendPendingChatMutation(raw[0])
        XCTAssertEqual(SharedDataStore.popPendingChatMutations().count, 1)
    }
}

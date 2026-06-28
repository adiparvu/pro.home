import XCTest
@testable import PRVIO

@MainActor
final class OutboxTests: XCTestCase {

    private func freshOutbox() -> OfflineOutbox {
        // Unique file per test run so cases don't interfere.
        let name = "test_outbox_\(UUID().uuidString).json"
        return OfflineOutbox(filename: name)
    }

    func testEnqueueAndFilterByProperty() {
        let outbox = freshOutbox()
        let a = UUID(), b = UUID()
        outbox.enqueue(PendingMessage(propertyId: a, senderName: "Me", body: "1"))
        outbox.enqueue(PendingMessage(propertyId: a, senderName: "Me", body: "2"))
        outbox.enqueue(PendingMessage(propertyId: b, senderName: "Me", body: "3"))

        XCTAssertEqual(outbox.pending.count, 3)
        XCTAssertEqual(outbox.pending(for: a).count, 2)
        XCTAssertEqual(outbox.pending(for: b).count, 1)
    }

    func testRemove() {
        let outbox = freshOutbox()
        let pid = UUID()
        let m = PendingMessage(propertyId: pid, senderName: "Me", body: "x")
        outbox.enqueue(m)
        XCTAssertEqual(outbox.pending.count, 1)
        outbox.remove(m.id)
        XCTAssertTrue(outbox.pending.isEmpty)
    }

    func testPendingSortedByDate() {
        let outbox = freshOutbox()
        let pid = UUID()
        let older = PendingMessage(propertyId: pid, senderName: "Me", body: "old",
                                   createdAt: Date(timeIntervalSince1970: 1000))
        let newer = PendingMessage(propertyId: pid, senderName: "Me", body: "new",
                                   createdAt: Date(timeIntervalSince1970: 2000))
        outbox.enqueue(newer)
        outbox.enqueue(older)
        XCTAssertEqual(outbox.pending(for: pid).map(\.body), ["old", "new"])
    }

    func testPersistenceAcrossInstances() {
        let name = "test_persist_\(UUID().uuidString).json"
        let pid = UUID()
        do {
            let outbox = OfflineOutbox(filename: name)
            outbox.enqueue(PendingMessage(propertyId: pid, senderName: "Me", body: "persisted"))
        }
        // A new instance with the same file should load the queued message.
        let reloaded = OfflineOutbox(filename: name)
        XCTAssertEqual(reloaded.pending(for: pid).first?.body, "persisted")
    }
}

import XCTest
@testable import PRVIO

final class ModelTests: XCTestCase {

    private func message(attachmentType: String?) -> Message {
        Message(id: UUID(), propertyId: nil, senderId: nil, senderName: "x", body: "b",
                attachmentUrl: nil, attachmentType: attachmentType, latitude: nil, longitude: nil,
                mentionedIds: [], replyTo: nil, pinned: nil, isMarked: nil, editedAt: nil,
                deletedForAll: nil, createdAt: "2026-06-28T18:00:00Z")
    }

    func testMessageTypeFlags() {
        XCTAssertTrue(message(attachmentType: "image").isImageMessage)
        XCTAssertTrue(message(attachmentType: "audio").isAudioMessage)
        XCTAssertTrue(message(attachmentType: "location").isLocationMessage)
        XCTAssertTrue(message(attachmentType: "file").isFileMessage)
        XCTAssertTrue(message(attachmentType: "sticker").isStickerMessage)
        XCTAssertTrue(message(attachmentType: "poll").isPollMessage)
        XCTAssertTrue(message(attachmentType: "event").isEventMessage)

        let plain = message(attachmentType: nil)
        XCTAssertFalse(plain.isImageMessage)
        XCTAssertFalse(plain.isPollMessage)
    }

    func testMessageTimeDisplayNonEmpty() {
        XCTAssertFalse(message(attachmentType: nil).timeDisplay.isEmpty)
    }

    func testDirectMessageDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sender_name":"Ana","recipient_name":"Me",
         "body":"salut","created_at":"2026-06-28T18:00:00Z","pinned":true,"is_marked":false}
        """.data(using: .utf8)!
        let dm = try JSONDecoder().decode(DirectMessage.self, from: json)
        XCTAssertEqual(dm.senderName, "Ana")
        XCTAssertEqual(dm.body, "salut")
        XCTAssertEqual(dm.pinned, true)
        XCTAssertFalse(dm.timeDisplay.isEmpty)
        // delivery receipt fields are optional and absent here
        XCTAssertNil(dm.deliveredAt)
        XCTAssertNil(dm.readAt)
    }

    func testDirectMessageDecodesDeliveryReceipts() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sender_name":"Me","recipient_name":"Ana",
         "body":"hey","created_at":"2026-06-28T18:00:00Z",
         "delivered_at":"2026-06-28T18:00:05Z","read_at":"2026-06-28T18:01:00Z"}
        """.data(using: .utf8)!
        let dm = try JSONDecoder().decode(DirectMessage.self, from: json)
        XCTAssertNotNil(dm.deliveredAt)
        XCTAssertNotNil(dm.readAt)
    }
}

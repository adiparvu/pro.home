import XCTest
@testable import PRVIO

final class MessagingExtrasTests: XCTestCase {

    // MARK: - Theme

    func testChatThemeProperties() {
        let def = ChatTheme.theme(for: "appDefault")
        XCTAssertNil(def.backgroundColors)
        XCTAssertFalse(def.isDark)

        let dark = ChatTheme.theme(for: "dark")
        XCTAssertNotNil(dark.backgroundColors)
        XCTAssertTrue(dark.isDark)

        XCTAssertGreaterThanOrEqual(ChatTheme.all.count, 5)
    }

    // MARK: - Link detection edge cases

    func testFirstDetectedURLReturnsFirst() {
        XCTAssertEqual(firstDetectedURL(in: "a https://one.com then https://two.com")?.host, "one.com")
    }

    func testFirstDetectedURLRejectsNonHTTP() {
        XCTAssertNil(firstDetectedURL(in: "mailto:test@example.com"))
        XCTAssertNil(firstDetectedURL(in: "ftp://files.example.com"))
    }

    // MARK: - Event date formatting

    func testChatEventDateDisplayFormatted() {
        let ev = ChatEvent(t: "X", d: nil, date: "2026-06-28T18:00:00Z", loc: nil)
        XCTAssertFalse(ev.dateDisplay.isEmpty)
        XCTAssertNotEqual(ev.dateDisplay, ev.date)   // formatted, not raw ISO
    }

    func testChatEventBadDateFallsBack() {
        let ev = ChatEvent(t: "X", d: nil, date: "garbage", loc: nil)
        XCTAssertNil(ev.parsedDate)
        XCTAssertEqual(ev.dateDisplay, "garbage")
    }

    // MARK: - Read receipts / reactions decoding

    func testMessageReadDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","message_id":"\(UUID().uuidString)","reader_name":"Ana","read_at":"2026-06-28T18:00:00Z"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(MessageRead.self, from: json)
        XCTAssertEqual(r.readerName, "Ana")
        XCTAssertFalse(r.readTimeDisplay.isEmpty)
    }

    func testMessageReactionDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","message_id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)","reactor_name":"Ana","emoji":"❤️","created_at":"2026-06-28T18:00:00Z"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(MessageReaction.self, from: json)
        XCTAssertEqual(r.emoji, "❤️")
        XCTAssertEqual(r.reactorName, "Ana")
    }

    // MARK: - Conversation entry time formatting

    func testConversationEntryFormattedTime() {
        let none = ConversationEntry(id: "g", name: "G", preview: "p", date: nil,
                                     unread: 0, isGroup: true, member: nil)
        XCTAssertEqual(none.formattedTime, "")

        let today = ConversationEntry(id: "g", name: "G", preview: "p", date: Date(),
                                      unread: 2, isGroup: true, member: nil)
        XCTAssertFalse(today.formattedTime.isEmpty)
    }
}

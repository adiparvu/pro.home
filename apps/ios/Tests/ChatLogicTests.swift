import XCTest
@testable import PRVIO

// Unit tests for pure chat logic (no UI, no network).
// Run in Xcode with Cmd+U (PRVIOTests scheme).
final class ChatLogicTests: XCTestCase {

    // MARK: - Poll payload

    func testChatPollRoundTrip() {
        let poll = ChatPoll(q: "Pizza diseară?", opts: ["Da", "Nu", "Poate"], multi: true)
        let encoded = poll.encoded()
        XCTAssertNotNil(encoded)
        let decoded = ChatPoll.decode(encoded)
        XCTAssertEqual(decoded?.q, "Pizza diseară?")
        XCTAssertEqual(decoded?.opts, ["Da", "Nu", "Poate"])
        XCTAssertEqual(decoded?.multi, true)
    }

    func testChatPollDecodeInvalid() {
        XCTAssertNil(ChatPoll.decode("not valid json"))
        XCTAssertNil(ChatPoll.decode(nil))
    }

    // MARK: - Event payload

    func testChatEventRoundTrip() {
        let ev = ChatEvent(t: "Grătar", d: "La terasă", date: "2026-06-28T18:00:00Z", loc: "Acasă")
        let decoded = ChatEvent.decode(ev.encoded())
        XCTAssertEqual(decoded?.t, "Grătar")
        XCTAssertEqual(decoded?.d, "La terasă")
        XCTAssertEqual(decoded?.loc, "Acasă")
        XCTAssertNotNil(decoded?.parsedDate)
    }

    func testChatEventOptionalFields() {
        let ev = ChatEvent(t: "Ședință", d: nil, date: "2026-06-28T10:00:00Z", loc: nil)
        let decoded = ChatEvent.decode(ev.encoded())
        XCTAssertEqual(decoded?.t, "Ședință")
        XCTAssertNil(decoded?.d)
        XCTAssertNil(decoded?.loc)
    }

    /// Bodies written before the end/all-day upgrade must keep decoding —
    /// old messages live forever in the database.
    func testChatEventLegacyBodyStillDecodes() {
        let legacy = #"{"t":"Grătar","d":"La terasă","date":"2026-06-28T18:00:00Z","loc":"Acasă"}"#
        let decoded = ChatEvent.decode(legacy)
        XCTAssertEqual(decoded?.t, "Grătar")
        XCTAssertNil(decoded?.end)
        XCTAssertNil(decoded?.allDay)
        XCTAssertFalse(decoded?.isAllDay ?? true)
        XCTAssertNotNil(decoded?.parsedDate)
    }

    func testChatEventV2RoundTripKeepsEndAndAllDay() {
        let ev = ChatEvent(t: "Concediu", d: nil, date: "2026-07-01T00:00:00Z", loc: nil,
                           end: "2026-07-03T00:00:00Z", allDay: true)
        let decoded = ChatEvent.decode(ev.encoded())
        XCTAssertEqual(decoded?.end, "2026-07-03T00:00:00Z")
        XCTAssertEqual(decoded?.allDay, true)
        XCTAssertNotNil(decoded?.parsedEnd)
    }

    func testChatEventDraftPayloadNormalizes() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        // End before start must clamp — the wire payload never carries an
        // inverted range.
        let draft = ChatEventDraft(title: "Test", details: "", start: start,
                                   end: start.addingTimeInterval(-600),
                                   isAllDay: false, location: "")
        let payload = draft.payload()
        XCTAssertNil(payload.d)
        XCTAssertNil(payload.loc)
        XCTAssertNil(payload.allDay)
        guard let s = payload.parsedDate, let e = payload.parsedEnd else {
            return XCTFail("payload dates must parse")
        }
        XCTAssertGreaterThanOrEqual(e, s)
    }

    // MARK: - Offline outbox model

    func testPendingMessageCodableGroup() throws {
        let pid = UUID()
        let pm = PendingMessage(propertyId: pid, senderName: "Eu", body: "salut",
                                mentionedIds: ["a", "b"])
        let data = try JSONEncoder().encode(pm)
        let back = try JSONDecoder().decode(PendingMessage.self, from: data)
        XCTAssertEqual(back.propertyId, pid)
        XCTAssertNil(back.recipientName)
        XCTAssertEqual(back.body, "salut")
        XCTAssertEqual(back.mentionedIds, ["a", "b"])
    }

    func testPendingMessageCodableDM() throws {
        let pid = UUID()
        let reply = UUID()
        let pm = PendingMessage(propertyId: pid, senderName: "Eu", recipientName: "Ana",
                                body: "ce faci?", replyTo: reply)
        let back = try JSONDecoder().decode(PendingMessage.self, from: JSONEncoder().encode(pm))
        XCTAssertEqual(back.recipientName, "Ana")
        XCTAssertEqual(back.replyTo, reply)
    }

    // MARK: - Link detection

    func testLinkDetectionFindsURL() {
        XCTAssertEqual(firstDetectedURL(in: "vezi https://apple.com aici")?.host, "apple.com")
        XCTAssertNotNil(firstDetectedURL(in: "http://example.org"))
    }

    func testLinkDetectionIgnoresNonLinks() {
        XCTAssertNil(firstDetectedURL(in: "fără niciun link"))
        XCTAssertNil(firstDetectedURL(in: ""))
    }

    // MARK: - Chat theme

    func testChatThemeFallback() {
        XCTAssertEqual(ChatTheme.theme(for: "does-not-exist").id, "appDefault")
        XCTAssertEqual(ChatTheme.theme(for: "dark").id, "dark")
    }
}

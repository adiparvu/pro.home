import XCTest
@testable import PRVIO

// Unit tests for MessageSubject — the U+001E (record separator) encoding that
// carries an optional subject line inside the plain-text chat `body` column.
// Pure string logic, no UI or network. Run with Cmd+U (PRVIOTests scheme).
//
// The contract under test:
//   - a blank subject encodes to the text unchanged (no marker),
//   - marker-free bodies (every pre-feature message) parse to (nil, body),
//   - a degenerate leading marker is plain text, never an empty subject,
//   - strip(_:) renders one line and never lets U+001E reach a label.
final class MessageSubjectTests: XCTestCase {

    private let sep = String(MessageSubject.separator)

    // MARK: - encode

    func testEncodeBlankSubjectReturnsTextUnchanged() {
        let text = "see you at 7"
        let encoded = MessageSubject.encode(subject: "", text: text)
        XCTAssertEqual(encoded, text)
        XCTAssertFalse(encoded.contains(MessageSubject.separator))
    }

    func testEncodeWhitespaceOnlySubjectReturnsTextUnchanged() {
        let text = "see you at 7"
        let encoded = MessageSubject.encode(subject: "  \n\t ", text: text)
        XCTAssertEqual(encoded, text)
        XCTAssertFalse(encoded.contains(MessageSubject.separator))
    }

    // MARK: - encode → parse round-trip

    func testEncodeParseRoundTrip() {
        let encoded = MessageSubject.encode(subject: "Dinner plan", text: "at 7, bring wine")
        let parsed = MessageSubject.parse(encoded)
        XCTAssertEqual(parsed.subject, "Dinner plan")
        XCTAssertEqual(parsed.text, "at 7, bring wine")
    }

    func testEncodeTrimsSubjectBeforeRoundTrip() {
        let encoded = MessageSubject.encode(subject: "  Dinner plan \n", text: "at 7")
        let parsed = MessageSubject.parse(encoded)
        XCTAssertEqual(parsed.subject, "Dinner plan")
        XCTAssertEqual(parsed.text, "at 7")
    }

    func testEncodeParseRoundTripWithEmptyText() {
        let encoded = MessageSubject.encode(subject: "Heads up", text: "")
        let parsed = MessageSubject.parse(encoded)
        XCTAssertEqual(parsed.subject, "Heads up")
        XCTAssertEqual(parsed.text, "")
    }

    // MARK: - parse

    func testParseLegacyBodyWithoutMarkerIsNilSubject() {
        let body = "plain message sent before the feature existed"
        let parsed = MessageSubject.parse(body)
        XCTAssertNil(parsed.subject)
        XCTAssertEqual(parsed.text, body)
    }

    func testParseDegenerateLeadingMarkerIsPlainText() {
        // "\u{1E}text" has an EMPTY subject — that is plain text, not a subject.
        let parsed = MessageSubject.parse(sep + "text")
        XCTAssertNil(parsed.subject)
        XCTAssertEqual(parsed.text, "text")
    }

    func testParseBareMarkerIsEmptyPlainText() {
        let parsed = MessageSubject.parse(sep)
        XCTAssertNil(parsed.subject)
        XCTAssertEqual(parsed.text, "")
    }

    // MARK: - strip

    func testStripJoinsSubjectAndTextWithEmDash() {
        XCTAssertEqual(MessageSubject.strip("s\(sep)t"), "s — t")
    }

    func testStripEmptyTextReturnsSubjectOnly() {
        XCTAssertEqual(MessageSubject.strip("Subject\(sep)"), "Subject")
    }

    func testStripMarkerFreeBodyUnchanged() {
        let body = "just a normal message"
        XCTAssertEqual(MessageSubject.strip(body), body)
    }

    func testStripDegenerateLeadingMarkerReturnsText() {
        XCTAssertEqual(MessageSubject.strip(sep + "text"), "text")
    }

    func testStripNeverLeavesSeparatorInOutput() {
        let bodies = [
            MessageSubject.encode(subject: "Subject", text: "text"),
            MessageSubject.encode(subject: "S", text: ""),
            "s\(sep)t",          // subject + text
            "\(sep)text",        // degenerate leading marker
            sep,                 // bare marker
            "subject\(sep)",     // subject, empty text
            "no marker at all",  // legacy body
        ]
        for body in bodies {
            let stripped = MessageSubject.strip(body)
            XCTAssertFalse(stripped.contains(MessageSubject.separator),
                           "strip left U+001E in output for body: \(body.debugDescription)")
        }
    }
}

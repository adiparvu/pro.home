import XCTest
@testable import PRVIO

// Unit tests for the shared ISO8601 date-parsing helpers (ISODate).
// Pure logic, no UI or network. Run in Xcode with Cmd+U (PRVIOTests scheme).
//
// Assertions are anchored to the Unix epoch and use timezone-independent
// checks so they stay deterministic across CI machines and locales.
final class DateParsingTests: XCTestCase {

    // MARK: - Plain (no fractional seconds)

    func testParsesPlainInternetDateTime() {
        // The plain formatter path: "…T00:00:00Z" has no fractional seconds.
        let d = ISODate.date(from: "1970-01-01T00:00:00Z")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.timeIntervalSince1970, 0, accuracy: 0.0001)
    }

    func testParsesPlainNonEpoch() {
        // 2000-01-01T00:00:00Z == 946684800s since the Unix epoch.
        let d = ISODate.date(from: "2000-01-01T00:00:00Z")
        XCTAssertEqual(d?.timeIntervalSince1970, 946684800, accuracy: 0.0001)
    }

    // MARK: - Fractional seconds

    func testParsesFractionalSeconds() {
        // The fractional formatter path: ".500" must be honored.
        let d = ISODate.date(from: "1970-01-01T00:00:00.500Z")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.timeIntervalSince1970, 0.5, accuracy: 0.0001)
    }

    func testFractionalAndPlainAgreeOnSameInstant() {
        // ".000" (fractional path) and no-fraction (plain path) are the same instant.
        let a = ISODate.date(from: "2026-06-28T18:00:00.000Z")
        let b = ISODate.date(from: "2026-06-28T18:00:00Z")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(a?.timeIntervalSince1970, b?.timeIntervalSince1970)
    }

    // MARK: - Invalid input

    func testRejectsGarbage() {
        XCTAssertNil(ISODate.date(from: "not a date"))
    }

    func testRejectsEmptyString() {
        XCTAssertNil(ISODate.date(from: ""))
    }

    func testRejectsDateOnly() {
        // A bare calendar date without a time component is not a full internet date-time.
        XCTAssertNil(ISODate.date(from: "2026-06-28"))
    }

    // MARK: - Time-only display formatter

    func testTimeOnlyProducesHHmmShape() {
        // Output is timezone-dependent, so assert the "HH:mm" shape, not exact digits.
        let s = ISODate.timeOnly.string(from: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(s.count, 5)
        XCTAssertNotNil(s.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression))
    }
}

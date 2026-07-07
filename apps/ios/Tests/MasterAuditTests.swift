import XCTest
@testable import PRVIO

// Tests for the authorities the master audit found uncovered: the account-ID
// formatter/matcher, the expense forecast, the ICS calendar export, the
// server-notification localizer, and the document-scan date intelligence.
// All pure logic — no network, no UI.

// MARK: - AccountID

final class AccountIDTests: XCTestCase {
    private let id = UUID(uuidString: "3F2A9C1B-0000-4000-8000-000000000000")!

    func testDisplayIsBrandPrefixPlusFirstGroupUppercased() {
        XCTAssertEqual(AccountID.display(for: id), "PRVIO-3F2A9C1B")
    }

    func testDisplayIsDeterministic() {
        XCTAssertEqual(AccountID.display(for: id), AccountID.display(for: id))
    }

    func testMatchesFullForm() {
        XCTAssertTrue(AccountID.matches("PRVIO-3F2A9C1B", userId: id))
    }

    func testMatchesBareHexAndLowercase() {
        XCTAssertTrue(AccountID.matches("3f2a9c1b", userId: id))
        XCTAssertTrue(AccountID.matches("prvio 3f2a", userId: id))
    }

    func testShortQueriesNeverMatch() {
        XCTAssertFalse(AccountID.matches("3F2", userId: id))
        XCTAssertFalse(AccountID.matches("PRVIO-", userId: id))
        XCTAssertFalse(AccountID.matches("", userId: id))
    }

    func testWrongPrefixDoesNotMatch() {
        XCTAssertFalse(AccountID.matches("ABCD1234", userId: id))
    }
}

// MARK: - ExpenseForecast

final class ExpenseForecastTests: XCTestCase {
    /// Fixed "now": 2026-07-15, so the six full months window is Jan–Jun.
    private var now: Date { AppDate.day(from: "2026-07-15")! }

    private func record(_ amount: Double, _ currency: String, _ date: String,
                        type: String = "expense", category: String = "utilities") -> FinancialRecord {
        FinancialRecord(id: UUID(), propertyId: UUID(), title: "t", amount: amount,
                        currency: currency, type: type, category: category,
                        date: date, description: nil, createdAt: "2026-01-01T00:00:00Z")
    }

    func testEmptyRecordsProduceNoForecast() {
        XCTAssertTrue(ExpenseForecast.compute(records: [], now: now).isEmpty)
    }

    func testAverageAndRangeOverMonthsWithData() {
        let records = [
            record(100, "RON", "2026-05-10"),
            record(300, "RON", "2026-06-10"),
        ]
        let f = ExpenseForecast.compute(records: records, now: now)
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].code, "RON")
        XCTAssertEqual(f[0].average, 200, accuracy: 0.01)
        XCTAssertEqual(f[0].low, 100, accuracy: 0.01)
        XCTAssertEqual(f[0].high, 300, accuracy: 0.01)
        XCTAssertEqual(f[0].monthsOfData, 2)
    }

    func testSingleMonthOfHistoryIsAnAnecdoteNotAForecast() {
        let records = [record(100, "EUR", "2026-06-10")]
        XCTAssertTrue(ExpenseForecast.compute(records: records, now: now).isEmpty)
    }

    func testCurrenciesNeverMix() {
        let records = [
            record(100, "RON", "2026-05-10"), record(100, "RON", "2026-06-10"),
            record(9000, "EUR", "2026-05-11"), record(9000, "EUR", "2026-06-11"),
        ]
        let f = ExpenseForecast.compute(records: records, now: now)
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f.first?.code, "EUR") // biggest spender first
        XCTAssertEqual(f.first(where: { $0.code == "RON" })?.average ?? 0, 100, accuracy: 0.01)
    }

    func testCurrentMonthAndIncomeAreExcluded() {
        let records = [
            record(100, "RON", "2026-05-10"),
            record(100, "RON", "2026-06-10"),
            record(999, "RON", "2026-07-05"),                    // current month
            record(999, "RON", "2026-06-12", type: "income"),    // income
        ]
        let f = ExpenseForecast.compute(records: records, now: now)
        XCTAssertEqual(f[0].average, 100, accuracy: 0.01)
    }
}

// MARK: - HouseCalendarICS

final class HouseCalendarICSTests: XCTestCase {
    private func task(title: String, due: String?, status: String = "pending") throws -> MaintenanceTask {
        var json = """
        {"id":"\(UUID().uuidString)","property_id":"\(UUID().uuidString)",
         "title":\(String(data: try JSONEncoder().encode(title), encoding: .utf8)!),
         "category":"maintenance","priority":"medium","status":"\(status)",
         "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"
        """
        if let due { json += ",\"due_date\":\"\(due)\"" }
        json += "}"
        return try JSONDecoder().decode(MaintenanceTask.self, from: Data(json.utf8))
    }

    func testBuildEmitsOneEventPerOpenDatedTask() throws {
        let tasks = [try task(title: "Curăță jgheaburile", due: "2026-08-01"),
                     try task(title: "No due date", due: nil),
                     try task(title: "Done", due: "2026-08-02", status: "completed")]
        let ics = HouseCalendarICS.build(tasks: tasks, documents: [], appliances: [], members: [])
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR"))
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 1)
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20260801"))
        XCTAssertTrue(ics.contains("END:VCALENDAR"))
    }

    func testSpecialCharactersAreEscapedPerRFC5545() throws {
        let tasks = [try task(title: "Verifică boiler; filtre, țevi", due: "2026-09-01")]
        let ics = HouseCalendarICS.build(tasks: tasks, documents: [], appliances: [], members: [])
        XCTAssertTrue(ics.contains("SUMMARY:Verifică boiler\\; filtre\\, țevi"))
    }

    func testDueDateWithTimeSuffixStillExports() throws {
        let tasks = [try task(title: "Cu oră", due: "2026-10-05 14:30")]
        let ics = HouseCalendarICS.build(tasks: tasks, documents: [], appliances: [], members: [])
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20261005"))
    }

    func testNothingDatedMeansNoFile() {
        XCTAssertNil(HouseCalendarICS.writeFile(tasks: [], documents: [], appliances: [], members: []))
    }
}

// MARK: - ServerNotificationLocalizer

final class ServerNotificationLocalizerTests: XCTestCase {
    func testUnknownTitlePassesThroughUnchanged() {
        XCTAssertEqual(ServerNotificationLocalizer.title("Something the server never sends"),
                       "Something the server never sends")
    }

    func testNilBodyStaysNil() {
        XCTAssertNil(ServerNotificationLocalizer.body(nil))
    }

    func testUnknownBodyPassesThroughUnchanged() {
        let raw = "A completely custom body 123."
        XCTAssertEqual(ServerNotificationLocalizer.body(raw), raw)
    }

    func testDigestCountSegmentIsTransformedAndKeepsTheNumber() {
        let raw = "3 tasks overdue. "
        let out = ServerNotificationLocalizer.body(raw) ?? ""
        XCTAssertTrue(out.contains("3"))
        XCTAssertNotEqual(out, raw)
    }
}

// MARK: - DocumentScanIntelligence

final class DocumentScanIntelligenceTests: XCTestCase {
    private func day(_ date: Date?) -> String? {
        date.map { AppDate.dayString(from: $0) }
    }

    func testKeywordAnchoredFutureDateWins() {
        let lines = ["POLIȚĂ DE ASIGURARE",
                     "Emisă la 01.02.2024",
                     "Valabil până la 15.03.2030"]
        XCTAssertEqual(day(DocumentScanIntelligence.detectExpiry(in: lines)), "2030-03-15")
    }

    func testPastDatesAreNeverAnExpiry() {
        let lines = ["Contract semnat la 10.01.2019", "Data emiterii 05.06.2020"]
        XCTAssertNil(DocumentScanIntelligence.detectExpiry(in: lines))
    }

    func testISOFormatIsAccepted() {
        let lines = ["Expiration: 2031-12-31"]
        XCTAssertEqual(day(DocumentScanIntelligence.detectExpiry(in: lines)), "2031-12-31")
    }

    func testSuggestNamePicksFirstSubstantialLine() {
        let name = DocumentScanIntelligence.suggestName(from: ["12345", "  ", "Asigurare locuință Groupama", "alte rânduri"])
        XCTAssertEqual(name, "Asigurare locuință Groupama")
    }
}

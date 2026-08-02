import XCTest
@testable import PRVIO

// Unit tests for PlantWeatherCare — the pure weather → watering-due rules.
// Pure logic, no UI or network (mirrors DateParsingTests). Dates are anchored
// to fixed instants and a UTC gregorian calendar is injected so results stay
// deterministic across CI machines, locales, and DST transitions.
final class PlantWeatherCareTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2025-06-15T15:06:40Z — an arbitrary fixed baseline due date.
    private let baseline = Date(timeIntervalSince1970: 1_750_000_000)
    private let day: TimeInterval = 86_400

    private let rain = PlantWeatherCare.Conditions(rainLikely: true, highTempC: 22)
    private let heat = PlantWeatherCare.Conditions(rainLikely: false, highTempC: 34)
    private let mild = PlantWeatherCare.Conditions(rainLikely: false, highTempC: 21)

    private func adjust(_ placement: String?,
                        _ conditions: PlantWeatherCare.Conditions?) -> PlantWeatherCare.Adjustment {
        PlantWeatherCare.adjustedDue(baseline: baseline, placement: placement,
                                     conditions: conditions, calendar: calendar)
    }

    // MARK: - Rain

    func testRainPostponesOutdoorPlantByOneDay() {
        let adj = adjust("outdoor", rain)
        XCTAssertEqual(adj.dueDate.timeIntervalSince(baseline), day, accuracy: 1)
        XCTAssertEqual(adj.reason, .rainPostponed)
    }

    func testRainNeverTouchesIndoorPlant() {
        // The core conservative promise: rain does not reach a windowsill.
        let adj = adjust("indoor", rain)
        XCTAssertEqual(adj.dueDate, baseline)
        XCTAssertNil(adj.reason)
    }

    // MARK: - Heat

    func testHeatAdvancesOutdoorPlantByOneDay() {
        let adj = adjust("outdoor", heat)
        XCTAssertEqual(adj.dueDate.timeIntervalSince(baseline), -day, accuracy: 1)
        XCTAssertEqual(adj.reason, .heatAdvanced)
    }

    func testHeatThresholdIsInclusive() {
        // Exactly 30 °C counts — "≥", not ">".
        let adj = adjust("outdoor", .init(rainLikely: false, highTempC: 30))
        XCTAssertEqual(adj.reason, .heatAdvanced)
    }

    func testHeatLeavesIndoorPlantAlone() {
        let adj = adjust("indoor", heat)
        XCTAssertEqual(adj.dueDate, baseline)
        XCTAssertNil(adj.reason)
    }

    // MARK: - No adjustment paths

    func testMildWeatherChangesNothing() {
        let adj = adjust("outdoor", mild)
        XCTAssertEqual(adj.dueDate, baseline)
        XCTAssertNil(adj.reason)
    }

    func testUnknownAndBothPlacementsNeverMove() {
        // nil and "both" are not plainly outdoor — a schedule must never
        // shift on a guess about where the plant stands today.
        for placement in [nil, "both"] {
            for conditions in [rain, heat] {
                let adj = adjust(placement, conditions)
                XCTAssertEqual(adj.dueDate, baseline)
                XCTAssertNil(adj.reason)
            }
        }
    }

    func testNilConditionsChangeNothing() {
        // Missing/stale weather means no vote at all, even outdoors.
        let adj = adjust("outdoor", nil)
        XCTAssertEqual(adj.dueDate, baseline)
        XCTAssertNil(adj.reason)
    }

    // MARK: - Precedence and clamp

    func testRainWinsOverHeat() {
        // Rain during a heat wave delivers exactly the water the heat would
        // have demanded sooner — postpone, never advance.
        let stormyScorcher = PlantWeatherCare.Conditions(rainLikely: true, highTempC: 38)
        let adj = adjust("outdoor", stormyScorcher)
        XCTAssertEqual(adj.reason, .rainPostponed)
        XCTAssertEqual(adj.dueDate.timeIntervalSince(baseline), day, accuracy: 1)
    }

    func testAdjustmentIsClampedToOneDayEitherWay() {
        // However extreme the inputs, the shift is at most a single day.
        let extremes: [PlantWeatherCare.Conditions] = [
            .init(rainLikely: true, highTempC: 45),
            .init(rainLikely: false, highTempC: 45),
            .init(rainLikely: true, highTempC: -10),
        ]
        for conditions in extremes {
            let adj = adjust("outdoor", conditions)
            XCTAssertLessThanOrEqual(abs(adj.dueDate.timeIntervalSince(baseline)), day + 1)
        }
    }

    // MARK: - Conditions distilled from the cached summary

    private func summary(symbol: String = "sun.max", temp: Double = 20, hi: Double = 24,
                         advisory: String? = nil, age: TimeInterval = 0,
                         now: Date = Date(timeIntervalSince1970: 1_750_000_000)) -> (PropertyWeather.Summary, Date) {
        (PropertyWeather.Summary(temp: temp, symbol: symbol, lo: 12, hi: hi,
                                 advisory: advisory, fetchedAt: now.addingTimeInterval(-age)),
         now)
    }

    func testStaleSummaryYieldsNoConditions() {
        // Past the freshness gate the snapshot may not move a schedule.
        let (s, now) = summary(symbol: "cloud.rain", age: PlantWeatherCare.maxSnapshotAge + 60)
        XCTAssertNil(PlantWeatherCare.Conditions(summary: s, now: now))
    }

    func testRainReadFromConditionSymbol() {
        let (s, now) = summary(symbol: "cloud.heavyrain.fill")
        XCTAssertEqual(PlantWeatherCare.Conditions(summary: s, now: now)?.rainLikely, true)
    }

    func testRainReadFromAdvisory() {
        // Clear sky right now, but the fetch flagged a ≥50% chance.
        let (s, now) = summary(symbol: "sun.max", advisory: "rain")
        XCTAssertEqual(PlantWeatherCare.Conditions(summary: s, now: now)?.rainLikely, true)
    }

    func testHighTempIsMaxOfCurrentAndForecastHigh() {
        // A 31° "right now" counts even when the daily high was fetched
        // during a cooler morning — and vice versa.
        let (s, now) = summary(temp: 31, hi: 26)
        XCTAssertEqual(PlantWeatherCare.Conditions(summary: s, now: now)?.highTempC, 31)
    }
}

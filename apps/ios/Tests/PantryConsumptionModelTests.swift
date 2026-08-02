import XCTest
@testable import PRVIO

// Unit tests for PantryConsumptionModel — the pure model that infers a
// consumption pace from the repurchase rhythm on scanned receipts and turns
// it into an effective "what's really on the shelf" quantity. No UI, no
// network, no wall clock: every date is fixed.
final class PantryConsumptionModelTests: XCTestCase {

    // MARK: - Fixtures

    /// Deterministic timeline: `day(n)` is n days after 2026-01-01 00:00 UTC.
    private func day(_ n: Double) -> Date {
        Date(timeIntervalSince1970: 1_767_225_600 + n * 86_400)
    }

    private func event(_ dayIndex: Double, _ quantity: Double)
        -> PantryConsumptionModel.PurchaseEvent {
        .init(date: day(dayIndex), quantity: quantity)
    }

    // MARK: - Pace from regular purchases

    func testPaceFromRegularPurchases() {
        // 2 units bought every 4 days → 0.5/day on both intervals.
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(0, 2), event(4, 2), event(8, 2)])
        XCTAssertEqual(pace ?? 0, 0.5, accuracy: 0.0001)
    }

    func testPaceAveragesUnevenIntervals() {
        // 2/2 days = 1.0 and 2/4 days = 0.5 → average 0.75.
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(0, 2), event(2, 2), event(6, 2)])
        XCTAssertEqual(pace ?? 0, 0.75, accuracy: 0.0001)
    }

    func testPaceIgnoresPurchaseOrder() {
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(8, 2), event(0, 2), event(4, 2)])
        XCTAssertEqual(pace ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - No inference under 2 purchases

    func testNoInferenceWithSinglePurchase() {
        XCTAssertNil(PantryConsumptionModel.dailyPace(for: [event(0, 3)]))
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 3, purchases: [event(0, 3)], asOf: day(30))
        XCTAssertNil(estimate.dailyPace)
        XCTAssertNil(estimate.daysUntilEmpty)
        XCTAssertEqual(estimate.effectiveQuantity, 3)
    }

    func testNoInferenceWithNoPurchases() {
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 5, purchases: [], asOf: day(10))
        XCTAssertNil(estimate.dailyPace)
        XCTAssertNil(estimate.daysUntilEmpty)
        XCTAssertEqual(estimate.effectiveQuantity, 5)
    }

    func testSameDayPurchasesAreOneRestockNotTwo() {
        // Two receipts on one shop day: still a single restock → no pace.
        XCTAssertNil(PantryConsumptionModel.dailyPace(
            for: [event(0, 1), event(0, 2)]))
        // But merged quantities feed the interval: (1+1)/5 days = 0.4.
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(0, 1), event(0, 1), event(5, 1)])
        XCTAssertEqual(pace ?? 0, 0.4, accuracy: 0.0001)
    }

    func testZeroQuantityPurchasesAreDropped() {
        // The empty line contributes nothing; the remaining pair infers.
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(0, 0), event(4, 2), event(8, 2)])
        XCTAssertEqual(pace ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - Clamping

    func testPaceClampsAtUpperBound() {
        // 100 units in one day is a parsing artifact → clamp to the cap.
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(0, 100), event(1, 100)])
        XCTAssertEqual(pace, PantryConsumptionModel.paceBounds.upperBound)
    }

    func testPaceClampsAtLowerBound() {
        // Half a unit over 100 days → 0.005/day, below the floor.
        let pace = PantryConsumptionModel.dailyPace(
            for: [event(0, 0.5), event(100, 0.5)])
        XCTAssertEqual(pace, PantryConsumptionModel.paceBounds.lowerBound)
    }

    // MARK: - Effective quantity

    func testEffectiveQuantityDepletesSinceLastRestock() {
        // Pace 0.5/day, last restock day 8, now day 12 → 4 − 0.5×4 = 2.
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 4,
            purchases: [event(0, 2), event(4, 2), event(8, 2)],
            asOf: day(12))
        XCTAssertEqual(estimate.dailyPace ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(estimate.effectiveQuantity, 2, accuracy: 0.0001)
    }

    func testEffectiveQuantityFloorsAtZero() {
        // 22 days at 0.5/day would eat 11 units — the shelf shows 0, not −7.
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 4,
            purchases: [event(0, 2), event(4, 2), event(8, 2)],
            asOf: day(30))
        XCTAssertEqual(estimate.effectiveQuantity, 0)
        XCTAssertEqual(estimate.daysUntilEmpty, 0)
    }

    func testManualRestockResetsTheClock() {
        // A manual correction after the last purchase outranks the model:
        // nothing has depleted since the household set the number.
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 4,
            purchases: [event(0, 2), event(4, 2), event(8, 2)],
            asOf: day(12),
            restockedAt: day(12))
        XCTAssertEqual(estimate.effectiveQuantity, 4)
    }

    // MARK: - Days until empty

    func testDaysUntilEmptyMath() {
        // Effective 2 at pace 0.5 → exactly 4 days left.
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 4,
            purchases: [event(0, 2), event(4, 2), event(8, 2)],
            asOf: day(12))
        XCTAssertEqual(estimate.daysUntilEmpty, 4)
    }

    func testDaysUntilEmptyRoundsUp() {
        // Pace 1.5/day, stored 4, no elapsed time → 4/1.5 = 2.67 → 3 days:
        // "runs out in ~3 days", never an optimistic round-down.
        let estimate = PantryConsumptionModel.estimate(
            storedQuantity: 4,
            purchases: [event(0, 3), event(2, 3)],
            asOf: day(2))
        XCTAssertEqual(estimate.dailyPace ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(estimate.daysUntilEmpty, 3)
    }

    // MARK: - Receipt-quantity folding (unit lost on the wire)

    func testBaseQuantityFoldsLostGramsOnWeighedRows() {
        XCTAssertEqual(PantryConsumptionModel.baseQuantity(500, pantryUnit: "kg"), 0.5)
        XCTAssertEqual(PantryConsumptionModel.baseQuantity(250, pantryUnit: "l"), 0.25)
        XCTAssertEqual(PantryConsumptionModel.baseQuantity(0.5, pantryUnit: "kg"), 0.5)
        // Counted rows never fold — 500 pieces stays 500 pieces.
        XCTAssertEqual(PantryConsumptionModel.baseQuantity(500, pantryUnit: "buc"), 500)
    }
}

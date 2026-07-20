import XCTest
@testable import PRVIO

// Unit tests for PantryMerge — the pure engine that decides how scanned
// receipt items land in the pantry: grow existing stock, insert new rows,
// skip unit conflicts. No UI or network.
final class PantryMergeTests: XCTestCase {

    // MARK: - Fixtures

    private func pantryItem(name: String, quantity: Double = 1,
                            unit: String = "buc") -> PantryItem {
        PantryItem(id: UUID(), propertyId: UUID(), name: name,
                   normalizedName: name.lowercased(), quantity: quantity,
                   unit: unit, category: "food", minQuantity: nil, emoji: nil,
                   updatedAt: "2026-07-07T00:00:00Z",
                   createdAt: "2026-07-07T00:00:00Z")
    }

    private func addition(_ name: String, _ quantity: Double,
                          _ unit: String = "buc") -> PantryMerge.Addition {
        PantryMerge.Addition(name: name, normalizedName: name,
                             quantity: quantity, unit: unit)
    }

    // MARK: - Unit coarsening

    func testCoarseConvertsGramsAndMillilitres() {
        XCTAssertEqual(PantryMerge.coarse(quantity: 500, unit: "g").value, 0.5)
        XCTAssertEqual(PantryMerge.coarse(quantity: 500, unit: "g").unit, "kg")
        XCTAssertEqual(PantryMerge.coarse(quantity: 250, unit: "ml").value, 0.25)
        XCTAssertEqual(PantryMerge.coarse(quantity: 250, unit: "ml").unit, "l")
        XCTAssertEqual(PantryMerge.coarse(quantity: 3, unit: "buc").unit, "buc")
        XCTAssertEqual(PantryMerge.coarse(quantity: 2, unit: "kg").unit, "kg")
    }

    // MARK: - Growing existing stock

    func testExistingStockGrows() {
        let lapte = pantryItem(name: "Lapte", quantity: 1, unit: "buc")
        let plan = PantryMerge.plan(additions: [addition("Lapte", 2)],
                                    existing: [lapte])
        XCTAssertEqual(plan.increments.count, 1)
        XCTAssertEqual(plan.increments.first?.itemId, lapte.id)
        XCTAssertEqual(plan.increments.first?.add, 2)
        XCTAssertTrue(plan.inserts.isEmpty)
        XCTAssertTrue(plan.skippedNames.isEmpty)
    }

    func testMatchingIsCaseInsensitive() {
        let lapte = pantryItem(name: "LAPTE")
        let plan = PantryMerge.plan(additions: [addition("lapte", 1)],
                                    existing: [lapte])
        XCTAssertEqual(plan.increments.count, 1)
    }

    func testGramsGrowKilogramStock() {
        let faina = pantryItem(name: "Făină", quantity: 1, unit: "kg")
        let plan = PantryMerge.plan(
            additions: [PantryMerge.Addition(name: "Făină", normalizedName: "Făină",
                                             quantity: 500, unit: "g")],
            existing: [faina])
        XCTAssertEqual(plan.increments.first?.add, 0.5)
    }

    // MARK: - New products insert

    func testUnknownProductInserts() {
        let plan = PantryMerge.plan(additions: [addition("Banane", 1.4, "kg")],
                                    existing: [pantryItem(name: "Lapte")])
        XCTAssertTrue(plan.increments.isEmpty)
        XCTAssertEqual(plan.inserts.count, 1)
        XCTAssertEqual(plan.inserts.first?.unit, "kg")
        XCTAssertEqual(plan.inserts.first?.quantity, 1.4)
    }

    // MARK: - Unit conflicts are skipped, never guessed

    func testUnitConflictIsSkipped() {
        let lapte = pantryItem(name: "Lapte", unit: "buc")
        let plan = PantryMerge.plan(additions: [addition("Lapte", 1.5, "l")],
                                    existing: [lapte])
        XCTAssertTrue(plan.increments.isEmpty)
        XCTAssertTrue(plan.inserts.isEmpty)
        XCTAssertEqual(plan.skippedNames, ["Lapte"])
    }

    // MARK: - Duplicates within one receipt merge first

    func testDuplicateReceiptRowsMerge() {
        let lapte = pantryItem(name: "Lapte")
        let plan = PantryMerge.plan(additions: [addition("Lapte", 2), addition("Lapte", 1)],
                                    existing: [lapte])
        XCTAssertEqual(plan.increments.count, 1)
        XCTAssertEqual(plan.increments.first?.add, 3)
    }

    // MARK: - Garbage in, nothing out

    func testZeroAndEmptyAdditionsAreDropped() {
        let plan = PantryMerge.plan(
            additions: [addition("Lapte", 0),
                        PantryMerge.Addition(name: "X", normalizedName: "",
                                             quantity: 2, unit: "buc")],
            existing: [])
        XCTAssertTrue(plan.increments.isEmpty)
        XCTAssertTrue(plan.inserts.isEmpty)
    }
}

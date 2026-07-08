import XCTest
@testable import PRVIO

// Unit tests for the receipt scanner engine: OCR row reconstruction,
// Romanian receipt parsing, product-name normalization/matching, and the
// shopping-list sync planner. Pure logic — no Vision, no UI, no network.
final class ReceiptIntelligenceTests: XCTestCase {

    // MARK: - Helpers

    /// A whole visual row as a single observation at increasing Y.
    private func row(_ text: String, y: CGFloat,
                     x: CGFloat = 0.05, confidence: Float = 0.95) -> OCRLine {
        OCRLine(text: text, x: x, y: y, width: 0.8, height: 0.02, confidence: confidence)
    }

    private func supplyItem(name: String, quantity: String?,
                            completed: Bool = false) -> SupplyItem {
        SupplyItem(id: UUID(), listId: UUID(), propertyId: UUID(),
                   name: name, quantity: quantity, category: "food",
                   priority: "medium", notes: nil, isCompleted: completed,
                   location: nil, createdAt: "", updatedAt: "")
    }

    // MARK: - Parser: full Lidl-style Romanian receipt

    func testParsesLidlStyleReceipt() {
        let lines: [OCRLine] = [
            row("LIDL", y: 0.02),
            row("BON FISCAL", y: 0.04),
            row("CUI: RO12345678", y: 0.06),
            row("LAPTE ZUZU 1.5% 1L    7,49 A", y: 0.10),
            row("BANANE", y: 0.14),
            row("1.404 kg x 5,99", y: 0.16),               // weight line after name
            row("IAURT GREC 10%    7,98 A", y: 0.20),
            row("2 x 3,99", y: 0.22),                       // multiple after item
            row("CIOCOLATA MILKA    5,45 B", y: 0.26),
            row("REDUCERE    -0,85", y: 0.28),              // discount on previous item
            row("TVA A 9%    2,10", y: 0.32),
            row("TOTAL LEI    28,48", y: 0.34),
            row("CARD BANCAR    28,48", y: 0.36),
            row("07.07.2026 14:32", y: 0.40),
        ]

        let receipt = ReceiptIntelligence.parse(rows: lines)

        XCTAssertEqual(receipt.storeName, "Lidl")
        XCTAssertEqual(receipt.dateString, "2026-07-07")
        XCTAssertEqual(receipt.currency, "RON")
        XCTAssertEqual(receipt.items.count, 4, "TVA/TOTAL/CARD/CUI rows must not become items")

        // Simple item: qty 1.
        let lapte = receipt.items[0]
        XCTAssertEqual(lapte.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(lapte.totalPrice, 7.49, accuracy: 0.001)

        // Weight item: name row followed by "1.404 kg x 5,99".
        let banane = receipt.items[1]
        XCTAssertEqual(banane.name.lowercased(), "banane")
        XCTAssertEqual(banane.quantity, 1.404, accuracy: 0.0005)
        XCTAssertEqual(banane.unit, "kg")
        XCTAssertEqual(banane.unitPrice, 5.99, accuracy: 0.001)
        XCTAssertEqual(banane.totalPrice, 8.41, accuracy: 0.01)

        // Multiple: "2 x 3,99" annotates the item above it.
        let iaurt = receipt.items[2]
        XCTAssertEqual(iaurt.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(iaurt.unitPrice, 3.99, accuracy: 0.001)
        XCTAssertEqual(iaurt.totalPrice, 7.98, accuracy: 0.001)

        // Discount subtracted from the previous item.
        let ciocolata = receipt.items[3]
        XCTAssertEqual(ciocolata.totalPrice, 4.60, accuracy: 0.001)

        // Printed TOTAL wins and matches the item sum.
        XCTAssertEqual(receipt.total, 28.48, accuracy: 0.001)
        XCTAssertGreaterThan(receipt.overallConfidence, 0.5,
                             "consistent totals must not be flagged low-confidence")
    }

    // MARK: - Parser: fragmented-row reconstruction

    func testFragmentedRowBecomesOneItem() {
        // Vision returns the name and the price as separate observations
        // on the same visual line — the root cause of the old parser
        // silently dropping items.
        let lines: [OCRLine] = [
            OCRLine(text: "PROFI", x: 0.30, y: 0.05, width: 0.3, height: 0.02, confidence: 0.98),
            OCRLine(text: "LAPTE ZUZU 1.5%", x: 0.05, y: 0.300, width: 0.5, height: 0.02, confidence: 0.95),
            OCRLine(text: "7,49", x: 0.85, y: 0.302, width: 0.1, height: 0.02, confidence: 0.95),
        ]

        let receipt = ReceiptIntelligence.parse(rows: lines)
        XCTAssertEqual(receipt.items.count, 1)
        XCTAssertEqual(receipt.items[0].totalPrice, 7.49, accuracy: 0.001)
        XCTAssertTrue(receipt.items[0].name.lowercased().contains("lapte"))
    }

    func testRowReconstructionKeepsSeparateLinesApart() {
        let fragments: [OCRLine] = [
            OCRLine(text: "PAINE", x: 0.05, y: 0.10, height: 0.02, confidence: 1),
            OCRLine(text: "3,50", x: 0.85, y: 0.105, height: 0.02, confidence: 1),
            OCRLine(text: "OUA M", x: 0.05, y: 0.16, height: 0.02, confidence: 1),
            OCRLine(text: "12,90", x: 0.85, y: 0.162, height: 0.02, confidence: 1),
        ]
        let rows = ReceiptIntelligence.reconstructRows(fragments)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].text, "PAINE  3,50")
        XCTAssertEqual(rows[1].text, "OUA M  12,90")
    }

    // MARK: - Lexicon

    func testLexiconNormalization() {
        XCTAssertEqual(ReceiptProductLexicon.normalize("LAPTE ZUZU 1.5%"), "Lapte")
        XCTAssertEqual(ReceiptProductLexicon.normalize("OUA M"), "Ouă")
        XCTAssertEqual(ReceiptProductLexicon.normalize("IAURT GREC 10%"), "Iaurt grec")
    }

    func testLexiconMatching() {
        let threshold = ReceiptProductLexicon.matchThreshold

        XCTAssertGreaterThanOrEqual(
            ReceiptProductLexicon.match("LAPTE ZUZU 1.5%", against: "Lapte"), threshold)
        XCTAssertGreaterThanOrEqual(
            ReceiptProductLexicon.match("BAN GOLD", against: "Banane"), threshold)
        XCTAssertGreaterThanOrEqual(
            ReceiptProductLexicon.match("OUA M", against: "Ouă"), threshold)
        XCTAssertGreaterThanOrEqual(
            ReceiptProductLexicon.match("IAURT GREC 10%", against: "Iaurt grec"), threshold)
        // Bilingual: the list may be in English.
        XCTAssertGreaterThanOrEqual(
            ReceiptProductLexicon.match("LAPTE ZUZU 1.5%", against: "Milk"), threshold)
        // And unrelated products must NOT match.
        XCTAssertLessThan(
            ReceiptProductLexicon.match("DETERGENT ARIEL", against: "Lapte"), threshold)
    }

    // MARK: - List sync planning

    func testListSyncDecrementsAndCompletes() {
        let lapte = supplyItem(name: "Lapte", quantity: "3")
        let oua = supplyItem(name: "Ouă", quantity: "10")
        let banane = supplyItem(name: "Banane", quantity: "2 kg")
        let listItems = [lapte, oua, banane]

        let receiptItems = [
            ParsedItem(name: "Lapte Zuzu 1.5%", quantity: 2, unit: "buc",
                       unitPrice: 7.49, totalPrice: 14.98),
            ParsedItem(name: "Oua M", quantity: 10, unit: "buc",
                       unitPrice: 1.29, totalPrice: 12.90),
            ParsedItem(name: "Banane", quantity: 1.4, unit: "kg",
                       unitPrice: 5.99, totalPrice: 8.39),
        ]

        let plan = ReceiptListSync.plan(receiptItems: receiptItems, listItems: listItems)
        XCTAssertEqual(plan.actions.count, 3)
        XCTAssertTrue(plan.unmatchedReceiptItems.isEmpty)

        var newQuantities: [UUID: String] = [:]
        var completed: Set<UUID> = []
        for action in plan.actions {
            switch action {
            case .complete(let item):
                completed.insert(item.id)
            case .decrement(let item, let newText, _, _):
                newQuantities[item.id] = newText
            }
        }

        // Lapte ×3, bought 2 → "1" remains.
        XCTAssertEqual(newQuantities[lapte.id], "1")
        // Ouă ×10, bought 10 → fully done.
        XCTAssertTrue(completed.contains(oua.id))
        // Banane 2 kg, bought 1.4 kg → "0.6 kg" remains (parseable, dot decimal).
        XCTAssertEqual(newQuantities[banane.id], "0.6 kg")
    }

    func testListSyncFallsBackToCompleteOnIncompatibleUnits() {
        // "2 kg" on the list but counted pieces on the receipt: never
        // guess a subtraction across dimensions — just check it off.
        let faina = supplyItem(name: "Făină", quantity: "2 kg")
        let receiptItems = [
            ParsedItem(name: "Faina alba", quantity: 1, unit: "buc",
                       unitPrice: 4.50, totalPrice: 4.50),
        ]
        let plan = ReceiptListSync.plan(receiptItems: receiptItems, listItems: [faina])
        XCTAssertEqual(plan.actions.count, 1)
        if case .complete(let item) = plan.actions[0] {
            XCTAssertEqual(item.id, faina.id)
        } else {
            XCTFail("Incompatible units must fall back to .complete")
        }
    }

    func testListSyncIgnoresUnparseableQuantityByCompleting() {
        let paine = supplyItem(name: "Pâine", quantity: "câteva")
        let receiptItems = [
            ParsedItem(name: "Paine alba", quantity: 1, unit: "buc",
                       unitPrice: 3.50, totalPrice: 3.50),
        ]
        let plan = ReceiptListSync.plan(receiptItems: receiptItems, listItems: [paine])
        XCTAssertEqual(plan.actions.count, 1)
        if case .complete = plan.actions[0] {} else {
            XCTFail("Unparseable list quantity must fall back to .complete")
        }
    }

    func testListSyncMatchesEachItemAtMostOnce() {
        let lapte = supplyItem(name: "Lapte", quantity: "1")
        let receiptItems = [
            ParsedItem(name: "Lapte Zuzu", quantity: 1, unit: "buc",
                       unitPrice: 7.49, totalPrice: 7.49),
            ParsedItem(name: "Lapte Fulga", quantity: 1, unit: "buc",
                       unitPrice: 6.99, totalPrice: 6.99),
        ]
        let plan = ReceiptListSync.plan(receiptItems: receiptItems, listItems: [lapte])
        XCTAssertEqual(plan.actions.count, 1, "one list item matches at most one receipt item")
        XCTAssertEqual(plan.unmatchedReceiptItems.count, 1)
    }

    // MARK: - Quantity text parsing

    func testQuantityTextParsing() {
        XCTAssertEqual(ReceiptListSync.parseQuantity("3")?.value, 3)
        XCTAssertNil(ReceiptListSync.parseQuantity("3")?.unit)
        XCTAssertEqual(ReceiptListSync.parseQuantity("x3")?.value, 3)
        XCTAssertEqual(ReceiptListSync.parseQuantity("×3")?.value, 3)
        XCTAssertEqual(ReceiptListSync.parseQuantity("3 buc")?.unit, "buc")
        XCTAssertEqual(ReceiptListSync.parseQuantity("2kg")?.unit, "kg")
        XCTAssertEqual(ReceiptListSync.parseQuantity("2 kg")?.value, 2)
        XCTAssertEqual(ReceiptListSync.parseQuantity("1.5 l")?.value ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(ReceiptListSync.parseQuantity("1,5 l")?.value ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(ReceiptListSync.parseQuantity("10")?.value, 10)
        XCTAssertNil(ReceiptListSync.parseQuantity(nil))
        XCTAssertNil(ReceiptListSync.parseQuantity("câteva"))
    }

    func testQuantityFormatting() {
        XCTAssertEqual(ReceiptListSync.formatQuantity(1, unit: nil), "1")
        XCTAssertEqual(ReceiptListSync.formatQuantity(0.6, unit: "kg"), "0.6 kg")
        XCTAssertEqual(ReceiptListSync.formatQuantity(2.0, unit: "buc"), "2")
        XCTAssertEqual(ReceiptListSync.formatQuantity(1.5, unit: "l"), "1.5 l")
    }

    // MARK: - Parser: the real Ninove (Colruyt-style, Dutch) receipt
    //
    // Regression for IMG_8085-8087: "Te betalen 50,92" and "Betaalkaart
    // 50,92" parsed as PRODUCTS, tripling the total to 152,76 and inflating
    // the item count; the inline "2,99 x 2" quantity (OCR'd as "Ł") stayed
    // glued to the product name.
    func testParsesBelgianNinoveReceipt() {
        let lines: [OCRLine] = [
            row("Ninove", y: 0.02),
            row("Omschrijving    €", y: 0.04),
            row("ZOETE PUNTPAPRIKA    2,85 B", y: 0.06),
            row("LICHT MEERGR. BROOD    1,95 B", y: 0.08),
            row("SNACKTOMATEN XXL    5,99 B", y: 0.10),
            row("FRIETAARDAPPELEN    8,99 B", y: 0.12),
            row("AVOCADO RTE    2,99 B", y: 0.14),
            row("GROTE UIEN    3,79 B", y: 0.16),
            row("FAIRTRADEROZEN  2,99 x  2    5,98 B", y: 0.18),   // inline qty
            row("MINI MOZZARELLA    0,97 B", y: 0.20),
            row("VOLKORENBROOD    2,19 B", y: 0.22),
            row("MINI MOZZARELLA    0,97 B", y: 0.24),
            row("BLAUWE BESSEN 500GR    6,29 B", y: 0.26),
            row("SCHARRELEIEREN    2,59 B", y: 0.28),
            row("MELK VOL LACTOSEVRIJ    1,39 B", y: 0.30),
            row("BIO BANAAN FT    2,03 B", y: 0.32),
            row("0,862 kg x 2,35  €/kg", y: 0.34),                 // weight after item
            row("GRIEKSE YOGHURT 10%    1,95 B", y: 0.36),
            row("Aantal    16 art.", y: 0.40),
            row("Te betalen    50,92", y: 0.42),
            row("Betaalkaart    50,92", y: 0.44),
            row("1171  081863/01  03.07.26  13:10", y: 0.46),
            row("BE 0451.881.923 RPR/RPM Gent", y: 0.48),
            row("Kopie Kaarthouder", y: 0.52),
            row("Terminal  87101546  Merchant  600230900", y: 0.54),
        ]
        let parsed = ReceiptIntelligence.parse(rows: lines)

        // "Te betalen" IS the total; footer rows are not products.
        XCTAssertEqual(parsed.total, 50.92, accuracy: 0.001)
        XCTAssertEqual(parsed.items.count, 15)
        XCTAssertFalse(parsed.items.contains { $0.name.lowercased().contains("betalen") })
        XCTAssertFalse(parsed.items.contains { $0.name.lowercased().contains("betaalkaart") })
        XCTAssertFalse(parsed.items.contains { $0.name.lowercased().contains("aantal") })

        // Items sum matches the printed total exactly → high confidence.
        let sum = parsed.items.reduce(0) { $0 + $1.totalPrice }
        XCTAssertEqual(sum, 50.92, accuracy: 0.001)
        XCTAssertGreaterThan(parsed.overallConfidence, 0.5)

        // The inline "2,99 x 2" row: clean name, qty 2, unit price 2,99.
        let roses = parsed.items.first { $0.name.lowercased().contains("fairtraderozen") }
        XCTAssertEqual(roses?.quantity ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(roses?.unitPrice ?? 0, 2.99, accuracy: 0.001)
        XCTAssertFalse(roses?.name.contains("2,99") ?? true)

        // The weight row annotates the banana above it.
        let banana = parsed.items.first { $0.name.lowercased().contains("banaan") }
        XCTAssertEqual(banana?.quantity ?? 0, 0.862, accuracy: 0.001)
        XCTAssertEqual(banana?.unit, "kg")

        XCTAssertEqual(parsed.dateString, "2026-07-03")
        XCTAssertEqual(parsed.currency, "EUR")
        XCTAssertEqual(parsed.category, "food")
    }

    // The OCR often reads the multiplication sign as "Ł" on thin receipt
    // fonts — both quantity shapes must survive it.
    func testInlineQuantityTolleratesOCRMisreadX() {
        let lines: [OCRLine] = [
            row("Winkel", y: 0.02),
            row("FAIRTRADEROZEN  2,99 Ł  2    5,98 B", y: 0.10),
            row("KAAS JONG    4,50 B", y: 0.12),
            row("2 Ł 2,25", y: 0.14),
            row("Totaal    10,48", y: 0.20),
        ]
        let parsed = ReceiptIntelligence.parse(rows: lines)
        XCTAssertEqual(parsed.items.count, 2)
        XCTAssertEqual(parsed.items.first?.quantity ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(parsed.items.last?.quantity ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(parsed.total, 10.48, accuracy: 0.001)
    }

    // Per-item categories: the detergent on a grocery receipt files under
    // cleaning; a basket that is mostly cleaning flips the receipt category.
    func testPerItemCategories() {
        XCTAssertEqual(ReceiptProductLexicon.category(for: "LAPTE ZUZU 1.5%"), "food")
        XCTAssertEqual(ReceiptProductLexicon.category(for: "DETERGENT ARIEL 2L"), "cleaning")
        XCTAssertEqual(ReceiptProductLexicon.category(for: "Wasmiddel Persil"), "cleaning")
        XCTAssertEqual(ReceiptProductLexicon.category(for: "TOILETPAPIER 12 ROL"), "bathroom")
        XCTAssertEqual(ReceiptProductLexicon.category(for: "Potgrond 20L"), "garden")

        let lines: [OCRLine] = [
            row("Magazin", y: 0.02),
            row("DETERGENT ARIEL    25,99 A", y: 0.10),
            row("WASMIDDEL PERSIL    19,99 A", y: 0.12),
            row("LAPTE    7,49 A", y: 0.14),
            row("TOTAL    53,47", y: 0.20),
        ]
        let parsed = ReceiptIntelligence.parse(rows: lines)
        XCTAssertEqual(parsed.category, "cleaning")
        XCTAssertEqual(parsed.items.filter { $0.category == "cleaning" }.count, 2)
    }
}

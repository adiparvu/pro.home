import Foundation
import CoreGraphics
import UIKit
import Vision

// MARK: - OCRLine
//
// One Vision text observation with its normalized position. `y` is
// top-origin (0 = top of the receipt) and grows downward; multi-page scans
// offset each page by +1.0 so pages read sequentially.
struct OCRLine: Equatable {
    var text: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var confidence: Float

    init(text: String, x: CGFloat, y: CGFloat,
         width: CGFloat = 0.4, height: CGFloat = 0.02, confidence: Float = 1) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

// MARK: - Parsed models

/// A discount the receipt itself printed against one item (or one group of
/// identical items): "NUTRI-BOOST 10% -0,32", "AVANTAGES -5,98". Kept
/// structured and SEPARATE from the item's own price — the printed price is
/// never silently rewritten.
struct ParsedDiscount: Equatable {
    /// The label as printed ("Nutri-Boost", "Avantages"); may be empty when
    /// the row carried only numbers.
    var label: String
    /// Percent when the row printed one ("10% -0,32" → 10); nil otherwise
    /// (merged discounts with different percents also become nil).
    var percent: Double?
    /// Money taken off, always positive.
    var amount: Double
}

/// Why an item is flagged for review — structured so the UI can explain the
/// badge in plain language instead of showing a mute (!) icon.
enum ParsedItemFlag: String, Equatable, CaseIterable {
    case uncertainPrice     // price misread or qty × unit ≠ total
    case uncertainName      // name too short / mostly noise
    case discountAttached   // a discount row was attributed to this item
    case weightPriced       // sold by weight (kg/g), price is per kg
}

/// A named receipt-level reduction printed in the footer between the
/// subtotal and the paid total ("REDUCTION NUTRI-BOOST -2,11", "PROMO -11,96").
struct ReceiptReduction: Equatable {
    var label: String
    var amount: Double      // positive
}

/// items − discounts vs. the printed paid total, stated openly.
struct ReceiptReconciliation: Equatable {
    var itemsGross: Double      // Σ printed line totals (before discounts)
    var itemDiscounts: Double   // Σ discounts attached to items
    var itemsNet: Double        // Σ final line prices
    var paidTotal: Double       // the receipt's printed paid total
    var delta: Double           // itemsNet − paidTotal
    var isMatched: Bool         // the math closes (within a rounding cent)
}

struct ParsedReceipt {
    var storeName: String = ""
    var dateString: String = AppDate.dayString(from: Date())
    /// The PAID total (the last printed total). When the receipt prints a
    /// pre-reduction total first, that lands in `subtotal`.
    var total: Double = 0
    var currency: String = "RON"
    var category: String = "other"
    var items: [ParsedItem] = []
    var notes: String? = nil
    /// VAT total read off the receipt's fiscal rows (nil when absent) —
    /// captured instead of discarded, never invented.
    var vatAmount: Double? = nil
    /// Pre-reduction total when the receipt printed two totals
    /// ("TOTAAL 74,37 … TOTAAL 60,30" → 74,37); nil otherwise.
    var subtotal: Double? = nil
    /// Named footer reductions between subtotal and paid total.
    var reductions: [ReceiptReduction] = []
    /// Cash handed over / change returned, when printed. Read, not invented.
    var cashGiven: Double? = nil
    var changeGiven: Double? = nil
    var overallConfidence: Double = 0

    var dateValue: Date { AppDate.day(from: dateString) ?? Date() }

    /// Compares what the items say with what the receipt says was paid.
    var reconciliation: ReceiptReconciliation {
        let gross = ReceiptIntelligence.roundMoney(items.reduce(0) { $0 + $1.totalPrice })
        let discounts = ReceiptIntelligence.roundMoney(items.reduce(0) { $0 + ($1.discount?.amount ?? 0) })
        let net = ReceiptIntelligence.roundMoney(items.reduce(0) { $0 + $1.finalPrice })
        let delta = ReceiptIntelligence.roundMoney(net - total)
        return ReceiptReconciliation(itemsGross: gross,
                                     itemDiscounts: discounts,
                                     itemsNet: net,
                                     paidTotal: total,
                                     delta: delta,
                                     isMatched: total > 0 && abs(delta) <= 0.015)
    }
}

struct ParsedItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var normalizedName: String
    var quantity: Double
    var unit: String            // "buc" / "kg" / "g" / "l"
    var unitPrice: Double
    /// The line total AS PRINTED, before any attached discount. Display and
    /// persistence use `finalPrice`; this stays the receipt's own number.
    var totalPrice: Double
    var confidence: Double
    var uncertain: Bool
    /// ReceiptCategory id per product — detergents file under cleaning even
    /// on a grocery receipt, so budgets see where the money actually went.
    var category: String
    /// Package size lifted out of the name ("275G DLL CHIA BIO" → "275 g").
    var sizeText: String? = nil
    /// Discount the receipt attributed to this item/group, kept separate.
    var discount: ParsedDiscount? = nil
    /// Structured reasons behind the review badge (order = display order).
    var flags: [ParsedItemFlag] = []

    /// What this line actually cost after its attached discount. Never
    /// negative — a promo can cover the line, not overdraw it.
    var finalPrice: Double {
        ReceiptIntelligence.roundMoney(max(0, totalPrice - (discount?.amount ?? 0)))
    }

    init(id: UUID = UUID(), name: String, normalizedName: String? = nil,
         quantity: Double = 1, unit: String = "buc",
         unitPrice: Double = 0, totalPrice: Double = 0,
         confidence: Double = 1, uncertain: Bool = false,
         category: String? = nil, sizeText: String? = nil,
         discount: ParsedDiscount? = nil, flags: [ParsedItemFlag] = []) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? ReceiptProductLexicon.normalize(name)
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice
        self.confidence = confidence
        self.uncertain = uncertain
        self.category = category ?? ReceiptProductLexicon.category(for: name)
        self.sizeText = sizeText
        self.discount = discount
        self.flags = flags
    }
}

// MARK: - Legacy shim
//
// AddReceiptSheet still calls `ReceiptParser.isoDate(_:)`; keep that one
// entry point stable while the parser itself lives in ReceiptIntelligence.
enum ReceiptParser {
    static func isoDate(_ date: Date) -> String { AppDate.dayString(from: date) }
}

// MARK: - ReceiptIntelligence
//
// The scanner's brain: Vision OCR (with positions) → visual row
// reconstruction → rule-based parsing tuned for Romanian and Belgian
// receipts. Parsing is pure and static so every rule is unit-testable
// without a device or an image.
enum ReceiptIntelligence {

    // MARK: - OCR

    /// Runs accurate Vision OCR on one page, off the main actor. Returned
    /// lines carry normalized top-origin positions, offset by `pageIndex`
    /// so multi-page scans concatenate naturally.
    static func recognize(image: UIImage, pageIndex: Int = 0) async -> [OCRLine] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        // `.accurate` recognition is CPU-heavy (often 1s+ per page); a
        // detached task keeps the processing animation perfectly smooth.
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Receipt languages, in priority order. If the OS build doesn't
            // support them, fall back to automatic detection.
            let preferred = ["ro-RO", "en-US", "de-DE", "fr-FR", "nl-NL"]
            if let supported = try? request.supportedRecognitionLanguages() {
                let usable = preferred.filter(supported.contains)
                if !usable.isEmpty { request.recognitionLanguages = usable }
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            let observations = request.results ?? []
            let offset = CGFloat(pageIndex)
            return observations.compactMap { obs -> OCRLine? in
                guard let candidate = obs.topCandidates(1).first,
                      !candidate.string.trimmingCharacters(in: .whitespaces).isEmpty
                else { return nil }
                let box = obs.boundingBox   // normalized, bottom-left origin
                return OCRLine(text: candidate.string,
                               x: box.minX,
                               y: (1 - box.midY) + offset,
                               width: box.width,
                               height: box.height,
                               confidence: candidate.confidence)
            }
        }.value
    }

    // MARK: - Row reconstruction

    /// A visually reconstructed receipt row (name + price columns rejoined).
    struct ReceiptRow {
        var text: String
        var y: CGFloat
        var confidence: Double
    }

    /// Vision frequently returns "LAPTE ZUZU 1.5%" and "7,49" as separate
    /// observations on the same visual line. Group fragments whose vertical
    /// centers overlap (tolerance 60% of line height), order them by X and
    /// rejoin them — this is what lets the parser see whole rows.
    static func reconstructRows(_ fragments: [OCRLine]) -> [ReceiptRow] {
        let sorted = fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.y < $1.y }
        guard !sorted.isEmpty else { return [] }

        var groups: [[OCRLine]] = []
        for fragment in sorted {
            if let last = groups.last {
                let rowY = last.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(last.count)
                let rowHeight = last.map(\.height).max() ?? 0.02
                let tolerance = max(rowHeight, fragment.height) * 0.6
                if abs(fragment.y - rowY) <= tolerance {
                    groups[groups.count - 1].append(fragment)
                    continue
                }
            }
            groups.append([fragment])
        }

        return groups.map { group in
            let ordered = group.sorted { $0.x < $1.x }
            // Two spaces mark the column gap between rejoined fragments.
            let text = ordered.map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "  ")
            let confidence = ordered.reduce(0.0) { $0 + Double($1.confidence) } / Double(ordered.count)
            let y = ordered.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(ordered.count)
            return ReceiptRow(text: text, y: y, confidence: confidence)
        }
    }

    // MARK: - Parsing

    static func parse(rows fragments: [OCRLine]) -> ParsedReceipt {
        var receipt = ParsedReceipt()
        let rows = reconstructRows(fragments)
        guard !rows.isEmpty else { return receipt }
        let texts = rows.map(\.text)

        receipt.storeName = detectStore(in: texts)
        if let date = extractDate(from: texts) { receipt.dateString = date }
        receipt.currency = detectCurrency(in: texts)

        var items: [ParsedItem] = []
        var totalsSeen: [Double] = []
        var vatTotal: Double = 0
        var footerReductions: [ReceiptReduction] = []
        var cashGiven: Double? = nil
        var changeGiven: Double? = nil
        // A product name printed on its own row (its quantity/price follows).
        var pendingName: (name: String, confidence: Double)? = nil
        // A quantity row printed before its product name row.
        var pendingQuantity: QuantityMatch? = nil
        let store = receipt.storeName

        for row in rows {
            let raw = row.text.trimmingCharacters(in: .whitespaces)
            guard raw.count > 1 else { continue }

            // Barcode / article-number rows ("540011958694", "2226") sit
            // BETWEEN a product and its weight line — skip them without
            // touching the pending state, and never let them become items.
            if isBarcodeRow(raw) { continue }

            let folded = ReceiptProductLexicon.fold(raw)
            let tokens = folded.split(separator: " ").map(String.init)

            // VAT rows: capture the amount instead of discarding it.
            // Multiple rates (9%, 19%) each get a row; they sum.
            if folded.contains("tva") || folded.contains("btw")
                || tokens.contains("vat") {
                if let t = trailingAmount(in: raw), t.value > 0, !t.isNegative {
                    vatTotal = roundMoney(vatTotal + t.value)
                }
                pendingName = nil
                continue
            }

            // TOTAL — strongest signal; "TOTAL TVA"/"SUBTOTAL" are not it.
            // Belgian receipts print "Te betalen", French ones "à payer",
            // Romanian ones sometimes "de plată" — all mean THE total.
            // Receipts with footer reductions print TWO totals (Delhaize:
            // "TOTAAL 74,37 … TOTAAL 60,30") — keep them all, in order;
            // the LAST is what was paid, the first is the subtotal.
            let isTotalRow = folded.contains("total") || folded.contains("totaal")
                || folded.contains("te betalen") || folded.contains("a payer")
                || folded.contains("de plata")
            if isTotalRow {
                if !folded.contains("subtotal") && !folded.contains("sub-total")
                    && !folded.contains("tva") && !folded.contains("btw"),
                   let best = allAmounts(in: raw).max(), best > 0 {
                    totalsSeen.append(best)
                }
                pendingName = nil
                continue
            }

            // Change / cash rows — read the payment story before the skip
            // list swallows it ("CASH 60,50", "TERUG CASH 0,20", "REST 0,20").
            if let amount = allAmounts(in: raw).last, amount > 0, !totalsSeen.isEmpty {
                if tokens.contains(where: { ["terug", "wisselgeld", "rest", "change"].contains($0) }) {
                    changeGiven = amount
                    pendingName = nil
                    continue
                }
                if tokens.contains(where: { ["cash", "numerar", "contant", "especes"].contains($0) }) {
                    cashGiven = amount
                    pendingName = nil
                    continue
                }
            }

            // Fiscal / payment / metadata rows — never products.
            if shouldSkip(tokens: tokens, folded: folded) {
                pendingName = nil
                continue
            }

            let trailing = trailingAmount(in: raw)

            // Discount rows. Before the totals: attributed to the item just
            // above as a STRUCTURED discount ("NUTRI-BOOST 10% -0,32",
            // "AVANTAGES -5,98") — the item's own printed price stays
            // untouched. After the first total: a named receipt-level
            // reduction ("REDUCTION NUTRI-BOOST -2,11", "PROMO -11,96").
            let isDiscountWord = discountWords.contains { folded.contains($0) }
            if isDiscountWord || (trailing?.isNegative ?? false) {
                if let line = discountLine(in: raw) {
                    if !totalsSeen.isEmpty {
                        footerReductions.append(ReceiptReduction(label: line.label,
                                                                 amount: line.amount))
                    } else if !items.isEmpty {
                        let idx = items.count - 1
                        items[idx].discount = mergeDiscounts(
                            items[idx].discount,
                            ParsedDiscount(label: line.label, percent: line.percent,
                                           amount: line.amount))
                        if !items[idx].flags.contains(.discountAttached) {
                            items[idx].flags.append(.discountAttached)
                        }
                    }
                }
                pendingName = nil
                continue
            }

            // Quantity rows: "2 x 3,99", "1.404 kg x 5,99 LEI/kg",
            // "3 BUC x 2,50" — may follow the product name or precede it.
            if let q = quantityMatch(in: raw) {
                let amounts = allAmounts(in: raw)
                let lineTotal: Double
                if amounts.count >= 2, let last = amounts.last, abs(last - q.unitPrice) > 0.005 {
                    lineTotal = last
                } else {
                    lineTotal = roundMoney(q.qty * q.unitPrice)
                }

                if let pending = pendingName {
                    items.append(makeItem(name: pending.name,
                                          quantity: q.qty, unit: q.unit,
                                          unitPrice: q.unitPrice, total: lineTotal,
                                          visionConfidence: min(pending.confidence, row.confidence),
                                          store: store))
                    pendingName = nil
                } else if let last = items.last, last.quantity == 1,
                          abs(q.qty * q.unitPrice - last.totalPrice) <= max(0.05, last.totalPrice * 0.02) {
                    // Annotates the item just above (its math checks out).
                    let idx = items.count - 1
                    items[idx].quantity = q.qty
                    items[idx].unit = q.unit
                    items[idx].unitPrice = q.unitPrice
                    if (q.unit == "kg" || q.unit == "g"),
                       !items[idx].flags.contains(.weightPriced) {
                        items[idx].flags.append(.weightPriced)
                    }
                } else {
                    pendingQuantity = q
                }
                continue
            }

            // Product row: name followed by a price in the right column.
            if let t = trailing, t.value > 0, t.value < 100_000 {
                let name = String(raw[..<t.range.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t-*·."))
                guard isPlausibleName(name) else { pendingName = nil; continue }

                if let inline = inlineQuantity(in: name) {
                    // Belgian single-row style: "FAIRTRADEROZEN 2,99 x 2 5,98".
                    items.append(makeItem(name: inline.name, quantity: inline.qty, unit: "buc",
                                          unitPrice: inline.unitPrice, total: t.value,
                                          visionConfidence: row.confidence,
                                          store: store))
                } else if let pq = pendingQuantity,
                   abs(pq.qty * pq.unitPrice - t.value) <= max(0.05, t.value * 0.02) {
                    items.append(makeItem(name: name, quantity: pq.qty, unit: pq.unit,
                                          unitPrice: pq.unitPrice, total: t.value,
                                          visionConfidence: row.confidence,
                                          store: store))
                } else {
                    items.append(makeItem(name: name, quantity: 1, unit: "buc",
                                          unitPrice: t.value, total: t.value,
                                          visionConfidence: row.confidence,
                                          store: store))
                }
                pendingQuantity = nil
                pendingName = nil
                continue
            }

            // Bare text row → likely a product name whose quantity/price
            // is printed on the next row (Lidl/Kaufland weight style).
            if isPlausibleName(raw) {
                pendingName = (cleanName(raw), row.confidence)
            }
        }

        // Consecutive identical lines ("MYRTILLES 300GR 5,49" × 4) collapse
        // into one ×N row; their promo discounts merge onto the group.
        items = groupIdenticalItems(items)

        // The household's own store-scoped renames outrank every static rule.
        if !store.isEmpty {
            for index in items.indices {
                if let learned = ReceiptLexiconMemory.correction(for: items[index].name,
                                                                 storeName: store) {
                    items[index].normalizedName = learned
                }
            }
        }

        receipt.items = items
        let itemsSum = roundMoney(items.reduce(0) { $0 + $1.finalPrice })
        let declaredTotal = totalsSeen.last ?? 0
        receipt.total = declaredTotal > 0 ? declaredTotal : itemsSum
        if totalsSeen.count >= 2, let first = totalsSeen.first,
           first > receipt.total + 0.005 {
            receipt.subtotal = first
        }
        receipt.reductions = footerReductions
        receipt.cashGiven = cashGiven
        receipt.changeGiven = changeGiven
        // A VAT figure larger than the total is a misread, not a fact.
        if vatTotal > 0, vatTotal < receipt.total { receipt.vatAmount = vatTotal }
        receipt.category = guessCategory(storeName: receipt.storeName, items: items)
        // The items know better than the storefront: a basket that is mostly
        // cleaning products IS a cleaning run, whatever the store's sign says.
        if receipt.category == "food" || receipt.category == "other", !items.isEmpty {
            var counts: [String: Int] = [:]
            for item in items { counts[item.category, default: 0] += 1 }
            if let (winner, hits) = counts.max(by: { $0.value < $1.value }),
               winner != "food", hits * 2 > items.count {
                receipt.category = winner
            } else if receipt.category == "other", (counts["food"] ?? 0) * 2 > items.count {
                receipt.category = "food"
            }
        }

        var overall = items.isEmpty ? 0 : items.reduce(0) { $0 + $1.confidence } / Double(items.count)
        // Sanity: if the printed total and the item sum disagree badly,
        // something was misread — surface that honestly.
        if declaredTotal > 0, abs(itemsSum - declaredTotal) / declaredTotal > 0.25 {
            overall = min(overall, 0.4)
        }
        receipt.overallConfidence = overall
        return receipt
    }

    // MARK: - Row classifiers

    /// Word tokens that mark fiscal/payment/metadata rows.
    private static let skipTokens: Set<String> = [
        "tva", "vat", "btw", "subtotal", "card", "numerar", "cash", "rest",
        "cui", "cif", "srl", "s.c", "sc", "tel", "telefon", "fax", "www",
        "http", "https", "email", "casier", "casa", "operator", "client",
        "puncte", "loteria", "loterie", "fiscal", "fiscala", "bon", "tichet",
        "terminal", "contactless", "banca", "bancar", "plata", "betaling",
        "kassa", "bank", "mastercard", "visa", "maestro", "cec", "voucher",
        "str", "strada", "bd", "bld", "calea", "sos", "soseaua", "jud",
        "judetul", "sector", "nr", "cod", "cip", "aid", "rrn", "auth",
        "multumim", "bedankt", "merci", "ticket", "factura", "garantie",
        "sgr",
        // Belgian/Dutch payment & footer rows (the Ninove receipt taught us:
        // "Betaalkaart 50,92" parsed as a 50,92 product and doubled the total).
        "betalen", "betaalkaart", "bancontact", "payconiq", "aantal",
        "omschrijving", "kaarthouder", "kopie", "merchant", "wisselgeld",
        "eft", "girocard",
        // Loyalty-points footer blocks (Delhaize SuperPlus: 1753 → +30 → 1783).
        "punten", "saldo", "spaarpunten", "superplus", "points",
    ]

    private static let skipPhrases: [String] = [
        "bon fiscal", "card client", "cod fiscal", "total tva", "va asteptam",
        "deschis zilnic", "program", "kassabon", "btw nr",
    ]

    private static func shouldSkip(tokens: [String], folded: String) -> Bool {
        if tokens.contains(where: { skipTokens.contains($0) }) { return true }
        return skipPhrases.contains { folded.contains($0) }
    }

    /// True when a string plausibly names a product (enough letters,
    /// not dominated by digits).
    private static func isPlausibleName(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        return letters >= 3 && letters > digits
    }

    private static func cleanName(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t-*·."))
            .replacingOccurrences(of: "  ", with: " ")
            .localizedCapitalized
    }

    // MARK: - Amounts

    // A money amount has exactly two decimals; the lookahead (plus the
    // preceding-character check in `allAmounts`) stops "1.404" (a weight)
    // from half-matching as "1.40".
    private static let amountRegex = #/\d{1,6}[.,]\d{2}(?!\d)/#
    // Trailing amount at line end, tolerating VAT class letters ("7,49 A"),
    // currency suffixes ("28,45 LEI") and negative markers ("0,85-").
    private static let trailingAmountRegex =
        #/(-?)(\d{1,6}[.,]\d{2})\s*(-?)\s*(?:lei|ron|eur|€|[A-Za-z]{1,2})?\s*$/#.ignoresCase()
    // Quantity lines: qty [unit] x unitPrice. OCR reads the "x" as "Ł"
    // often enough (thin receipt fonts) that it belongs in the class.
    private static let quantityRegex =
        #/^\s*(\d{1,4}(?:[.,]\d{1,3})?)\s*(buc|bucati|kg|gr|g|l|ml|st|stuks|pcs)?\.?\s*[x×*Łł]\s*(\d{1,6}(?:[.,]\d{1,2})?)/#.ignoresCase()

    // Inline quantity at the END of a product row's name part, Belgian style:
    // "FAIRTRADEROZEN  2,99 x  2  5,98" → name + unitPrice×qty + line total.
    // Two shapes: price-first (price has the 2 decimals) and qty-first.
    private static let inlinePriceQtyRegex =
        #/^(.+?)\s+(\d{1,6}[.,]\d{2})\s*[x×*Łł]\s*(\d{1,4}(?:[.,]\d{1,3})?)\s*$/#.ignoresCase()
    private static let inlineQtyPriceRegex =
        #/^(.+?)\s+(\d{1,4})\s*[x×*Łł]\s*(\d{1,6}[.,]\d{2})\s*$/#.ignoresCase()

    static func number(from s: some StringProtocol) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    static func roundMoney(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func allAmounts(in text: String) -> [Double] {
        var out: [Double] = []
        for match in text.matches(of: amountRegex) {
            let range = match.range
            if range.lowerBound > text.startIndex {
                let previous = text[text.index(before: range.lowerBound)]
                if previous.isNumber || previous == "." || previous == "," { continue }
            }
            if let value = number(from: text[range]) { out.append(value) }
        }
        return out
    }

    struct TrailingAmount {
        var value: Double
        var isNegative: Bool
        var range: Range<String.Index>
    }

    static func trailingAmount(in text: String) -> TrailingAmount? {
        guard let match = text.firstMatch(of: trailingAmountRegex),
              let value = number(from: match.2) else { return nil }
        let negative = !match.1.isEmpty || !match.3.isEmpty
        return TrailingAmount(value: value, isNegative: negative, range: match.range)
    }

    struct QuantityMatch {
        var qty: Double
        var unit: String
        var unitPrice: Double
    }

    struct InlineQuantity {
        var name: String
        var qty: Double
        var unitPrice: Double
    }

    /// Extracts a trailing "unitPrice × qty" (or "qty × unitPrice") from a
    /// product row's NAME part — the part left of the line total. The side
    /// with two decimals is the price.
    static func inlineQuantity(in nameTail: String) -> InlineQuantity? {
        if let m = nameTail.firstMatch(of: inlinePriceQtyRegex),
           let price = number(from: m.2), let qty = number(from: m.3),
           qty > 0, price > 0, isPlausibleName(String(m.1)) {
            return InlineQuantity(name: String(m.1), qty: qty, unitPrice: price)
        }
        if let m = nameTail.firstMatch(of: inlineQtyPriceRegex),
           let qty = number(from: m.2), let price = number(from: m.3),
           qty > 0, price > 0, isPlausibleName(String(m.1)) {
            return InlineQuantity(name: String(m.1), qty: qty, unitPrice: price)
        }
        return nil
    }

    static func quantityMatch(in text: String) -> QuantityMatch? {
        guard let match = text.firstMatch(of: quantityRegex),
              let qty = number(from: match.1),
              let unitPrice = number(from: match.3),
              qty > 0, unitPrice >= 0 else { return nil }
        let unitToken = match.2?.lowercased() ?? ""
        let unit: String
        switch unitToken {
        case "kg":      unit = "kg"
        case "g", "gr": unit = "g"
        case "l":       unit = "l"
        case "ml":      unit = "ml"
        default:        unit = "buc"
        }
        return QuantityMatch(qty: qty, unit: unit, unitPrice: unitPrice)
    }

    // MARK: - Discount rows

    /// Words that mark a discount/promo row in the languages receipts
    /// actually arrive in (RO, NL, FR, EN). Rows with a negative amount are
    /// discounts regardless; these words also catch rows where the OCR lost
    /// the minus. "Promo" is deliberately absent — it appears in product
    /// names too, so it only counts with a negative amount.
    static let discountWords: [String] = [
        "reducere", "discount", "rabat", "korting", "reduction", "remise",
        "avantage", "avantaj", "voordeel",
    ]

    /// Marker words to strip from a discount label so "REDUCTION
    /// NUTRI-BOOST" reads "Nutri-Boost" (only when something remains).
    private static let discountLabelNoise: Set<String> = [
        "reduction", "reducere", "discount", "korting", "remise", "rabat",
    ]

    struct DiscountLine {
        var label: String
        var percent: Double?
        var amount: Double
    }

    private static let percentRegex = #/(\d{1,3}(?:[.,]\d{1,2})?)\s*%/#

    /// Reads a discount row into (label, percent?, amount). "NUTRI-BOOST
    /// 10% -0,32" → ("Nutri-Boost", 10, 0.32); "AVANTAGES -5,98" →
    /// ("Avantages", nil, 5.98).
    static func discountLine(in text: String) -> DiscountLine? {
        guard let trailing = trailingAmount(in: text), trailing.value > 0
        else { return nil }
        var head = String(text[..<trailing.range.lowerBound])
        var percent: Double? = nil
        if let match = head.firstMatch(of: percentRegex),
           let value = number(from: match.1), value > 0, value <= 100 {
            percent = value
            head.replaceSubrange(match.range, with: " ")
        }
        let labelWords = ReceiptProductLexicon.fold(head)
            .split(separator: " ").map(String.init)
        let meaningful = labelWords.filter { !discountLabelNoise.contains($0) }
        let chosen = meaningful.isEmpty ? labelWords : meaningful
        let label = cleanName(chosen.joined(separator: " "))
        return DiscountLine(label: label, percent: percent,
                            amount: roundMoney(abs(trailing.value)))
    }

    /// Sums two attached discounts; the percent survives only when both
    /// agree (a merged 10% + flat promo has no single honest percent).
    static func mergeDiscounts(_ a: ParsedDiscount?, _ b: ParsedDiscount?) -> ParsedDiscount? {
        guard let a else { return b }
        guard let b else { return a }
        return ParsedDiscount(label: a.label.isEmpty ? b.label : a.label,
                              percent: a.percent == b.percent ? a.percent : nil,
                              amount: roundMoney(a.amount + b.amount))
    }

    // A discount fused into a product row by OCR: "… 10% -0,33" embedded in
    // the name part. Extracted structurally, never left in the name.
    private static let embeddedDiscountRegex =
        #/(\d{1,3}(?:[.,]\d{1,2})?)\s*%\s*-\s*(\d{1,6}[.,]\d{2})/#

    // MARK: - Line grouping

    /// Collapses CONSECUTIVE identical unit-priced lines (same folded name,
    /// same unit price, counted pieces) into one ×N row. Attached promo
    /// discounts merge onto the group; flags and worst confidence carry over.
    static func groupIdenticalItems(_ items: [ParsedItem]) -> [ParsedItem] {
        var out: [ParsedItem] = []
        for item in items {
            if var last = out.last,
               last.unit == "buc", item.unit == "buc",
               last.quantity.rounded() == last.quantity,
               item.quantity.rounded() == item.quantity,
               abs(last.unitPrice - item.unitPrice) < 0.005,
               ReceiptProductLexicon.fold(last.name) == ReceiptProductLexicon.fold(item.name) {
                last.quantity += item.quantity
                last.totalPrice = roundMoney(last.totalPrice + item.totalPrice)
                last.discount = mergeDiscounts(last.discount, item.discount)
                for flag in item.flags where !last.flags.contains(flag) {
                    last.flags.append(flag)
                }
                last.confidence = min(last.confidence, item.confidence)
                last.uncertain = last.uncertain || item.uncertain
                out[out.count - 1] = last
            } else {
                out.append(item)
            }
        }
        return out
    }

    // MARK: - Name cleanup

    /// True for rows that are only a number (barcodes, article codes,
    /// loyalty balances) — never products, never names.
    static func isBarcodeRow(_ text: String) -> Bool {
        let stripped = text.filter { !$0.isWhitespace }
        guard stripped.count >= 4 else { return false }
        return stripped.allSatisfy(\.isNumber)
    }

    /// Removes embedded barcode runs (6+ digits) from a name fragment.
    private static func stripBarcodes(_ name: String) -> String {
        name.replacingOccurrences(of: #"\d{6,}"#, with: " ",
                                  options: .regularExpression)
    }

    // Leading or trailing package size in a name: "275G DLL CHIA BIO",
    // "MYRTILLES 300GR". Moved into `sizeText`, never left as name noise.
    private static let leadingSizeRegex =
        #/^\s*(\d{1,4}(?:[.,]\d{1,2})?)\s*(g|gr|kg|ml|cl|l)\b[\s.]*/#.ignoresCase()
    private static let trailingSizeRegex =
        #/[\s.]+(\d{1,4}(?:[.,]\d{1,2})?)\s*(g|gr|kg|ml|cl|l)\.?\s*$/#.ignoresCase()

    /// Lifts a leading/trailing size out of `name`; returns it as display
    /// text ("275 g") and the name without it — only when a real name is
    /// left over (never strip a size that IS the whole line).
    static func extractSize(from name: String) -> (sizeText: String?, name: String) {
        func normalizedUnit(_ raw: String) -> String {
            let lower = raw.lowercased()
            return lower == "gr" ? "g" : lower
        }
        if let match = name.firstMatch(of: leadingSizeRegex) {
            var rest = name
            rest.removeSubrange(match.range)
            if isPlausibleName(rest) {
                return ("\(match.1) \(normalizedUnit(String(match.2)))", rest)
            }
        }
        if let match = name.firstMatch(of: trailingSizeRegex) {
            var rest = name
            rest.removeSubrange(match.range)
            if isPlausibleName(rest) {
                return ("\(match.1) \(normalizedUnit(String(match.2)))", rest)
            }
        }
        return (nil, name)
    }

    /// The name the row should DISPLAY: the household's own store-scoped
    /// rename first, then a curated retailer-abbreviation expansion
    /// ("DLL" → "Delhaize"), then the shared product lexicon. The fallback
    /// is always the cleaned original text — never an invention.
    static func displayName(for clean: String, store: String) -> String {
        if let learned = ReceiptLexiconMemory.correction(for: clean, storeName: store) {
            return learned
        }
        if let expanded = ReceiptAbbreviations.expand(clean, store: store) {
            return expanded
        }
        return ReceiptProductLexicon.normalize(clean)
    }

    // MARK: - Item factory

    private static func makeItem(name rawName: String, quantity: Double, unit: String,
                                 unitPrice: Double, total: Double,
                                 visionConfidence: Double, store: String) -> ParsedItem {
        var working = stripBarcodes(rawName)
        var discount: ParsedDiscount? = nil
        var flags: [ParsedItemFlag] = []

        // OCR sometimes fuses the discount row into the product row; pull
        // the "10% -0,33" back out as structure and drop the store's promo
        // marker words from the name (only when a discount was found —
        // "Nutri-Boost" can also be a real product).
        if let match = working.firstMatch(of: embeddedDiscountRegex),
           let percent = number(from: match.1), let amount = number(from: match.2),
           percent > 0, percent <= 100, amount > 0 {
            discount = ParsedDiscount(label: "", percent: percent,
                                      amount: roundMoney(amount))
            working.replaceSubrange(match.range, with: " ")
            working = ReceiptAbbreviations.removingPromoMarkers(from: working, store: store)
            flags.append(.discountAttached)
        }

        let (sizeText, sized) = extractSize(from: working)
        let clean = cleanName(sized)

        var quality = 1.0
        if clean.count < 3 {
            quality *= 0.6
            flags.append(.uncertainName)
        }
        if total <= 0 {
            quality *= 0.5
            flags.append(.uncertainPrice)
        }
        let expected = quantity * unitPrice
        if expected > 0, abs(expected - total) > max(0.05, total * 0.02) {
            quality *= 0.7
            if !flags.contains(.uncertainPrice) { flags.append(.uncertainPrice) }
        }
        if unit == "kg" || unit == "g" { flags.append(.weightPriced) }

        let confidence = min(1, max(0, visionConfidence * quality))
        let effectiveUnitPrice = unitPrice > 0 ? unitPrice : total / max(quantity, 0.001)
        return ParsedItem(name: clean,
                          normalizedName: displayName(for: clean, store: store),
                          quantity: quantity,
                          unit: unit,
                          unitPrice: roundMoney(effectiveUnitPrice),
                          totalPrice: roundMoney(total),
                          confidence: confidence,
                          uncertain: confidence < 0.8,
                          sizeText: sizeText,
                          discount: discount,
                          flags: flags)
    }

    // MARK: - Store / date / currency / category

    private static let knownStores: [(match: String, display: String)] = [
        ("lidl", "Lidl"), ("kaufland", "Kaufland"), ("carrefour", "Carrefour"),
        ("profi", "Profi"), ("penny", "Penny"), ("mega image", "Mega Image"),
        ("dedeman", "Dedeman"), ("colruyt", "Colruyt"), ("delhaize", "Delhaize"),
        ("aldi", "Aldi"), ("auchan", "Auchan"), ("cora", "Cora"),
        ("selgros", "Selgros"), ("metro", "Metro"), ("spar", "Spar"),
        ("jumbo", "Jumbo"), ("albert heijn", "Albert Heijn"),
        ("dr max", "Dr. Max"), ("catena", "Catena"), ("helpnet", "HelpNet"),
        ("leroy merlin", "Leroy Merlin"), ("hornbach", "Hornbach"),
        ("brico", "Brico"), ("ikea", "IKEA"), ("action", "Action"),
    ]

    static func detectStore(in texts: [String]) -> String {
        let head = texts.prefix(8).map { ReceiptProductLexicon.fold($0) }
        for (match, display) in knownStores where head.contains(where: { $0.contains(match) }) {
            return display
        }
        // Fallback: the first plausible text row that isn't a date or amount.
        for text in texts.prefix(5) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 2, isPlausibleName(trimmed),
                  extractDate(from: [trimmed]) == nil,
                  trailingAmount(in: trimmed) == nil else { continue }
            let folded = ReceiptProductLexicon.fold(trimmed)
            let tokens = folded.split(separator: " ").map(String.init)
            guard !shouldSkip(tokens: tokens, folded: folded) else { continue }
            return trimmed
        }
        return ""
    }

    static func extractDate(from texts: [String]) -> String? {
        let patterns = [
            #"\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b"#,
            #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b"#,
            #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2})\b"#,
        ]
        for text in texts {
            for pattern in patterns {
                guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
                let parts = String(text[range])
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ".", with: "-")
                    .components(separatedBy: "-")
                    .map { Int($0) ?? 0 }
                guard parts.count == 3 else { continue }
                let candidate: (y: Int, m: Int, d: Int)
                if parts[0] > 1900 {
                    candidate = (parts[0], parts[1], parts[2])
                } else if parts[2] > 1900 {
                    candidate = (parts[2], parts[1], parts[0])
                } else if parts[2] > 0 {
                    let year = parts[2] < 50 ? 2000 + parts[2] : 1900 + parts[2]
                    candidate = (year, parts[1], parts[0])
                } else { continue }
                guard (1...12).contains(candidate.m), (1...31).contains(candidate.d) else { continue }
                return String(format: "%04d-%02d-%02d", candidate.y, candidate.m, candidate.d)
            }
        }
        return nil
    }

    static func detectCurrency(in texts: [String]) -> String {
        for text in texts {
            let folded = ReceiptProductLexicon.fold(text)
            if text.contains("€") || folded.split(separator: " ").contains("eur") {
                return "EUR"
            }
            // Dutch/French fiscal vocabulary only appears on Benelux
            // receipts — those are Euro receipts even when the OCR misses
            // the € sign (Delhaize prints bare "TOTAAL 74,37").
            if folded.contains("totaal") || folded.contains("te betalen")
                || folded.contains("btw") || folded.contains("terug") {
                return "EUR"
            }
        }
        return "RON"
    }

    static func guessCategory(storeName: String, items: [ParsedItem]) -> String {
        let lower = storeName.lowercased()
        let groups: [(keywords: [String], category: String)] = [
            (["kaufland", "lidl", "aldi", "mega", "carrefour", "penny", "market",
              "supermarket", "magazin", "shop", "food", "alimentar", "piata",
              "piaţa", "consum", "profi", "colruyt", "delhaize", "auchan",
              "cora", "selgros", "spar", "jumbo", "albert heijn"], "food"),
            (["pharmacy", "farma", "farmacia", "apotek", "apotheke", "dr max",
              "dr. max", "helpnet", "catena"], "health"),
            (["dedeman", "brico", "leroy", "hornbach", "bauhaus", "hardware",
              "bricolaj"], "diy"),
            (["zara", "h&m", "hm ", "fashion", "clothing", "moda", "new yorker"], "clothing"),
            (["restaurant", "pizzeria", "cafe", "cafenea", "mcdonalds", "kfc",
              "burger"], "dining"),
        ]
        for (keywords, category) in groups where keywords.contains(where: { lower.contains($0) }) {
            return category
        }
        // Many recognized grocery products but an unknown store → food.
        let groceryHits = items.filter { $0.normalizedName != $0.name && !$0.normalizedName.isEmpty }.count
        if groceryHits >= 3 { return "food" }
        return "other"
    }
}

// MARK: - Orientation bridge

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

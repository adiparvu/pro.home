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

struct ParsedReceipt {
    var storeName: String = ""
    var dateString: String = AppDate.dayString(from: Date())
    var total: Double = 0
    var currency: String = "RON"
    var category: String = "other"
    var items: [ParsedItem] = []
    var notes: String? = nil
    var overallConfidence: Double = 0

    var dateValue: Date { AppDate.day(from: dateString) ?? Date() }
}

struct ParsedItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var normalizedName: String
    var quantity: Double
    var unit: String            // "buc" / "kg" / "g" / "l"
    var unitPrice: Double
    var totalPrice: Double
    var confidence: Double
    var uncertain: Bool

    init(id: UUID = UUID(), name: String, normalizedName: String? = nil,
         quantity: Double = 1, unit: String = "buc",
         unitPrice: Double = 0, totalPrice: Double = 0,
         confidence: Double = 1, uncertain: Bool = false) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? ReceiptProductLexicon.normalize(name)
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice
        self.confidence = confidence
        self.uncertain = uncertain
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
        var declaredTotal: Double = 0
        // A product name printed on its own row (its quantity/price follows).
        var pendingName: (name: String, confidence: Double)? = nil
        // A quantity row printed before its product name row.
        var pendingQuantity: (qty: Double, unit: String, unitPrice: Double)? = nil

        for row in rows {
            let raw = row.text.trimmingCharacters(in: .whitespaces)
            guard raw.count > 1 else { continue }
            let folded = ReceiptProductLexicon.fold(raw)
            let tokens = folded.split(separator: " ").map(String.init)

            // TOTAL — strongest signal; "TOTAL TVA"/"SUBTOTAL" are not it.
            if folded.contains("total") || folded.contains("totaal") {
                if !folded.contains("subtotal") && !folded.contains("sub-total")
                    && !folded.contains("tva") && !folded.contains("btw") {
                    if let best = allAmounts(in: raw).max(), best > declaredTotal {
                        declaredTotal = best
                    }
                }
                pendingName = nil
                continue
            }

            // Fiscal / payment / metadata rows — never products.
            if shouldSkip(tokens: tokens, folded: folded) {
                pendingName = nil
                continue
            }

            let trailing = trailingAmount(in: raw)

            // Discounts subtract from the item above them.
            let isDiscountWord = ["reducere", "discount", "rabat", "korting"]
                .contains { folded.contains($0) }
            if isDiscountWord || (trailing?.isNegative ?? false) {
                if let t = trailing, !items.isEmpty {
                    let idx = items.count - 1
                    items[idx].totalPrice = max(0, roundMoney(items[idx].totalPrice - abs(t.value)))
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
                                          visionConfidence: min(pending.confidence, row.confidence)))
                    pendingName = nil
                } else if let last = items.last, last.quantity == 1,
                          abs(q.qty * q.unitPrice - last.totalPrice) <= max(0.05, last.totalPrice * 0.02) {
                    // Annotates the item just above (its math checks out).
                    let idx = items.count - 1
                    items[idx].quantity = q.qty
                    items[idx].unit = q.unit
                    items[idx].unitPrice = q.unitPrice
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

                if let pq = pendingQuantity,
                   abs(pq.qty * pq.unitPrice - t.value) <= max(0.05, t.value * 0.02) {
                    items.append(makeItem(name: name, quantity: pq.qty, unit: pq.unit,
                                          unitPrice: pq.unitPrice, total: t.value,
                                          visionConfidence: row.confidence))
                } else {
                    items.append(makeItem(name: name, quantity: 1, unit: "buc",
                                          unitPrice: t.value, total: t.value,
                                          visionConfidence: row.confidence))
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

        receipt.items = items
        let itemsSum = roundMoney(items.reduce(0) { $0 + $1.totalPrice })
        receipt.total = declaredTotal > 0 ? declaredTotal : itemsSum
        receipt.category = guessCategory(storeName: receipt.storeName, items: items)

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
    // Quantity lines: qty [unit] x unitPrice.
    private static let quantityRegex =
        #/^\s*(\d{1,4}(?:[.,]\d{1,3})?)\s*(buc|bucati|kg|gr|g|l|ml|st|stuks|pcs)?\.?\s*[x×*]\s*(\d{1,6}(?:[.,]\d{1,2})?)/#.ignoresCase()

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

    // MARK: - Item factory

    private static func makeItem(name: String, quantity: Double, unit: String,
                                 unitPrice: Double, total: Double,
                                 visionConfidence: Double) -> ParsedItem {
        let clean = cleanName(name)
        var quality = 1.0
        if clean.count < 3 { quality *= 0.6 }
        if total <= 0 { quality *= 0.5 }
        let expected = quantity * unitPrice
        if expected > 0, abs(expected - total) > max(0.05, total * 0.02) { quality *= 0.7 }

        let confidence = min(1, max(0, visionConfidence * quality))
        let effectiveUnitPrice = unitPrice > 0 ? unitPrice : total / max(quantity, 0.001)
        return ParsedItem(name: clean,
                          quantity: quantity,
                          unit: unit,
                          unitPrice: roundMoney(effectiveUnitPrice),
                          totalPrice: roundMoney(total),
                          confidence: confidence,
                          uncertain: confidence < 0.8)
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

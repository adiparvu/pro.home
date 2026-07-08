import Foundation
import UIKit

// MARK: - Document OCR prefill (Document Intelligence D2)
//
// Deterministic extraction over recognized text: it reads dates, the amount,
// identifiers (contract / series / policy / client / fiscal codes) and the
// issuer from a known-company lexicon, then hands back a prefill the form
// applies ONLY where the user hasn't typed. Nothing is saved silently — the
// add sheet shows a review banner listing exactly what was read (honesty law).
// The AI-assisted structured extraction (D3) rides on top of this later; this
// layer stands on its own without any model.

struct DocumentPrefill {
    var issuedAt: Date?
    var expiresAt: Date?
    var value: Double?
    var currency: String?
    var issuerCompany: String?
    var docNumber: String?
    var contractCode: String?
    var series: String?
    var policyNumber: String?
    var clientCode: String?
    var clientNumber: String?
    var fiscalCode: String?
    var email: String?
    var phone: String?
    var website: String?
    var suggestedCategory: String?

    /// Human-readable labels of the fields that got filled — drives the review
    /// banner so the user sees what was read before trusting it.
    var filledLabels: [String] = []

    var isEmpty: Bool { filledLabels.isEmpty }
}

enum DocumentOCR {

    /// Runs Vision text recognition on an image off the main actor.
    static func recognize(_ image: UIImage) async -> [String] {
        await VisionCaptureService.recognizeText(in: image)
    }

    // MARK: Extraction

    static func extract(from lines: [String]) -> DocumentPrefill {
        var p = DocumentPrefill()
        let all = lines.joined(separator: "\n")
        let lower = all.lowercased()

        // ── Issuer (known-company lexicon) + category hint ──────────────────
        if let (name, category) = matchIssuer(in: lower) {
            p.issuerCompany = name
            p.suggestedCategory = category
            p.filledLabels.append(String(localized: "doc_f_company"))
        }

        // ── Dates ───────────────────────────────────────────────────────────
        if let expiry = DocumentScanIntelligence.detectExpiry(in: lines) {
            p.expiresAt = expiry
            p.filledLabels.append(String(localized: "doc_f_expires"))
        }
        if let issued = detectIssued(in: lines) {
            p.issuedAt = issued
            p.filledLabels.append(String(localized: "doc_f_issued"))
        }

        // ── Amount + currency ───────────────────────────────────────────────
        if let (value, currency) = detectAmount(in: lines) {
            p.value = value
            p.currency = currency
            p.filledLabels.append(String(localized: "doc_f_value"))
        }

        // ── Identifiers ─────────────────────────────────────────────────────
        if let v = code(after: ["nr. contract", "nr contract", "contract nr", "număr contract",
                                "numar contract", "contract no", "contract number"], in: lines) {
            p.contractCode = v; p.filledLabels.append(String(localized: "doc_f_contract_code"))
        }
        if let v = code(after: ["polița nr", "polita nr", "poliță nr", "nr. poliță", "nr polita",
                                "policy no", "policy number", "poliță", "polita"], in: lines) {
            p.policyNumber = v; p.filledLabels.append(String(localized: "doc_f_policy"))
        }
        if let v = code(after: ["seria", "serie", "series"], in: lines) {
            p.series = v; p.filledLabels.append(String(localized: "doc_f_series"))
        }
        if let v = code(after: ["cod client", "client code"], in: lines) {
            p.clientCode = v; p.filledLabels.append(String(localized: "doc_f_client_code"))
        }
        if let v = code(after: ["nr. client", "nr client", "cod abonat", "client number", "customer number"], in: lines) {
            p.clientNumber = v; p.filledLabels.append(String(localized: "doc_f_client_number"))
        }
        if let v = code(after: ["cui", "cif", "cod fiscal", "vat number", "vat no"], in: lines) {
            p.fiscalCode = v; p.filledLabels.append(String(localized: "doc_f_fiscal_code"))
        }
        // A bare invoice/document number, only if we didn't already catch a contract code.
        if p.contractCode == nil,
           let v = code(after: ["factura nr", "factură nr", "nr. factura", "nr factură",
                                "invoice no", "invoice number", "document nr", "nr. document"], in: lines) {
            p.docNumber = v; p.filledLabels.append(String(localized: "doc_f_number"))
        }

        // ── Contact ─────────────────────────────────────────────────────────
        if let v = firstMatch(#/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#, in: all) {
            p.email = v; p.filledLabels.append(String(localized: "doc_f_email"))
        }
        if let v = firstMatch(#/(?:www\.|https?:\/\/)[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#, in: all) {
            p.website = v.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            p.filledLabels.append(String(localized: "doc_f_website"))
        }
        if let v = detectPhone(in: all) {
            p.phone = v; p.filledLabels.append(String(localized: "doc_f_phone"))
        }

        return p
    }

    // MARK: - Issuer lexicon
    //
    // Known Romanian/EU providers, so a scanned utility bill or policy arrives
    // with the issuer (and a category hint) already set. Extend freely — this
    // is pure data. Keys are matched lowercased against the whole OCR text.
    private static let issuers: [(needles: [String], name: String, category: String?)] = [
        (["engie"], "ENGIE", "utility"),
        (["e.on", "eon energie", "e-on"], "E.ON", "utility"),
        (["electrica"], "Electrica", "utility"),
        (["enel"], "Enel", "utility"),
        (["hidroelectrica"], "Hidroelectrica", "utility"),
        (["distrigaz"], "Distrigaz", "utility"),
        (["apa nova", "apanova"], "Apa Nova", "utility"),
        (["digi", "rcs & rds", "rcs&rds", "rcs-rds"], "DIGI / RCS&RDS", "utility"),
        (["orange"], "Orange", "utility"),
        (["vodafone"], "Vodafone", "utility"),
        (["telekom"], "Telekom", "utility"),
        (["allianz", "allianz-țiriac", "allianz tiriac"], "Allianz-Țiriac", "insurance"),
        (["groupama"], "Groupama", "insurance"),
        (["omniasig"], "Omniasig", "insurance"),
        (["generali"], "Generali", "insurance"),
        (["asirom"], "Asirom", "insurance"),
        (["euroins"], "Euroins", "insurance"),
        (["city insurance"], "City Insurance", "insurance"),
        (["uniqa"], "UNIQA", "insurance"),
        (["nn asigur", "nn pensii", "nn "], "NN", "insurance"),
        (["ing bank", "ing "], "ING Bank", nil),
        (["banca transilvania", "btrl", "bt "], "Banca Transilvania", nil),
        (["brd"], "BRD", nil),
        (["raiffeisen"], "Raiffeisen Bank", nil),
        (["bcr"], "BCR", nil),
    ]

    private static func matchIssuer(in lower: String) -> (String, String?)? {
        for entry in issuers where entry.needles.contains(where: { lower.contains($0) }) {
            return (entry.name, entry.category)
        }
        return nil
    }

    // MARK: - Field extractors

    /// The earliest PAST date on a line with an issue keyword; falls back to
    /// the earliest past date overall. Expiry (future) is handled separately.
    private static func detectIssued(in lines: [String]) -> Date? {
        let keywords = ["emis", "emitere", "data emiterii", "data facturii", "issued",
                        "issue date", "din data", "încheiat", "incheiat", "data contract"]
        let now = Date()
        var keyworded: [Date] = []
        var allPast: [Date] = []
        for line in lines {
            let lower = line.lowercased()
            let past = DocumentScanIntelligence.extractDates(from: line).filter { $0 <= now }
            allPast.append(contentsOf: past)
            if keywords.contains(where: { lower.contains($0) }) { keyworded.append(contentsOf: past) }
        }
        return keyworded.max() ?? allPast.max()
    }

    /// The amount next to a total keyword, with its currency. Prefers the
    /// strongest "amount due" phrasing; picks the largest number on the line.
    private static func detectAmount(in lines: [String]) -> (Double, String)? {
        let strong = ["total de plată", "total de plata", "de plată", "de plata",
                      "total factură", "total factura", "amount due", "total due"]
        let weak = ["total", "valoare", "sumă", "suma", "amount", "prima", "primă"]

        func scan(_ keywords: [String]) -> (Double, String)? {
            for line in lines {
                let lower = line.lowercased()
                guard keywords.contains(where: { lower.contains($0) }) else { continue }
                if let amount = largestAmount(in: line) {
                    return (amount, currency(in: lower))
                }
            }
            return nil
        }
        return scan(strong) ?? scan(weak)
    }

    private static func currency(in lower: String) -> String {
        if lower.contains("eur") || lower.contains("€") { return "EUR" }
        if lower.contains("usd") || lower.contains("$") { return "USD" }
        if lower.contains("gbp") || lower.contains("£") { return "GBP" }
        return "RON"   // "lei", "ron", or unmarked — the app's default
    }

    /// The largest monetary number on a line, tolerant of RO/EN thousand and
    /// decimal separators (1.234,56 and 1,234.56 both parse).
    private static func largestAmount(in line: String) -> Double? {
        var best: Double?
        for m in line.matches(of: #/\d[\d.,]*\d|\d/#) {
            let token = String(m.output)
            guard let value = parseNumber(token), value >= 1 else { continue }
            if best == nil || value > best! { best = value }
        }
        return best
    }

    private static func parseNumber(_ token: String) -> Double? {
        var s = token
        let hasComma = s.contains(","), hasDot = s.contains(".")
        if hasComma && hasDot {
            // The last separator is the decimal one; the other groups thousands.
            if s.lastIndex(of: ",")! > s.lastIndex(of: ".")! {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            // Comma as decimal (RO) unless it clearly groups thousands (1,234).
            let parts = s.split(separator: ",")
            if parts.count == 2, parts[1].count == 3, parts[0].count <= 3 {
                s = s.replacingOccurrences(of: ",", with: "")  // 1,234 → 1234
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        }
        return Double(s)
    }

    /// The identifier token following any of the keywords on the same line.
    private static func code(after keywords: [String], in lines: [String]) -> String? {
        for line in lines {
            let lower = line.lowercased()
            guard let kw = keywords.first(where: { lower.contains($0) }) else { continue }
            guard let range = lower.range(of: kw) else { continue }
            let tailStart = line.index(line.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
            let tail = String(line[tailStart...])
            // First alphanumeric token of decent length after the keyword,
            // skipping separators like ":" and "nr.".
            if let m = tail.firstMatch(of: #/[A-Za-z0-9][A-Za-z0-9\-\/.]{3,}/#) {
                let token = String(m.output).trimmingCharacters(in: CharacterSet(charactersIn: ".-/"))
                if token.count >= 4, token.rangeOfCharacter(from: .decimalDigits) != nil {
                    return token
                }
            }
        }
        return nil
    }

    private static func detectPhone(in text: String) -> String? {
        for m in text.matches(of: #/(?:\+?4?0|\+\d{1,3})?[\s.\-]?\(?\d{2,4}\)?[\s.\-]?\d{3}[\s.\-]?\d{3,4}/#) {
            let token = String(m.output).trimmingCharacters(in: .whitespaces)
            let digits = token.filter(\.isNumber).count
            if (9...15).contains(digits) { return token }
        }
        return nil
    }

    private static func firstMatch<R>(_ regex: R, in text: String) -> String? where R: RegexComponent, R.RegexOutput == Substring {
        text.firstMatch(of: regex).map { String($0.output) }
    }
}

extension DocumentFieldState {
    /// Fills ONLY the fields the user hasn't touched, so a re-scan never
    /// clobbers a correction. Dates flip their toggle on. Returns the labels
    /// that were actually written, for the review banner.
    @discardableResult
    func applyPrefill(_ p: DocumentPrefill) -> [String] {
        var written: [String] = []
        func setText(_ f: DocField, _ v: String?, _ label: String.LocalizationValue) {
            guard let v, !v.isEmpty, (text[f] ?? "").isEmpty else { return }
            text[f] = v
            written.append(String(localized: label))
        }
        func setDate(_ f: DocField, _ d: Date?, _ label: String.LocalizationValue) {
            guard let d, dateEnabled[f] != true else { return }
            dates[f] = d; dateEnabled[f] = true
            written.append(String(localized: label))
        }
        setText(.issuerCompany, p.issuerCompany, "doc_f_company")
        setText(.contractCode, p.contractCode, "doc_f_contract_code")
        setText(.policyNumber, p.policyNumber, "doc_f_policy")
        setText(.series, p.series, "doc_f_series")
        setText(.clientCode, p.clientCode, "doc_f_client_code")
        setText(.clientNumber, p.clientNumber, "doc_f_client_number")
        setText(.fiscalCode, p.fiscalCode, "doc_f_fiscal_code")
        setText(.docNumber, p.docNumber, "doc_f_number")
        setText(.issuerEmail, p.email, "doc_f_email")
        setText(.issuerPhone, p.phone, "doc_f_phone")
        setText(.issuerWebsite, p.website, "doc_f_website")
        setDate(.issuedAt, p.issuedAt, "doc_f_issued")
        setDate(.expiresAt, p.expiresAt, "doc_f_expires")
        if let v = p.value, (text[.value] ?? "").isEmpty {
            text[.value] = trimmedNumber(v)
            if let c = p.currency { currency = c }
            written.append(String(localized: "doc_f_value"))
        }
        return written
    }

    private func trimmedNumber(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.2f", v)
    }
}

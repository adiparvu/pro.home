import Foundation
import Supabase

// MARK: - Document AI Smart Scan (phase D3, gated)
//
// The OCR text goes to ARIA for STRUCTURED extraction: the `aria-chat` edge
// function (verified reachable — it already sends text to Claude Haiku 4.5 and
// answers) gains an `extract` mode that returns strict JSON (document type,
// issuer, identifiers, dates incl. expiry, holder, amounts) plus a plain-language
// long-contract summary. The result is mapped into the SAME review prefill the
// D2 deterministic extractor feeds, so the add sheet's review UI is the single
// place a user confirms values — nothing here is ever saved silently.
//
// Honesty law: this layer NEVER invents. Every field it returns lands in the
// review UI marked as an AI suggestion for the user to confirm or edit. When
// the model is unreachable, errors, or returns nothing usable, the caller keeps
// the deterministic D2 prefill — this returns `nil` and the UI says so.

/// Strict, model-returned extraction. Codable + Sendable so it can cross actor
/// boundaries; every field is optional because the model is instructed to emit
/// `null` whenever a value isn't actually present in the text.
struct DocumentAIExtraction: Sendable {
    var documentType: String?
    var category: String?
    var issuer: String?
    var holder: String?
    var contractCode: String?
    var series: String?
    var policyNumber: String?
    var clientCode: String?
    var clientNumber: String?
    var docNumber: String?
    var fiscalCode: String?
    var issuedAt: String?      // ISO YYYY-MM-DD
    var expiresAt: String?
    var renewAt: String?
    var value: Double?
    var currency: String?
    var vat: Double?
    var summary: String?
    var confidence: Double?

    /// The app-category this maps to, if the model's guess is one we render.
    private static let knownCategories: Set<String> = [
        "contract", "legal", "warranty", "insurance", "certificate", "manual",
        "invoice", "permit", "tax", "utility", "photo", "other",
    ]

    var mappedCategory: String? {
        guard let category, Self.knownCategories.contains(category.lowercased()) else { return nil }
        return category.lowercased()
    }

    /// True when the model actually read something worth prefilling. A response
    /// with no identifying field and low confidence is treated as "unusable" so
    /// the caller falls back to the deterministic extractor honestly.
    var hasUsableFields: Bool {
        let fields: [String?] = [issuer, holder, contractCode, series, policyNumber,
                                 clientCode, clientNumber, docNumber, fiscalCode,
                                 issuedAt, expiresAt, renewAt, currency]
        let hasField = fields.contains { ($0?.isEmpty == false) } || value != nil
        let confident = (confidence ?? 0) >= 0.35
        return hasField && (confident || summary?.isEmpty == false)
    }

    // MARK: Mapping into the D2 review prefill

    /// Bridges the AI result into the same `DocumentPrefill` the deterministic
    /// extractor produces, so both feed the one review UI. Only carries the
    /// values the form can show; the summary and headline are handled separately.
    func toPrefill() -> DocumentPrefill {
        var p = DocumentPrefill()
        p.issuerCompany = issuer.nilIfBlank
        p.contractCode  = contractCode.nilIfBlank
        p.series        = series.nilIfBlank
        p.policyNumber  = policyNumber.nilIfBlank
        p.clientCode    = clientCode.nilIfBlank
        p.clientNumber  = clientNumber.nilIfBlank
        p.docNumber     = docNumber.nilIfBlank
        p.fiscalCode    = fiscalCode.nilIfBlank
        p.value         = value
        p.currency      = value != nil ? currency.nilIfBlank : nil
        p.vat           = vat
        p.issuedAt      = AppDate.day(from: issuedAt ?? "")
        p.expiresAt     = AppDate.day(from: expiresAt ?? "")
        p.renewAt       = AppDate.day(from: renewAt ?? "")
        p.suggestedCategory = mappedCategory
        return p
    }
}

extension DocumentAIExtraction: Decodable {
    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case category
        case issuer
        case holder
        case contractCode = "contract_code"
        case series
        case policyNumber = "policy_number"
        case clientCode = "client_code"
        case clientNumber = "client_number"
        case docNumber = "doc_number"
        case fiscalCode = "fiscal_code"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case renewAt = "renew_at"
        case value
        case currency
        case vat
        case summary
        case confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String? {
            guard let v = try? c.decodeIfPresent(String.self, forKey: k) else { return nil }
            return v.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        // The model is asked for numbers, but tolerate a stringified number too.
        func dbl(_ k: CodingKeys) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return d }
            guard let s = try? c.decodeIfPresent(String.self, forKey: k) else { return nil }
            let cleaned = s.replacingOccurrences(of: ",", with: ".")
                .filter { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(cleaned)
        }
        documentType = str(.documentType)
        category     = str(.category)
        issuer       = str(.issuer)
        holder       = str(.holder)
        contractCode = str(.contractCode)
        series       = str(.series)
        policyNumber = str(.policyNumber)
        clientCode   = str(.clientCode)
        clientNumber = str(.clientNumber)
        docNumber    = str(.docNumber)
        fiscalCode   = str(.fiscalCode)
        issuedAt     = str(.issuedAt)
        expiresAt    = str(.expiresAt)
        renewAt      = str(.renewAt)
        value        = dbl(.value)
        currency     = str(.currency)?.uppercased()
        vat          = dbl(.vat)
        summary      = str(.summary)
        confidence   = dbl(.confidence)
    }
}

// MARK: - Extractor

enum DocumentAIExtractor {

    /// The outcome of a Smart Scan attempt — the caller distinguishes a real
    /// result from an honest "couldn't read it" so the UI never pretends.
    enum Outcome: Sendable {
        case extracted(DocumentAIExtraction)
        /// Reached the model but got nothing trustworthy — keep deterministic.
        case lowConfidence
        /// Never reached the model / decode failed — keep deterministic.
        case unavailable
    }

    /// OCR text is capped before it crosses the wire: the identifying data lives
    /// up front, and a huge manual shouldn't burn tokens or latency.
    private static let maxOCRChars = 6_000

    /// Sends OCR text to the ARIA `extract` mode and decodes strict JSON. Runs
    /// entirely off the main actor. Returns an `Outcome` — never throws into the
    /// UI, because every failure mode is a graceful fall-back to deterministic.
    static func extract(ocrText: String, categoryHint: String?, language: String) async -> Outcome {
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return .unavailable }
        let clipped = String(trimmed.prefix(maxOCRChars))

        struct ExtractPayload: Encodable {
            let mode = "extract"
            let ocr_text: String
            // Self-contained instruction so a not-yet-updated deploy still
            // answers with JSON we can parse (mode is simply ignored there).
            let message: String
            let language: String
            let category_hint: String?
        }
        let payload = ExtractPayload(
            ocr_text: clipped,
            message: fallbackPrompt(ocr: clipped, language: language, categoryHint: categoryHint),
            language: language,
            category_hint: categoryHint
        )

        do {
            let data: Data = try await supabase.functions
                .invoke("aria-chat", options: .init(body: payload))
            guard let extraction = decode(data) else { return .lowConfidence }
            return extraction.hasUsableFields ? .extracted(extraction) : .lowConfidence
        } catch {
            return .unavailable
        }
    }

    // MARK: Decoding

    /// Tolerant of both shapes: the updated function returns
    /// `{ "extraction": {...}, "summary": ... }`; a plain chat deploy returns
    /// `{ "reply": "<json text>" }`. Either way we locate one JSON object and
    /// decode it; anything else → nil (deterministic fallback).
    private static func decode(_ data: Data) -> DocumentAIExtraction? {
        let decoder = JSONDecoder()

        // 1) Structured envelope from the extract-mode function.
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let obj = root["extraction"] as? [String: Any],
               let objData = try? JSONSerialization.data(withJSONObject: obj),
               var ex = try? decoder.decode(DocumentAIExtraction.self, from: objData) {
                if ex.summary == nil, let s = root["summary"] as? String { ex.summary = s.nilIfBlank }
                return ex
            }
            // 2) Chat-shaped reply / raw text holding a JSON object.
            for key in ["reply", "raw", "content"] {
                if let text = root[key] as? String, let ex = decodeJSONObject(in: text, using: decoder) {
                    return ex
                }
            }
            // 3) A soft error field with no payload — unusable.
            if root["error"] != nil { return nil }
        }

        // 4) The whole body might already be the extraction object.
        if let ex = try? decoder.decode(DocumentAIExtraction.self, from: data), ex.hasUsableFields {
            return ex
        }
        // 5) Last resort: scan the raw body text for an object.
        if let text = String(data: data, encoding: .utf8) {
            return decodeJSONObject(in: text, using: decoder)
        }
        return nil
    }

    /// Finds the first balanced `{ … }` in a string (tolerates ```json fences)
    /// and decodes it.
    private static func decodeJSONObject(in text: String, using decoder: JSONDecoder) -> DocumentAIExtraction? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var end: String.Index?
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { end = i; break }
            }
            i = text.index(after: i)
        }
        guard let end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? decoder.decode(DocumentAIExtraction.self, from: data)
    }

    // MARK: Fallback prompt (for a deploy without extract mode)

    private static func fallbackPrompt(ocr: String, language: String, categoryHint: String?) -> String {
        let hint = categoryHint.map { "The user tentatively categorised it as \"\($0)\". " } ?? ""
        return """
        Extract structured data from this scanned document's OCR text. \(hint)\
        Respond with ONLY one JSON object (no prose, no markdown fences) using these keys, \
        writing document_type and summary in language \(language): \
        document_type, category (one of contract,legal,warranty,insurance,certificate,manual,invoice,permit,tax,utility,photo,other), \
        issuer, holder, contract_code, series, policy_number, client_code, client_number, doc_number, fiscal_code, \
        issued_at (YYYY-MM-DD), expires_at (YYYY-MM-DD), renew_at (YYYY-MM-DD), value (number), currency, vat (number), \
        summary (2-4 sentence plain-language summary of a long contract: duration, obligations, costs, key clauses; null if short), \
        confidence (0-1). Use null for anything not clearly present. Never invent values.

        OCR TEXT:
        \(ocr)
        """
    }
}

private extension Optional where Wrapped == String {
    /// The trimmed value, or nil when empty/whitespace — keeps blank model
    /// fields from landing in the form as empty suggestions.
    var nilIfBlank: String? {
        guard let self else { return nil }
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

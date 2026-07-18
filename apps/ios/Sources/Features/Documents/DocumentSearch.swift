import Foundation

// MARK: - Document search ladder (Document Intelligence D6)
//
// Honest, shippable search over the loaded working set (DocumentService keeps
// up to 500 rows in memory), in the two tiers the spec allows us to ship for
// real today:
//
//   Tier 1 — full-field keyword: matches across the name, description,
//            category, every issuer + identifier field, tags, AND the OCR text
//            captured at add time. No field is silently excluded.
//
//   Tier 2 — synonym-aware RO/EN matching: a curated, diacritic-folded
//            bilingual lexicon (the SOURCE of synonyms is the static table in
//            this file — no model, no network) expands each query word to its
//            Romanian/English equivalents and common household objects, joined
//            by a lightweight shared-prefix stem so "garanția mașinii de
//            spălat" reaches warranty documents and washing-machine records.
//
// Tier 3 — true semantic search via pgvector embeddings — is intentionally NOT
// built here; it is an explicit later step with a named infrastructure cost
// (see the phase report), not something faked at this layer.

enum DocumentSearch {

    /// Whether `doc` satisfies `query` under tiers 1 + 2. Empty query matches.
    static func matches(_ doc: DocumentModel, query: String) -> Bool {
        let q = fold(query)
        guard !q.isEmpty else { return true }
        let hay = fold(haystack(doc))

        // Tier 1: the whole query as a phrase, or every meaningful word present.
        if hay.contains(q) { return true }
        let words = meaningfulWords(q)
        guard !words.isEmpty else { return hay.contains(q) }
        if words.allSatisfy({ hay.contains($0) }) { return true }

        // Tier 2: each query word is satisfied by itself, one of its synonyms,
        // or a shared word-stem — AND across words so precision holds.
        return words.allSatisfy { word in
            if hay.contains(word) { return true }
            for alt in synonyms(for: word) where hay.contains(alt) { return true }
            return stemMatches(word, in: hay)
        }
    }

    // MARK: Haystack

    /// Every user-visible + OCR field concatenated. Category is expanded to its
    /// RO and EN names so "garanție" and "warranty" both hit a warranty doc.
    private static func haystack(_ d: DocumentModel) -> String {
        var parts: [String?] = [
            d.name, d.description, d.category,
            categoryNames(d.category),
            d.subcategory,
            d.issuerCompany, d.issuerContact, d.issuerPhone, d.issuerEmail, d.issuerWebsite,
            d.clientNumber, d.docNumber, d.series, d.contractCode, d.clientCode,
            d.fiscalCode, d.policyNumber, d.barcode,
            d.ocrText,
            d.fileSizeDisplay, d.expiresDisplay
        ]
        parts.append(contentsOf: d.tags.map { Optional($0) })
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// Both localized names for a category key, so keyword search is language
    /// independent regardless of the user's current app language.
    private static func categoryNames(_ category: String) -> String {
        switch category {
        case "warranty":    return "garantie warranty"
        case "contract":    return "contract agreement"
        case "legal":       return "juridic legal"
        case "insurance":   return "asigurare insurance polita policy"
        case "certificate": return "certificat certificate"
        case "manual":      return "manual instructiuni guide"
        case "invoice":     return "factura invoice bill"
        case "permit":      return "autorizatie permit"
        case "tax":         return "taxe impozit tax"
        case "utility":     return "utilitati utility"
        case "photo":       return "fotografie photo"
        default:            return "altele other"
        }
    }

    // MARK: Synonym lexicon (the source: this static table)

    /// Groups of equivalent, diacritic-folded RO/EN terms + common household
    /// objects. Any member appearing in a query pulls in all the others.
    private static let groups: [[String]] = [
        ["garantie", "garantia", "warranty", "guarantee"],
        ["asigurare", "asigurari", "insurance", "polita", "policy", "rca", "casco"],
        ["factura", "facturi", "invoice", "bill"],
        ["contract", "contracte", "agreement"],
        ["chitanta", "chitante", "receipt"],
        ["taxa", "taxe", "impozit", "tax"],
        ["certificat", "certificate"],
        ["manual", "instructiuni", "instructions", "guide"],
        ["permis", "autorizatie", "permit", "license", "licenta"],
        ["utilitati", "utility", "utilities"],
        ["juridic", "legal"],
        // Household objects the warranties / manuals attach to.
        ["masina de spalat", "masina spalat", "spalat", "washing machine", "washer"],
        ["frigider", "fridge", "refrigerator"],
        ["cuptor", "aragaz", "oven", "stove"],
        ["masina de vase", "vase", "dishwasher"],
        ["masina", "auto", "vehicul", "vehicle", "car"],
        ["laptop", "computer", "calculator", "pc"],
        ["telefon", "phone", "smartphone"],
        ["televizor", "tv", "television"],
        ["locuinta", "casa", "apartament", "home", "house", "apartment"],
    ]

    /// The synonyms of a query word: every member of any group that word is a
    /// stem-match for (so genitive/plural forms like "masinii" still resolve).
    private static func synonyms(for word: String) -> [String] {
        var out: [String] = []
        for group in groups where group.contains(where: { sharesStem($0, word) }) {
            out.append(contentsOf: group)
        }
        return out
    }

    // MARK: Stemming helpers

    /// True when the query word matches any whole word in the haystack by a
    /// shared leading stem (≥ 4 chars) — a cheap stand-in for RO morphology
    /// ("masinii" ~ "masina", "garantia" ~ "garantie").
    private static func stemMatches(_ word: String, in hay: String) -> Bool {
        guard word.count >= 4 else { return false }
        for token in hay.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if sharesStem(String(token), word) { return true }
        }
        return false
    }

    private static func sharesStem(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Multiword lexicon members are matched as substrings elsewhere; here we
        // compare single tokens by common leading characters.
        guard !a.contains(" "), !b.contains(" ") else { return a.contains(b) || b.contains(a) }
        let n = a.commonPrefix(with: b).count
        return n >= 4 && n >= min(a.count, b.count) - 2
    }

    // MARK: Normalization

    private static let stopwords: Set<String> = [
        "de", "la", "si", "cu", "din", "pe", "un", "o", "in", "ale", "ai",
        "the", "a", "of", "for", "and", "to", "my", "an"
    ]

    private static func meaningfulWords(_ folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    /// Lowercase + strip diacritics so RO input matches ASCII-stored fields
    /// (and vice-versa): "mașină" → "masina", "garanție" → "garantie".
    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ro_RO"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

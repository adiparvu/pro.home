import Foundation

// MARK: - ReceiptAbbreviations
//
// Curated, data-driven expansion of the cryptic abbreviations retailers
// print on receipts ("275G DLL CHIA BIO" is Delhaize's house-brand chia).
// Two layers: a per-store table (keyed by folded store name substring) and
// a generic table that applies everywhere. Expansion is token-exact and
// HONEST — a token either has a curated expansion or it survives unchanged;
// nothing is guessed. Adding a store is adding a dictionary entry.
enum ReceiptAbbreviations {

    /// Abbreviations every store shares.
    static let generic: [String: String] = [
        "h&s": "Head & Shoulders",
        "vrac": "(vrac)",            // sold loose / bulk
    ]

    /// Folded store-name fragment → that retailer's own shorthand.
    static let byStore: [String: [String: String]] = [
        "delhaize": [
            "dll": "Delhaize",       // house brand prefix
            "tom": "Tomate",         // "TOM CHARNUE VRAC"
        ],
    ]

    /// Promo-program marker words per store — words that name the DISCOUNT
    /// program, not a product, when they ride a discount pattern.
    static let promoMarkersByStore: [String: [String]] = [
        "delhaize": ["nutri-boost", "nutriboost", "avantages", "avantage"],
    ]

    private static func storeTable(for store: String) -> [String: String] {
        let folded = ReceiptProductLexicon.fold(store)
        guard !folded.isEmpty else { return [:] }
        for (fragment, table) in byStore where folded.contains(fragment) {
            return table
        }
        return [:]
    }

    /// Expands known abbreviations token by token, capitalizing the
    /// untouched tokens. Returns nil when nothing was expanded, so callers
    /// can fall back to the shared product lexicon.
    static func expand(_ name: String, store: String) -> String? {
        let storeWords = storeTable(for: store)
        var didExpand = false
        let tokens = name.split(separator: " ").map { piece -> String in
            let token = String(piece)
            let key = token.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if let hit = storeWords[key] ?? generic[key] {
                didExpand = true
                return hit
            }
            return token.localizedCapitalized
        }
        guard didExpand else { return nil }
        return tokens.joined(separator: " ")
    }

    /// Strips a store's promo-program marker words from a name. Called only
    /// after a discount pattern was extracted from the same row — "Nutri-
    /// Boost" alone can also be a real product, so it is never stripped
    /// blindly.
    static func removingPromoMarkers(from name: String, store: String) -> String {
        let folded = ReceiptProductLexicon.fold(store)
        let markers = promoMarkersByStore.first { folded.contains($0.key) }?.value
            ?? []
        guard !markers.isEmpty else { return name }
        let kept = name.split(separator: " ").filter { piece in
            let key = ReceiptProductLexicon.fold(String(piece))
            return !markers.contains(key)
        }
        let result = kept.joined(separator: " ")
        return result.isEmpty ? name : result
    }
}

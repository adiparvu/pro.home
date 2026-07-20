import Foundation

// MARK: - Learned product corrections
//
// The static lexicon knows common products; the household knows ITS
// products. Every time the user renames an OCR'd line in review, the
// correction lands here — folded original → the user's exact name — and
// every future scan of that receipt line resolves instantly to what the
// user called it. On-device, no model, no network: the app simply stops
// making the same mistake twice.

enum ReceiptLexiconMemory {
    private static let key = "prvio.receipt.learned"
    private static let capacity = 500

    private static var store: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    /// In-process cache so hot matching loops never re-read the plist.
    private static var cache: [String: String] = load()

    private static func load() -> [String: String] {
        (store.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    /// Composite key for a store-scoped rename: the same OCR text can mean
    /// different products at different retailers.
    private static func scopedKey(storeName: String, raw: String) -> String {
        "s:" + ReceiptProductLexicon.fold(storeName) + "|" + ReceiptProductLexicon.fold(raw)
    }

    /// The user's name for this raw receipt line, if they've corrected it
    /// before. A store-scoped correction (learned while reviewing that
    /// store's receipt) wins over the store-agnostic one. Keyed on the
    /// folded original, so OCR case/diacritic noise still hits.
    static func correction(for raw: String, storeName: String? = nil) -> String? {
        if let storeName, !storeName.isEmpty,
           let scoped = cache[scopedKey(storeName: storeName, raw: raw)] {
            return scoped
        }
        return cache[ReceiptProductLexicon.fold(raw)]
    }

    /// Remember a rename made in review — globally, and store-scoped when
    /// the receipt's store is known. Ignores no-ops and empty names; oldest
    /// entries fall away past capacity (the map must never grow unboundedly
    /// in the App Group plist).
    static func remember(original raw: String, corrected: String,
                         storeName: String? = nil) {
        let folded = ReceiptProductLexicon.fold(raw)
        let name = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty, !name.isEmpty,
              ReceiptProductLexicon.fold(name) != folded else { return }
        var keys = [folded]
        if let storeName, !storeName.isEmpty {
            keys.append(scopedKey(storeName: storeName, raw: raw))
        }
        for entryKey in keys {
            if cache.count >= capacity, cache[entryKey] == nil,
               let victim = cache.keys.first {
                cache.removeValue(forKey: victim)
            }
            cache[entryKey] = name
        }
        store.set(cache, forKey: key)
    }

    /// Test seam: reset the in-process cache after mutating the suite.
    static func reloadForTesting() { cache = load() }
}

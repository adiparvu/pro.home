import Foundation

/// Persistence for the NFC wallet's registered tags — the exact UserDefaults
/// store (`prvio.nfcTags`) NFCWalletView has always used, lifted into a tiny
/// namespace so the deep-link router can resolve a scanned tag without
/// touching a view.
enum NFCTagStore {
    static let storageKey = "prvio.nfcTags"

    static func load() -> [NFCTag] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([NFCTag].self, from: data) else { return [] }
        return saved
    }

    static func save(_ tags: [NFCTag]) {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Looks up a saved tag by the id written into its NDEF record
    /// (`prvio://nfc/<id>`).
    static func tag(withId id: String) -> NFCTag? {
        load().first { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }
    }
}

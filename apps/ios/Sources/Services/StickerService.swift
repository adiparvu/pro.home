import SwiftUI

@MainActor
final class StickerService: ObservableObject {
    @Published private(set) var recents: [Sticker] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var useCounts: [String: Int] = [:]

    private let recentsKey   = "prvio.stickers.recents"
    private let favoritesKey = "prvio.stickers.favorites"
    private let countsKey    = "prvio.stickers.counts"

    init() { restore() }

    // MARK: - Public API

    func use(_ sticker: Sticker) {
        recents.removeAll { $0.id == sticker.id }
        recents.insert(sticker, at: 0)
        if recents.count > 24 { recents = Array(recents.prefix(24)) }
        useCounts[sticker.id, default: 0] += 1
        persist()
    }

    func toggleFavorite(_ sticker: Sticker) {
        if favorites.contains(sticker.id) {
            favorites.remove(sticker.id)
        } else {
            favorites.insert(sticker.id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    func isFavorite(_ sticker: Sticker) -> Bool { favorites.contains(sticker.id) }

    var favoriteStickers: [Sticker] {
        favorites.compactMap { StickerCatalog.sticker(id: $0) }
            .sorted { useCounts[$0.id, default: 0] > useCounts[$1.id, default: 0] }
    }

    var mostUsed: [Sticker] {
        useCounts
            .sorted { $0.value > $1.value }
            .prefix(16)
            .compactMap { StickerCatalog.sticker(id: $0.key) }
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(recents.map(\.id), forKey: recentsKey)
        UserDefaults.standard.set(useCounts, forKey: countsKey)
    }

    private func restore() {
        if let ids = UserDefaults.standard.stringArray(forKey: recentsKey) {
            recents = ids.compactMap { StickerCatalog.sticker(id: $0) }
        }
        if let ids = UserDefaults.standard.stringArray(forKey: favoritesKey) {
            favorites = Set(ids)
        }
        if let counts = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] {
            useCounts = counts
        }
    }
}

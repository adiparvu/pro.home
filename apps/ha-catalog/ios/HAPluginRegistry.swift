import Foundation

// MARK: - Plugin Registry
//
// Central read-only store for the bundled plugin catalog.
// Loaded once at app start from plugins.json (bundled resource or remote fetch).
// Not responsible for install state — that lives in HAPluginManager.

@MainActor
final class HAPluginRegistry: ObservableObject {

    // MARK: Published

    @Published private(set) var allPlugins: [HAPluginManifest] = []
    @Published private(set) var categories: [HACategoryMeta]  = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    // MARK: Derived (computed from allPlugins)

    func plugins(in category: HAPluginCategory) -> [HAPluginManifest] {
        allPlugins.filter { $0.category == category }
    }

    func plugins(matching query: String) -> [HAPluginManifest] {
        let q = query.lowercased()
        return allPlugins.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.tags.contains(where: { $0.contains(q) })
        }
    }

    func plugin(id: String) -> HAPluginManifest? {
        allPlugins.first(where: { $0.id == id })
    }

    // MARK: Load

    /// Load from bundled JSON (plugins.json must be in app bundle Resources)
    func loadBundled() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = Bundle.main.url(forResource: "plugins", withExtension: "json") else {
            loadError = "Catalog not found in bundle."
            return
        }

        await loadFrom(url: url)
    }

    /// Refresh from remote (replaces bundled catalog when newer version available)
    func loadRemote(from remoteURL: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let catalog = try JSONDecoder().decode(HAPluginCatalog.self, from: data)
            allPlugins = catalog.plugins
            categories = catalog.categories
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Private

    private func loadFrom(url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(HAPluginCatalog.self, from: data)
            allPlugins = catalog.plugins
            categories = catalog.categories
        } catch {
            loadError = error.localizedDescription
        }
    }
}

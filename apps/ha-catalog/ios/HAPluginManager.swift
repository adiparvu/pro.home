import Foundation

// MARK: - Plugin Manager
//
// Manages the INSTALLED state of plugins per HA instance.
// Install/uninstall/enable/disable operations are declared here as protocol
// but not yet implemented — implementation happens in Phase 2.

// MARK: - Manager Protocol

protocol HAPluginManaging {
    var installedPlugins: [HAInstalledPlugin] { get }

    func isInstalled(_ pluginId: String) -> Bool
    func isEnabled(_ pluginId: String) -> Bool

    func install(_ request: HAPluginInstallRequest) async throws
    func uninstall(pluginId: String, from instance: HAInstance) async throws
    func enable(pluginId: String) async throws
    func disable(pluginId: String) async throws
    func refresh() async
}

// MARK: - Install Error

enum HAPluginInstallError: LocalizedError {
    case noHAInstance
    case hacsNotAvailable
    case networkError(String)
    case unsupportedInstallType(HAPluginInstallType)
    case alreadyInstalled

    var errorDescription: String? {
        switch self {
        case .noHAInstance:
            return "No Home Assistant instance configured."
        case .hacsNotAvailable:
            return "HACS is not installed on the target instance."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .unsupportedInstallType(let t):
            return "Install type '\(t.rawValue)' requires manual setup."
        case .alreadyInstalled:
            return "Plugin is already installed."
        }
    }
}

// MARK: - Install Strategy Protocol
//
// Each install type gets its own strategy (future implementation).

protocol HAInstallStrategy {
    var supportedType: HAPluginInstallType { get }
    func install(_ manifest: HAPluginManifest, on instance: HAInstance) async throws
    func uninstall(_ manifest: HAPluginManifest, from instance: HAInstance) async throws
}

// MARK: - Concrete Manager (stub — install logic not implemented yet)

@MainActor
final class HAPluginManager: ObservableObject, HAPluginManaging {

    // MARK: Published

    @Published private(set) var installedPlugins: [HAInstalledPlugin] = []
    @Published private(set) var instances: [HAInstance] = []
    @Published var defaultInstance: HAInstance?

    // MARK: State persistence key

    private let persistenceKey = "ha.installed.plugins"

    // MARK: Init

    init() {
        loadFromDisk()
    }

    // MARK: Query

    func isInstalled(_ pluginId: String) -> Bool {
        installedPlugins.contains(where: { $0.id == pluginId })
    }

    func isEnabled(_ pluginId: String) -> Bool {
        installedPlugins.first(where: { $0.id == pluginId })?.isEnabled ?? false
    }

    func installedPlugin(_ id: String) -> HAInstalledPlugin? {
        installedPlugins.first(where: { $0.id == id })
    }

    // MARK: Mutations (not yet implemented — stubs only)

    func install(_ request: HAPluginInstallRequest) async throws {
        // Phase 2: delegate to strategy for request.manifest.installType
        // For now: record as installed locally (no actual HA API call)
        guard !isInstalled(request.manifest.id) else { throw HAPluginInstallError.alreadyInstalled }
        let entry = HAInstalledPlugin(
            id: request.manifest.id,
            isEnabled: request.autoEnable,
            installedAt: Date(),
            version: nil,
            notes: nil,
            haInstanceId: request.targetInstance.id.uuidString
        )
        installedPlugins.append(entry)
        saveToDisk()
    }

    func uninstall(pluginId: String, from instance: HAInstance) async throws {
        // Phase 2: reverse install via strategy
        installedPlugins.removeAll(where: { $0.id == pluginId })
        saveToDisk()
    }

    func enable(pluginId: String) async throws {
        guard let idx = installedPlugins.firstIndex(where: { $0.id == pluginId }) else { return }
        installedPlugins[idx].isEnabled = true
        saveToDisk()
    }

    func disable(pluginId: String) async throws {
        guard let idx = installedPlugins.firstIndex(where: { $0.id == pluginId }) else { return }
        installedPlugins[idx].isEnabled = false
        saveToDisk()
    }

    func refresh() async {
        // Phase 2: sync installed state from real HA instance via REST API
    }

    // MARK: Persistence

    private func saveToDisk() {
        let data = try? JSONEncoder().encode(installedPlugins)
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let plugins = try? JSONDecoder().decode([HAInstalledPlugin].self, from: data) else { return }
        installedPlugins = plugins
    }
}

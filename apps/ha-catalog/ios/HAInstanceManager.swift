import Foundation

// MARK: - HA Instance Manager
//
// Manages connections to one or more Home Assistant instances.
// Discovery (mDNS/Bonjour), token storage, and health checks are
// declared here but not implemented — that is Phase 2 work.

@MainActor
final class HAInstanceManager: ObservableObject {

    // MARK: Published

    @Published private(set) var instances: [HAInstance] = []
    @Published var defaultInstance: HAInstance?
    @Published private(set) var isDiscovering = false

    // MARK: CRUD

    func add(_ instance: HAInstance) {
        instances.append(instance)
        if instances.count == 1 { defaultInstance = instance }
        saveToDisk()
    }

    func remove(id: UUID) {
        instances.removeAll(where: { $0.id == id })
        if defaultInstance?.id == id { defaultInstance = instances.first }
        saveToDisk()
    }

    func update(_ instance: HAInstance) {
        guard let idx = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[idx] = instance
        saveToDisk()
    }

    func setDefault(_ instance: HAInstance) {
        var updated = instance
        updated.isDefault = true
        update(updated)
        defaultInstance = updated
    }

    // MARK: Discovery (stub — Phase 2)

    /// Discover HA instances on local network via mDNS (_home-assistant._tcp)
    func discoverOnLocalNetwork() async {
        isDiscovering = true
        defer { isDiscovering = false }
        // Phase 2: use Network.framework / Bonjour to find _home-assistant._tcp
    }

    // MARK: Health Check (stub — Phase 2)

    /// Validate access token and retrieve HA version
    func checkHealth(of instance: HAInstance) async -> Bool {
        // Phase 2: GET /api/ with Authorization: Bearer <token>
        return false
    }

    // MARK: WebSocket (stub — Phase 2)

    /// Open persistent WebSocket connection for real-time entity state updates
    func connectWebSocket(to instance: HAInstance) {
        // Phase 2: HA WebSocket API at ws(s)://<host>/api/websocket
    }

    // MARK: Persistence

    private let persistenceKey = "ha.instances"

    private func saveToDisk() {
        let data = try? JSONEncoder().encode(instances)
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let loaded = try? JSONDecoder().decode([HAInstance].self, from: data) else { return }
        instances = loaded
        defaultInstance = loaded.first(where: { $0.isDefault }) ?? loaded.first
    }
}

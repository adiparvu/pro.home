import Foundation

// MARK: - Widget snapshot (shared between main app and widget extension via App Groups)

struct PRVIOWidgetSnapshot: Codable {
    var overdueTaskCount: Int = 0
    var openTaskCount: Int = 0
    var pendingSupplyCount: Int = 0
    var plantsNeedingWater: Int = 0
    var plantNames: [String] = []
    var unreadMessages: Int = 0
    var propertyName: String? = nil
    var propertyHealthScore: Int? = nil
    var criticalTaskTitle: String? = nil
    var nextMaintenanceTitle: String? = nil
    // Optional so snapshots written before this field existed still decode.
    var nextMaintenanceDue: String? = nil
    var activeDeliveryCount: Int = 0
    var updatedAt: Date = Date()
}

// MARK: - Intent catalogs (read by App Intents without Supabase)

struct TaskCatalogEntry: Codable {
    var id: UUID
    var title: String
    var priority: String
    var isCompleted: Bool
    // Optional so catalogs written before this field existed still decode.
    var isOverdue: Bool? = nil
}

struct PlantCatalogEntry: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var needsWatering: Bool
}

struct SupplyCatalogEntry: Codable {
    var id: UUID
    var name: String
    var isCompleted: Bool
}

// MARK: - Store

enum SharedDataStore {
    static let suiteName = "group.com.prvio.app"

    private static let snapshotKey         = "prvio.widget.snapshot"
    private static let taskCatalogKey      = "prvio.catalog.tasks"
    private static let plantCatalogKey     = "prvio.catalog.plants"
    private static let supplyCatalogKey    = "prvio.catalog.supplies"
    private static let pendingWateringsKey = "prvio.pending.waterings"
    private static let pendingCompletionsKey = "prvio.pending.completions"
    private static let pendingSupplyChecksKey = "prvio.pending.supplyChecks"

    // MARK: Widget snapshot

    static func write(_ snapshot: PRVIOWidgetSnapshot) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        ud.set(data, forKey: snapshotKey)
    }

    static func read() -> PRVIOWidgetSnapshot? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(PRVIOWidgetSnapshot.self, from: data)
    }

    // MARK: Task catalog

    static func writeTaskCatalog(_ tasks: [TaskCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(tasks) else { return }
        ud.set(data, forKey: taskCatalogKey)
    }

    static func readTaskCatalog() -> [TaskCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: taskCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([TaskCatalogEntry].self, from: data)) ?? []
    }

    // MARK: Plant catalog

    static func writePlantCatalog(_ plants: [PlantCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(plants) else { return }
        ud.set(data, forKey: plantCatalogKey)
    }

    static func readPlantCatalog() -> [PlantCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: plantCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([PlantCatalogEntry].self, from: data)) ?? []
    }

    // MARK: Pending actions (written by App Intents, processed by main app on foreground)

    static func appendPendingWatering(_ plantId: UUID) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        var pending = (ud.array(forKey: pendingWateringsKey) as? [String]) ?? []
        let str = plantId.uuidString
        if !pending.contains(str) { pending.append(str) }
        ud.set(pending, forKey: pendingWateringsKey)
    }

    static func popPendingWaterings() -> [UUID] {
        guard let ud = UserDefaults(suiteName: suiteName) else { return [] }
        let ids = ((ud.array(forKey: pendingWateringsKey) as? [String]) ?? []).compactMap { UUID(uuidString: $0) }
        ud.removeObject(forKey: pendingWateringsKey)
        return ids
    }

    // MARK: Supply catalog

    static func writeSupplyCatalog(_ items: [SupplyCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: supplyCatalogKey)
    }

    static func readSupplyCatalog() -> [SupplyCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: supplyCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([SupplyCatalogEntry].self, from: data)) ?? []
    }

    static func appendPendingSupplyCheck(_ itemId: UUID) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        var pending = (ud.array(forKey: pendingSupplyChecksKey) as? [String]) ?? []
        let str = itemId.uuidString
        if !pending.contains(str) { pending.append(str) }
        ud.set(pending, forKey: pendingSupplyChecksKey)
    }

    static func popPendingSupplyChecks() -> [UUID] {
        guard let ud = UserDefaults(suiteName: suiteName) else { return [] }
        let ids = ((ud.array(forKey: pendingSupplyChecksKey) as? [String]) ?? []).compactMap { UUID(uuidString: $0) }
        ud.removeObject(forKey: pendingSupplyChecksKey)
        return ids
    }

    // MARK: Intent flags (widget/Shortcuts process → app process)
    //
    // Written from whichever process runs the App Intent. The app-group suite is
    // the only store both processes can see — flags written to .standard from
    // the widget extension were invisible to the app (the old bug: "New Task"
    // opened the app but never the form).

    static func setIntentFlag(_ key: String) {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: key)
    }

    static func consumeIntentFlag(_ key: String) -> Bool {
        var flagged = false
        if let ud = UserDefaults(suiteName: suiteName), ud.bool(forKey: key) {
            ud.removeObject(forKey: key); flagged = true
        }
        // Legacy location (intent ran in the app process before this migration).
        if UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.removeObject(forKey: key); flagged = true
        }
        return flagged
    }

    // MARK: Instant widget feedback (applied by App Intents in the extension)
    //
    // Pending actions are only reconciled with Supabase when the app next
    // foregrounds — without these local mutations a widget button tap would
    // visibly do nothing.

    static func applyLocalTaskCompletion(_ id: UUID) {
        var catalog = readTaskCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].isCompleted = true
        catalog[idx].isOverdue = false
        writeTaskCatalog(catalog)
        if var snap = read() {
            snap.openTaskCount = catalog.filter { !$0.isCompleted }.count
            snap.overdueTaskCount = catalog.filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
            if snap.criticalTaskTitle == catalog[idx].title { snap.criticalTaskTitle = nil }
            write(snap)
        }
    }

    static func applyLocalWatering(_ id: UUID) {
        var catalog = readPlantCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].needsWatering = false
        writePlantCatalog(catalog)
        if var snap = read() {
            let needing = catalog.filter { $0.needsWatering }
            snap.plantsNeedingWater = needing.count
            snap.plantNames = Array(needing.prefix(3).map(\.name))
            write(snap)
        }
    }

    static func applyLocalSupplyCheck(_ id: UUID) {
        var catalog = readSupplyCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].isCompleted = true
        writeSupplyCatalog(catalog)
        if var snap = read() {
            snap.pendingSupplyCount = catalog.filter { !$0.isCompleted }.count
            write(snap)
        }
    }

    static func appendPendingCompletion(_ taskId: UUID) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        var pending = (ud.array(forKey: pendingCompletionsKey) as? [String]) ?? []
        let str = taskId.uuidString
        if !pending.contains(str) { pending.append(str) }
        ud.set(pending, forKey: pendingCompletionsKey)
    }

    static func popPendingCompletions() -> [UUID] {
        guard let ud = UserDefaults(suiteName: suiteName) else { return [] }
        let ids = ((ud.array(forKey: pendingCompletionsKey) as? [String]) ?? []).compactMap { UUID(uuidString: $0) }
        ud.removeObject(forKey: pendingCompletionsKey)
        return ids
    }
}

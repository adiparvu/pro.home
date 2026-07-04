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
}

struct PlantCatalogEntry: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var needsWatering: Bool
}

// MARK: - Store

enum SharedDataStore {
    static let suiteName = "group.com.prvio.app"

    private static let snapshotKey         = "prvio.widget.snapshot"
    private static let taskCatalogKey      = "prvio.catalog.tasks"
    private static let plantCatalogKey     = "prvio.catalog.plants"
    private static let pendingWateringsKey = "prvio.pending.waterings"
    private static let pendingCompletionsKey = "prvio.pending.completions"

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

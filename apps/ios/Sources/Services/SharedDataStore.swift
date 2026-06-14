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
    var activeDeliveryCount: Int = 0
    var updatedAt: Date = Date()
}

// MARK: - Store

enum SharedDataStore {
    static let suiteName = "group.com.prvio.app"
    private static let snapshotKey = "prvio.widget.snapshot"

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
}

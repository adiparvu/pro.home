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

// MARK: - Watch payload (pushed to the watch over WatchConnectivity)
//
// The watch is a different device — it cannot read the phone's App Group.
// The phone pushes this bundle (the same snapshot the widgets render, plus
// the task/plant catalogs for real lists) via updateApplicationContext,
// which WatchConnectivity persists and delivers even when the watch app
// launches later.

struct WatchPayload: Codable {
    var snapshot: PRVIOWidgetSnapshot
    var tasks: [TaskCatalogEntry] = []
    var plants: [PlantCatalogEntry] = []
    // Optional-by-default so payloads cached by the V1 watch app still decode.
    var supplies: [SupplyCatalogEntry] = []
    var deliveries: [DeliveryCatalogEntry] = []
    /// Property coordinates for the wrist map (nil until geocoded).
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// The top ProactiveEngine insight — the phone's intelligence, delivered
    /// to the wrist and readable offline.
    var insightTitle: String? = nil
    var insightBody: String? = nil
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

struct DeliveryCatalogEntry: Codable {
    var id: UUID
    var title: String
    var carrier: String?
    /// Raw status ("expected", "out_for_delivery", …) — the watch localizes it.
    var status: String
    var eta: String?
}

// MARK: - Watch action relay (widget extension → watch app → phone)
//
// Interactive complications run in the watch WIDGET extension, which cannot
// touch WCSession. Their actions queue here (App Group), and the watch APP
// forwards them to the phone on its next activation. Lives in this file
// because it must compile into both watch targets.

enum WatchActionRelay {
    private static let key = "prvio.watch.pendingRelay"
    private static var relayDefaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    static func append(action: String, id: String) {
        var pending = (relayDefaults.array(forKey: key) as? [[String: String]]) ?? []
        pending.append(["action": action, "id": id])
        relayDefaults.set(pending, forKey: key)
    }

    static func drain() -> [[String: String]] {
        let pending = (relayDefaults.array(forKey: key) as? [[String: String]]) ?? []
        relayDefaults.removeObject(forKey: key)
        return pending
    }
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

    // MARK: Delivery catalog

    private static let deliveryCatalogKey = "prvio.catalog.deliveries"

    static func writeDeliveryCatalog(_ items: [DeliveryCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: deliveryCatalogKey)
    }

    static func readDeliveryCatalog() -> [DeliveryCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: deliveryCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([DeliveryCatalogEntry].self, from: data)) ?? []
    }

    // MARK: Watch extras (coordinates + top insight, set by writeWidgetSnapshot)

    private static let watchExtrasKey = "prvio.watch.extras"

    struct WatchExtras: Codable {
        var latitude: Double?
        var longitude: Double?
        var insightTitle: String?
        var insightBody: String?
    }

    static func writeWatchExtras(_ extras: WatchExtras) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(extras) else { return }
        ud.set(data, forKey: watchExtrasKey)
    }

    static func readWatchExtras() -> WatchExtras {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: watchExtrasKey),
              let extras = try? JSONDecoder().decode(WatchExtras.self, from: data) else {
            return WatchExtras()
        }
        return extras
    }

    /// The watch payload assembled from the store alone — used to answer a
    /// wrist action instantly (after the local mutations) without needing the
    /// app's services to be alive.
    static func currentWatchPayload() -> WatchPayload? {
        guard let snapshot = read() else { return nil }
        let extras = readWatchExtras()
        return WatchPayload(snapshot: snapshot,
                            tasks: readTaskCatalog(),
                            plants: readPlantCatalog(),
                            supplies: readSupplyCatalog(),
                            deliveries: readDeliveryCatalog(),
                            latitude: extras.latitude,
                            longitude: extras.longitude,
                            insightTitle: extras.insightTitle,
                            insightBody: extras.insightBody)
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

    // MARK: App context for in-app intents (primary property + display name)

    private static let contextPropertyIdKey = "prvio.context.propertyId"
    private static let contextMyNameKey     = "prvio.context.myName"

    static func setContext(propertyId: UUID?, myName: String?) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        ud.set(propertyId?.uuidString, forKey: contextPropertyIdKey)
        ud.set(myName, forKey: contextMyNameKey)
    }

    static func contextPropertyId() -> UUID? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let s = ud.string(forKey: contextPropertyIdKey) else { return nil }
        return UUID(uuidString: s)
    }

    static func contextMyName() -> String? {
        UserDefaults(suiteName: suiteName)?.string(forKey: contextMyNameKey)
    }

    // MARK: Watch-dictated tasks (watch → phone → Supabase on next beat)

    private static let pendingWatchTasksKey = "prvio.pending.watchTasks"

    static func appendPendingWatchTask(_ title: String) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        var pending = (ud.array(forKey: pendingWatchTasksKey) as? [String]) ?? []
        pending.append(title)
        ud.set(pending, forKey: pendingWatchTasksKey)
    }

    static func popPendingWatchTasks() -> [String] {
        guard let ud = UserDefaults(suiteName: suiteName) else { return [] }
        let titles = (ud.array(forKey: pendingWatchTasksKey) as? [String]) ?? []
        ud.removeObject(forKey: pendingWatchTasksKey)
        return titles
    }

    // MARK: Chat replies typed on a notification (delegate → app → Supabase)

    private static let pendingChatRepliesKey = "prvio.pending.chatReplies"

    static func appendPendingChatReply(_ text: String) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        var pending = (ud.array(forKey: pendingChatRepliesKey) as? [String]) ?? []
        pending.append(text)
        ud.set(pending, forKey: pendingChatRepliesKey)
    }

    static func popPendingChatReplies() -> [String] {
        guard let ud = UserDefaults(suiteName: suiteName) else { return [] }
        let texts = (ud.array(forKey: pendingChatRepliesKey) as? [String]) ?? []
        ud.removeObject(forKey: pendingChatRepliesKey)
        return texts
    }

    // MARK: Control Center hand-off (control tap → app navigation)
    //
    // Control Center intents run in the widget-extension process. The
    // OpenURLIntent chain they return has proven flaky across iOS versions
    // (app opens but the URL never arrives, or nothing opens on cold start),
    // so the tapped destination is ALSO parked here and consumed by the app
    // on its next activation — the same App Group hand-off the widget
    // buttons rely on, which does work.

    private static let controlPathKey = "prvio.intent.controlPath"

    static func setControlPath(_ path: String) {
        UserDefaults(suiteName: suiteName)?.set(path, forKey: controlPathKey)
    }

    static func consumeControlPath() -> String? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let path = ud.string(forKey: controlPathKey) else { return nil }
        ud.removeObject(forKey: controlPathKey)
        return path
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

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

    init() {}

    /// Every field decodes leniently: a snapshot written by ANY app version
    /// must decode in every widget/watch process, or the widgets freeze on
    /// defaults. (activeDeliveryCount was added non-optional — old
    /// snapshots threw keyNotFound and the whole snapshot silently
    /// vanished.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overdueTaskCount     = try c.decodeIfPresent(Int.self,      forKey: .overdueTaskCount) ?? 0
        openTaskCount        = try c.decodeIfPresent(Int.self,      forKey: .openTaskCount) ?? 0
        pendingSupplyCount   = try c.decodeIfPresent(Int.self,      forKey: .pendingSupplyCount) ?? 0
        plantsNeedingWater   = try c.decodeIfPresent(Int.self,      forKey: .plantsNeedingWater) ?? 0
        plantNames           = try c.decodeIfPresent([String].self, forKey: .plantNames) ?? []
        unreadMessages       = try c.decodeIfPresent(Int.self,      forKey: .unreadMessages) ?? 0
        propertyName         = try c.decodeIfPresent(String.self,   forKey: .propertyName)
        propertyHealthScore  = try c.decodeIfPresent(Int.self,      forKey: .propertyHealthScore)
        criticalTaskTitle    = try c.decodeIfPresent(String.self,   forKey: .criticalTaskTitle)
        nextMaintenanceTitle = try c.decodeIfPresent(String.self,   forKey: .nextMaintenanceTitle)
        nextMaintenanceDue   = try c.decodeIfPresent(String.self,   forKey: .nextMaintenanceDue)
        activeDeliveryCount  = try c.decodeIfPresent(Int.self,      forKey: .activeDeliveryCount) ?? 0
        updatedAt            = try c.decodeIfPresent(Date.self,     forKey: .updatedAt) ?? Date()
    }
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
    /// Pantry stock for the wrist — consume-one taps ride the action queue.
    var pantry: [PantryCatalogEntry] = []
    /// Property coordinates for the wrist map (nil until geocoded).
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// The top ProactiveEngine insight — the phone's intelligence, delivered
    /// to the wrist and readable offline.
    var insightTitle: String? = nil
    var insightBody: String? = nil
    /// Apple Weather for the property (fetched on the phone). Advisory is a
    /// raw token ("frost" | "rain") — the watch localizes it.
    var weatherTemp: Double? = nil
    var weatherSymbol: String? = nil
    var weatherLo: Double? = nil
    var weatherHi: Double? = nil
    var weatherAdvisory: String? = nil
    /// Consecutive all-clear days (no overdue tasks, no thirsty plants) —
    /// the house streak, computed on the phone.
    var streakDays: Int? = nil
    /// This month's spending in the household currency, and the total
    /// monthly budget when one is set. Sums never mix currencies — records
    /// in other currencies are simply not included here.
    var budgetSpent: Double? = nil
    var budgetLimit: Double? = nil
    var budgetCurrency: String? = nil
    /// The owner's chosen watch pages, in their chosen order (page keys).
    /// nil means the default set — Today is always first and never listed.
    var pageOrder: [String]? = nil
    /// Live smart-home state for the wrist (empty until the user adds IoT
    /// devices). Optional-by-default so older cached payloads still decode.
    var sensors: [SensorCatalogEntry] = []
    var actuators: [ActuatorCatalogEntry] = []
    /// The property's emergency plan — shutoff steps + contacts — mirrored to
    /// the wrist for a real incident. Empty until the user fills it in.
    var emergencyContacts: [EmergencyContactEntry] = []
    var emergencySteps: [EmergencyStepEntry] = []
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
    /// Last computed Plant Health Score (0–100), or nil when not computed yet.
    /// Optional so catalogs written before P6 still decode, and so a plant the
    /// user hasn't scored yet honestly shows no number on the widget/watch.
    var healthScore: Int? = nil
}

struct SupplyCatalogEntry: Codable {
    var id: UUID
    var name: String
    var isCompleted: Bool
}

struct PantryCatalogEntry: Codable {
    var id: UUID
    var name: String
    var quantity: Double
    var unit: String
}

struct DeliveryCatalogEntry: Codable {
    var id: UUID
    var title: String
    var carrier: String?
    /// Raw status ("expected", "out_for_delivery", …) — the watch localizes it.
    var status: String
    var eta: String?
}

// MARK: - Smart-home catalogs (sensors + actuators for the wrist)

/// A sensor reading, flattened for the wrist. Everything is pre-formatted on
/// the phone (which owns the units/thresholds) so the watch just renders.
struct SensorCatalogEntry: Codable {
    var id: UUID
    var name: String
    var icon: String          // SF Symbol for the sensor type
    var displayValue: String  // "21.4 °C" — already formatted
    var zone: String?
    var isAlerting: Bool
    var isCritical: Bool
}

/// A controllable actuator (relay or cover). `commands` is the raw
/// ActuatorCommand vocabulary the phone will execute; the watch never invents
/// a command the actuator doesn't declare, so a wrist tap always maps to a
/// real device write.
struct ActuatorCatalogEntry: Codable {
    var id: UUID
    var name: String
    var kind: String          // "relay" | "cover"
    var isOn: Bool?
    var commands: [String]    // ["on","off"] | ["open","close","stop"]
}

// MARK: - Emergency (SOS on the wrist)
//
// Decoded from the phone's own emergency store, so the wrist shows the SAME
// contacts and shutoff notes the user configured — nothing fabricated. `phone`
// drives a real tel: call straight from the watch.

struct EmergencyContactEntry: Codable {
    var id: UUID
    var name: String
    var role: String
    var phone: String
}

struct EmergencyStepEntry: Codable {
    var id: UUID
    var title: String
    var detail: String
}

// MARK: - Watch action relay (widget extension → watch app → phone)
//
// Interactive complications run in the watch WIDGET extension, which cannot
// touch WCSession. Their actions queue here (App Group), and the watch APP
// forwards them to the phone on its next activation. Lives in this file
// because it must compile into both watch targets.

enum WatchActionRelay {
    private static let key = "prvio.watch.pendingRelay"

    static func append(action: String, id: String) {
        guard let data = try? JSONEncoder().encode(["action": action, "id": id]),
              let json = String(data: data, encoding: .utf8) else { return }
        SharedDataStore.coordinateQueue("watchRelay", legacyKey: nil) { queue in
            queue.append(json)
        }
    }

    static func drain() -> [[String: String]] {
        var drained = SharedDataStore.coordinateQueue("watchRelay", legacyKey: nil) { (queue: inout [String]) -> [[String: String]] in
            let entries = queue.compactMap { json -> [String: String]? in
                json.data(using: .utf8)
                    .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            }
            queue.removeAll()
            return entries
        } ?? []
        // One-time drain of actions a pre-coordination build queued in
        // UserDefaults (dictionary elements — the generic drain can't).
        if let ud = UserDefaults(suiteName: SharedDataStore.suiteName),
           let legacy = ud.array(forKey: key) as? [[String: String]], !legacy.isEmpty {
            ud.removeObject(forKey: key)
            drained = legacy + drained
        }
        return drained
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
    //
    // Every pending queue used to be a UserDefaults array, but UserDefaults
    // read-modify-write is not atomic across processes: a widget tap (in the
    // extension process) racing the app's foreground drain could silently
    // drop actions. Each queue is now a JSON file in the App Group container
    // and every mutation runs inside NSFileCoordinator's writing block — the
    // system serializes coordinated access across all group processes. The
    // old UserDefaults key is drained into the file on first touch so no
    // action written by a previous build is lost.

    private static var queuesDirectory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName) else { return nil }
        let dir = container.appendingPathComponent("Queues", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Atomically read-modify-write one queue. `body` mutates the queue in
    /// place; the file is rewritten only when it actually changed (and
    /// removed when it empties, so the directory never accumulates husks).
    @discardableResult
    fileprivate static func coordinateQueue<T>(_ name: String,
                                           legacyKey: String?,
                                           _ body: (inout [String]) -> T) -> T? {
        guard let url = queuesDirectory?.appendingPathComponent(name + ".json") else { return nil }
        var result: T?
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordError) { url in
            var queue = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            var dirty = false
            if let legacyKey, let ud = UserDefaults(suiteName: suiteName),
               let legacy = ud.array(forKey: legacyKey) as? [String], !legacy.isEmpty {
                queue = legacy + queue
                ud.removeObject(forKey: legacyKey)
                dirty = true
            }
            let before = queue
            result = body(&queue)
            if queue != before { dirty = true }
            guard dirty else { return }
            if queue.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else if let data = try? JSONEncoder().encode(queue) {
                try? data.write(to: url, options: .atomic)
            }
        }
        return result
    }

    /// Append once (the queue is idempotent — a second tap on the same
    /// button must not produce a second action).
    private static func coordinatedAppendUnique(_ name: String, legacyKey: String?, _ value: String) {
        coordinateQueue(name, legacyKey: legacyKey) { queue in
            if !queue.contains(value) { queue.append(value) }
        }
    }

    private static func coordinatedPop(_ name: String, legacyKey: String?) -> [String] {
        coordinateQueue(name, legacyKey: legacyKey) { queue in
            let drained = queue
            queue.removeAll()
            return drained
        } ?? []
    }

    static func appendPendingWatering(_ plantId: UUID) {
        coordinatedAppendUnique("waterings", legacyKey: pendingWateringsKey, plantId.uuidString)
    }

    static func popPendingWaterings() -> [UUID] {
        coordinatedPop("waterings", legacyKey: pendingWateringsKey).compactMap { UUID(uuidString: $0) }
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

    // MARK: Pantry catalog

    private static let pantryCatalogKey = "prvio.catalog.pantry"
    private static let pendingPantryConsumesKey = "prvio.pending.pantryConsumes"

    static func writePantryCatalog(_ items: [PantryCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: pantryCatalogKey)
    }

    static func readPantryCatalog() -> [PantryCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: pantryCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([PantryCatalogEntry].self, from: data)) ?? []
    }

    /// Each element is one "consume 1" tap — duplicates are meaningful,
    /// so this appends unconditionally (unlike the idempotent check queues).
    static func appendPendingPantryConsume(_ itemId: UUID) {
        coordinateQueue("pantryConsumes", legacyKey: pendingPantryConsumesKey) { queue in
            queue.append(itemId.uuidString)
        }
    }

    static func popPendingPantryConsumes() -> [UUID] {
        coordinatedPop("pantryConsumes", legacyKey: pendingPantryConsumesKey)
            .compactMap { UUID(uuidString: $0) }
    }

    static func applyLocalPantryConsume(_ id: UUID) {
        var catalog = readPantryCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].quantity = max(0, ((catalog[idx].quantity - 1) * 10).rounded() / 10)
        writePantryCatalog(catalog)
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

    // MARK: Smart-home catalogs + wrist commands

    private static let sensorCatalogKey   = "prvio.catalog.sensors"
    private static let actuatorCatalogKey = "prvio.catalog.actuators"
    private static let pendingIoTKey      = "prvio.watch.pendingIoT"

    static func writeSensorCatalog(_ items: [SensorCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: sensorCatalogKey)
    }
    static func readSensorCatalog() -> [SensorCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: sensorCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([SensorCatalogEntry].self, from: data)) ?? []
    }
    static func writeActuatorCatalog(_ items: [ActuatorCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: actuatorCatalogKey)
    }
    static func readActuatorCatalog() -> [ActuatorCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: actuatorCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([ActuatorCatalogEntry].self, from: data)) ?? []
    }

    /// A wrist-issued actuator command, parked for the app to execute on its
    /// next active beat. `transferUserInfo` already guaranteed delivery to the
    /// phone; this survives the phone being backgrounded when it arrives, so
    /// nothing is lost if the garage command lands while the app is closed.
    static func appendPendingIoTCommand(actuatorId: UUID, command: String) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        var q = ud.stringArray(forKey: pendingIoTKey) ?? []
        q.append("\(actuatorId.uuidString)|\(command)")
        ud.set(q, forKey: pendingIoTKey)
    }
    static func drainPendingIoTCommands() -> [(actuatorId: UUID, command: String)] {
        guard let ud = UserDefaults(suiteName: suiteName) else { return [] }
        let q = ud.stringArray(forKey: pendingIoTKey) ?? []
        ud.removeObject(forKey: pendingIoTKey)
        return q.compactMap { entry in
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]) else { return nil }
            return (id, parts[1])
        }
    }

    /// Optimistic relay echo so a wrist toggle feels instant before the phone
    /// confirms the real device write — mirrors applyLocalTaskCompletion.
    static func applyLocalActuatorState(id: UUID, isOn: Bool?) {
        var cat = readActuatorCatalog()
        guard let i = cat.firstIndex(where: { $0.id == id }) else { return }
        cat[i].isOn = isOn
        writeActuatorCatalog(cat)
    }

    // MARK: Emergency plan (read from the phone's own store, called on-phone
    // when the payload is built — the watch just receives the result).

    static func readEmergencyContacts() -> [EmergencyContactEntry] {
        guard let d = UserDefaults.standard.data(forKey: "prvio.emergency") else { return [] }
        return (try? JSONDecoder().decode([EmergencyContactEntry].self, from: d)) ?? []
    }
    static func readEmergencySteps() -> [EmergencyStepEntry] {
        guard let d = UserDefaults.standard.data(forKey: "prvio.emergency.notes") else { return [] }
        return (try? JSONDecoder().decode([EmergencyStepEntry].self, from: d)) ?? []
    }

    /// A wrist-triggered "start emergency mode" — parked because ActivityKit
    /// only lets the app START a Live Activity in the foreground. Drained by
    /// MainTabView on the next active beat.
    private static let pendingEmergencyKey = "prvio.watch.pendingEmergency"
    static func setPendingEmergencyStart() {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: pendingEmergencyKey)
    }
    static func consumePendingEmergencyStart() -> Bool {
        guard let ud = UserDefaults(suiteName: suiteName),
              ud.bool(forKey: pendingEmergencyKey) else { return false }
        ud.removeObject(forKey: pendingEmergencyKey)
        return true
    }

    /// Deliveries marked received from the Live Activity island — drained into
    /// DeliveryService.markDelivered on the app's next foreground beat.
    /// Idempotent: a second tap on the same delivery must not re-mark it.
    static func appendPendingDeliveryReceived(_ deliveryId: UUID) {
        coordinatedAppendUnique("deliveryReceived", legacyKey: nil, deliveryId.uuidString)
    }

    static func popPendingDeliveryReceived() -> [UUID] {
        coordinatedPop("deliveryReceived", legacyKey: nil).compactMap { UUID(uuidString: $0) }
    }

    // MARK: Watch extras (coordinates + top insight, set by writeWidgetSnapshot)

    private static let watchExtrasKey = "prvio.watch.extras"

    struct WatchExtras: Codable {
        var latitude: Double?
        var longitude: Double?
        var insightTitle: String?
        var insightBody: String?
        var weatherTemp: Double? = nil
        var weatherSymbol: String? = nil
        var weatherLo: Double? = nil
        var weatherHi: Double? = nil
        var weatherAdvisory: String? = nil
        var streakDays: Int? = nil
        var budgetSpent: Double? = nil
        var budgetLimit: Double? = nil
        var budgetCurrency: String? = nil
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
                            pantry: readPantryCatalog(),
                            latitude: extras.latitude,
                            longitude: extras.longitude,
                            insightTitle: extras.insightTitle,
                            insightBody: extras.insightBody,
                            weatherTemp: extras.weatherTemp,
                            weatherSymbol: extras.weatherSymbol,
                            weatherLo: extras.weatherLo,
                            weatherHi: extras.weatherHi,
                            weatherAdvisory: extras.weatherAdvisory,
                            streakDays: extras.streakDays,
                            budgetSpent: extras.budgetSpent,
                            budgetLimit: extras.budgetLimit,
                            budgetCurrency: extras.budgetCurrency,
                            pageOrder: visibleWatchPages(),
                            sensors: readSensorCatalog(),
                            actuators: readActuatorCatalog(),
                            emergencyContacts: readEmergencyContacts(),
                            emergencySteps: readEmergencySteps())
    }

    // MARK: Watch page personalization (chosen on the iPhone)

    /// Every page the watch can show, in the default order. Today is not
    /// listed — it is always first and can't be hidden.
    static let allWatchPages = ["tasks", "plants", "shopping", "pantry", "deliveries", "map"]

    private static let watchPageOrderKey  = "prvio.watch.pageOrder"
    private static let watchHiddenPagesKey = "prvio.watch.hiddenPages"

    static func writeWatchPagePrefs(order: [String], hidden: [String]) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        ud.set(order, forKey: watchPageOrderKey)
        ud.set(hidden, forKey: watchHiddenPagesKey)
    }

    /// The stored order, sanitized: unknown keys dropped, pages added in a
    /// later version appended — so an old preference never hides new pages.
    static func readWatchPagePrefs() -> (order: [String], hidden: Set<String>) {
        guard let ud = UserDefaults(suiteName: suiteName) else {
            return (allWatchPages, [])
        }
        let stored = (ud.array(forKey: watchPageOrderKey) as? [String]) ?? []
        // Dedupe while filtering: a duplicated key in the stored order
        // becomes two ForEach rows with the same identity on the watch —
        // undefined behavior that can crash the app at first render.
        var seen = Set<String>()
        var order = stored.filter { allWatchPages.contains($0) && seen.insert($0).inserted }
        order += allWatchPages.filter { !seen.contains($0) }
        let hidden = Set((ud.array(forKey: watchHiddenPagesKey) as? [String]) ?? [])
            .intersection(allWatchPages)
        return (order, hidden)
    }

    /// The pages the watch should show, in order — what rides the payload.
    static func visibleWatchPages() -> [String] {
        let prefs = readWatchPagePrefs()
        return prefs.order.filter { !prefs.hidden.contains($0) }
    }

    // MARK: House streak (consecutive all-clear days)

    private static let streakCountKey = "prvio.streak.count"
    private static let streakDayKey   = "prvio.streak.lastDay"

    /// Rolls the streak forward from today's observed state and returns the
    /// current count. All-clear extends (once per day); a bad day resets to
    /// zero. A day the app never opened breaks the chain honestly — we only
    /// count days we actually verified.
    static func updateHouseStreak(allClear: Bool) -> Int {
        guard let ud = UserDefaults(suiteName: suiteName) else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Date().addingTimeInterval(-86_400))

        let lastDay = ud.string(forKey: streakDayKey)
        var count = ud.integer(forKey: streakCountKey)

        if allClear {
            if lastDay == today {
                count = max(count, 1)
            } else if lastDay == yesterday {
                count += 1
            } else {
                count = 1
            }
        } else {
            count = 0
        }
        ud.set(count, forKey: streakCountKey)
        ud.set(today, forKey: streakDayKey)
        return count
    }

    /// Read-only view of the streak — for screens that report it without
    /// rolling the day forward (updateHouseStreak stays the only writer).
    static func currentHouseStreak() -> Int {
        UserDefaults(suiteName: suiteName)?.integer(forKey: streakCountKey) ?? 0
    }

    // MARK: Pending work session (watch → phone Live Activity)
    //
    // The watch's session start/end land here because Live Activities can
    // only be requested while the app is in the foreground — the phone
    // mirrors the wrist's timer the next time it's active (or instantly
    // when it already is). startedAt rides along so the Dynamic Island
    // shows the TRUE elapsed time, not the time since the mirror appeared.

    private static let pendingSessionKey = "prvio.pending.session"

    static func writePendingSessionStart(taskId: UUID, title: String, startedAt: Date) {
        writePendingSessionEvent(["id": taskId.uuidString, "title": title,
                                  "startedAt": String(startedAt.timeIntervalSince1970)])
    }

    static func writePendingSessionEnd() {
        writePendingSessionEvent(["end": "1"])
    }

    /// The session slot rides the coordinated queue as a single JSON-encoded
    /// element — the newest event replaces whatever was waiting, as before.
    private static func writePendingSessionEvent(_ event: [String: String]) {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        coordinateQueue("session", legacyKey: nil) { queue in
            queue = [json]
        }
        // The slot moved out of UserDefaults — clear any event an older
        // build left there so it can't resurrect after this one is consumed.
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: pendingSessionKey)
    }

    /// nil = nothing pending; (nil) start = the session should END.
    static func consumePendingSessionEvent() -> (start: (taskId: UUID, title: String, startedAt: Date)?, isEnd: Bool)? {
        var event: [String: String]?
        coordinateQueue("session", legacyKey: nil) { queue in
            if let json = queue.first, let data = json.data(using: .utf8) {
                event = try? JSONDecoder().decode([String: String].self, from: data)
            }
            queue.removeAll()
        }
        // One-time drain of a slot written by a pre-coordination build.
        if event == nil, let ud = UserDefaults(suiteName: suiteName),
           let legacy = ud.dictionary(forKey: pendingSessionKey) as? [String: String] {
            ud.removeObject(forKey: pendingSessionKey)
            event = legacy
        }
        guard let dict = event else { return nil }
        if dict["end"] == "1" { return (start: nil, isEnd: true) }
        guard let idStr = dict["id"], let id = UUID(uuidString: idStr),
              let title = dict["title"],
              let ts = dict["startedAt"].flatMap(Double.init) else { return nil }
        return (start: (taskId: id, title: title, startedAt: Date(timeIntervalSince1970: ts)), isEnd: false)
    }

    static func appendPendingSupplyCheck(_ itemId: UUID) {
        coordinatedAppendUnique("supplyChecks", legacyKey: pendingSupplyChecksKey, itemId.uuidString)
    }

    static func popPendingSupplyChecks() -> [UUID] {
        coordinatedPop("supplyChecks", legacyKey: pendingSupplyChecksKey)
            .compactMap { UUID(uuidString: $0) }
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
        coordinateQueue("watchTasks", legacyKey: pendingWatchTasksKey) { queue in
            queue.append(title)
        }
    }

    static func popPendingWatchTasks() -> [String] {
        coordinatedPop("watchTasks", legacyKey: pendingWatchTasksKey)
    }

    // MARK: Chat replies typed on a notification (delegate → app → Supabase)

    private static let pendingChatRepliesKey = "prvio.pending.chatReplies"

    static func appendPendingChatReply(_ text: String) {
        coordinateQueue("chatReplies", legacyKey: pendingChatRepliesKey) { queue in
            queue.append(text)
        }
    }

    static func popPendingChatReplies() -> [String] {
        coordinatedPop("chatReplies", legacyKey: pendingChatRepliesKey)
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
        coordinatedAppendUnique("completions", legacyKey: pendingCompletionsKey, taskId.uuidString)
    }

    static func popPendingCompletions() -> [UUID] {
        coordinatedPop("completions", legacyKey: pendingCompletionsKey)
            .compactMap { UUID(uuidString: $0) }
    }
}

import ActivityKit
import AppIntents
import Foundation

// MARK: - Live Activity preferences (shared app ↔ widget extension)
//
// This file is compiled into BOTH the app and the widgets target, so it is the
// single source of truth for Live Activity preferences. Values live in the app
// group suite — the widget extension renders the activity, so prefs written to
// UserDefaults.standard would be invisible to it (the old bug: the settings
// screen only ever restyled its own mock preview).

enum LiveActivityPrefs {
    static let suiteName = "group.com.prvio.app"

    static let enabledKey       = "prvio.la.enabled"
    static let startOnOpenKey   = "prvio.la.startOnOpen"
    static let scheduleKey      = "prvio.la.schedule"
    static let lockScreenKey    = "prvio.la.lockScreen"
    static let dynamicIslandKey = "prvio.la.dynamicIsland"
    static let showProgressKey  = "prvio.la.showProgress"
    static let showETAKey       = "prvio.la.showETA"
    static let showPropertyKey  = "prvio.la.showProperty"
    static let islandStyleKey   = "prvio.la.islandStyle"
    static let autoShoppingKey  = "prvio.la.auto.shopping"
    static let autoDeliveryKey  = "prvio.la.auto.delivery"
    static let autoMaintKey     = "prvio.la.auto.maintenance"
    static let autoPlantKey     = "prvio.la.auto.plant"

    static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func bool(_ key: String, default def: Bool) -> Bool {
        // Fall back to .standard so preferences set before the app-group
        // migration keep their value.
        if let v = store.object(forKey: key) as? Bool { return v }
        return UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    static var isEnabled:        Bool { bool(enabledKey,       default: true) }
    static var startOnOpen:      Bool { bool(startOnOpenKey,   default: false) }
    static var startOnSchedule:  Bool { bool(scheduleKey,      default: false) }
    static var showOnLockScreen: Bool { bool(lockScreenKey,    default: true) }
    static var showDynamicIsland: Bool { bool(dynamicIslandKey, default: true) }
    static var showProgress:     Bool { bool(showProgressKey,  default: true) }
    static var showETA:          Bool { bool(showETAKey,       default: true) }
    static var showProperty:     Bool { bool(showPropertyKey,  default: true) }

    static var islandStyle: DynamicIslandStyle {
        DynamicIslandStyle(rawValue: store.string(forKey: islandStyleKey)
                           ?? UserDefaults.standard.string(forKey: islandStyleKey)
                           ?? "") ?? .detailed
    }

    // MARK: - Per-activity overrides
    //
    // Each activity kind ("shopping" / "delivery" / "maintenance" / "plantCare")
    // can keep its OWN appearance that overrides the global one. Every getter
    // falls back to the global value unless that kind's custom flag is on, so
    // nothing changes until the user deliberately customizes one activity.

    static func customKey(_ kind: String) -> String { "prvio.la.custom.\(kind)" }
    static func scopedKey(_ base: String, _ kind: String) -> String { "\(base).\(kind)" }

    static func hasCustom(_ kind: String) -> Bool { bool(customKey(kind), default: false) }

    static func showOnLockScreen(for kind: String?) -> Bool {
        guard let k = kind, hasCustom(k) else { return showOnLockScreen }
        return bool(scopedKey(lockScreenKey, k), default: showOnLockScreen)
    }
    static func showDynamicIsland(for kind: String?) -> Bool {
        guard let k = kind, hasCustom(k) else { return showDynamicIsland }
        return bool(scopedKey(dynamicIslandKey, k), default: showDynamicIsland)
    }
    static func showProgress(for kind: String?) -> Bool {
        guard let k = kind, hasCustom(k) else { return showProgress }
        return bool(scopedKey(showProgressKey, k), default: showProgress)
    }
    static func showETA(for kind: String?) -> Bool {
        guard let k = kind, hasCustom(k) else { return showETA }
        return bool(scopedKey(showETAKey, k), default: showETA)
    }
    static func showProperty(for kind: String?) -> Bool {
        guard let k = kind, hasCustom(k) else { return showProperty }
        return bool(scopedKey(showPropertyKey, k), default: showProperty)
    }
    static func islandStyle(for kind: String?) -> DynamicIslandStyle {
        guard let k = kind, hasCustom(k) else { return islandStyle }
        let raw = store.string(forKey: scopedKey(islandStyleKey, k))
            ?? UserDefaults.standard.string(forKey: scopedKey(islandStyleKey, k))
        return DynamicIslandStyle(rawValue: raw ?? "") ?? islandStyle
    }
}

enum DynamicIslandStyle: String, CaseIterable, Identifiable {
    case detailed, compact, minimal
    var id: String { rawValue }
}

// MARK: - Shopping Live Activity

struct ShoppingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var itemsBought: Int
        var totalItems: Int
        var listName: String
    }
    let propertyName: String
    let listName: String
}

// MARK: - Maintenance Live Activity

struct MaintenanceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var stepDescription: String
        var isComplete: Bool
    }
    let taskTitle: String
    let category: String
    var propertyName: String?
}

// MARK: - Delivery Live Activity

struct DeliveryActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var statusLabel: String
        var eta: String?
        // Milestone journey (all optional so payloads started before these
        // fields existed — and pushes from older senders — still decode).
        var milestoneIndex: Int?   // 0 ordered · 1 in transit · 2 out for delivery · 3 delivered
        var checkpoint: String?    // latest human-readable event ("Sorted · Cluj")
        var isProblem: Bool?       // exception / failed attempt / expired
    }
    let trackingNumber: String
    let carrier: String
    let description: String
    // Optional so old payloads (started before this field existed) still decode.
    var propertyName: String?
}

// MARK: - Plant Care Live Activity

struct PlantCareActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var wateredCount: Int
        var totalCount: Int
        var lastWateredName: String?
    }
    let propertyName: String
}

// MARK: - Work Session Live Activity
//
// The phone half of the watch's V10 session timer: the elapsed time lives in
// the Dynamic Island and on the Lock Screen, counted by the system from the
// fixed start date — no updates needed while it runs.

struct WorkSessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isComplete: Bool
    }
    let taskId: UUID
    let taskTitle: String
    let startedAt: Date
    var propertyName: String?
}

// MARK: - Emergency incident Live Activity
//
// Pinned by the user from the Emergency page during a real incident (burst
// pipe, power cut): keeps the numbers/valves page one tap away in the
// Dynamic Island, with the elapsed time counted by the system from the fixed
// start date. Never started automatically and never marked stale — it runs
// until the person says the incident is over.

struct EmergencyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isActive: Bool
    }
    let startedAt: Date
    var propertyName: String?
}

struct EndEmergencyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Emergency"

    init() {}

    func perform() async throws -> some IntentResult {
        HapticFeedback.impact(.medium)
        for activity in Activity<EmergencyActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: .init(isActive: false), staleDate: nil),
                dismissalPolicy: .immediate)
        }
        return .result()
    }
}

// MARK: - IoT alert Live Activity
//
// Raised when one of the user's own sensors crosses its limits (or a smoke
// sensor fires). Started only from real polled readings; ends when the
// sensor clears or the user acknowledges this instance.

struct IoTAlertActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var valueDisplay: String
        var isActive: Bool
    }
    let sensorId: UUID
    let sensorName: String
    let icon: String
    let isCritical: Bool
    let zone: String?
    let startedAt: Date
    var propertyName: String?
}

struct AcknowledgeIoTAlertIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Acknowledge Alert"

    @Parameter(title: "Sensor ID")
    var sensorId: String

    init() {}
    init(sensorId: UUID) { self.sensorId = sensorId.uuidString }

    func perform() async throws -> some IntentResult {
        HapticFeedback.impact(.light)
        // Remember the acknowledgement (app-group so the app's sync loop
        // sees it) — otherwise the next sensor poll would re-raise the same
        // alert seconds later. Cleared when the sensor itself clears.
        var acked = LiveActivityPrefs.store.stringArray(forKey: "prvio.iot.ackedAlerts") ?? []
        if !acked.contains(sensorId) { acked.append(sensorId) }
        LiveActivityPrefs.store.set(acked, forKey: "prvio.iot.ackedAlerts")

        for activity in Activity<IoTAlertActivityAttributes>.activities
        where activity.attributes.sensorId.uuidString == sensorId {
            await activity.end(
                ActivityContent(state: .init(valueDisplay: activity.content.state.valueDisplay,
                                             isActive: false), staleDate: nil),
                dismissalPolicy: .immediate)
        }
        return .result()
    }
}

// MARK: - Energy Live Activity
//
// A live gauge over the user's own power sensors: consumption vs tagged
// production (solar). User-started from the IoT hub; values update with
// every real poll — never invented.

struct EnergyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var consumptionW: Double?
        var productionW: Double?
    }
    let startedAt: Date
    var propertyName: String?
}

struct EndEnergySessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Energy Session"

    init() {}

    func perform() async throws -> some IntentResult {
        HapticFeedback.impact(.light)
        for activity in Activity<EnergyActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate)
        }
        return .result()
    }
}

// MARK: - Cover Live Activity (garage / gate)
//
// Follows one user-issued open/close/stop command: sent → moving →
// open/closed (only when a linked feedback sensor confirms it) or
// done/timeout/failed. Stage vocabulary is localized on-device.

struct CoverActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: String // sent / moving / open / closed / stopped / done / timeout / failed
    }
    let deviceName: String
    let startedAt: Date
}

// MARK: - Work session buttons (run in the app's process)
//
// These live in this shared file because the widget extension must SEE the
// intent types to render the buttons, while LiveActivityIntent executes them
// in the app's process. They speak only App Group + ActivityKit — never
// app-target services — so both targets compile.

struct CompleteWorkSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete Task"

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}
    init(taskId: UUID) { self.taskId = taskId.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskId) {
            SharedDataStore.appendPendingCompletion(id)
        }
        // Runs in the app's process: confirms the completion when the app is
        // active; a silent no-op when it's backgrounded.
        HapticFeedback.success()
        for activity in Activity<WorkSessionActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: .init(isComplete: true), staleDate: nil),
                dismissalPolicy: .after(.now + 2))
        }
        // Same channel the widget buttons use; the app drains the pending
        // completion on its next foreground (or instantly when running).
        NotificationCenter.default.post(name: Notification.Name("prvio.processPending"), object: nil)
        return .result()
    }
}

struct EndWorkSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Session"

    init() {}

    func perform() async throws -> some IntentResult {
        HapticFeedback.impact(.light)
        for activity in Activity<WorkSessionActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: .init(isComplete: false), staleDate: nil),
                dismissalPolicy: .immediate)
        }
        return .result()
    }
}

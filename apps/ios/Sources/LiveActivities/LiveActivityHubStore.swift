import Foundation
import ActivityKit
import SwiftUI
import UserNotifications

// MARK: - Live Activities Hub store
//
// The data core of the Live Activities Hub. Every number the hub shows comes
// from here, and everything here comes from real sources only:
//   • `active`  — a snapshot enumerated straight from ActivityKit
//                 (`Activity<Attrs>.activities` for all nine attribute types),
//                 mapped to display rows using each ContentState's real fields.
//   • `events`  — a persistent lifecycle log written by LiveActivityService's
//                 start/update/end hooks, stored as JSON in the app-group
//                 container (capped to the 600 newest).
//   • favorites — the user's pinned kinds, persisted in the shared prefs suite.
// Nothing is ever fabricated: no events → empty log, no activities → zero.

@MainActor @Observable
final class LiveActivityHubStore {
    static let shared = LiveActivityHubStore()

    // MARK: - Active activities (real ActivityKit enumeration)

    struct HubActivity: Identifiable, Equatable {
        let id: String                 // ActivityKit activity.id
        let kind: LiveActivityKind
        let title: String              // real content (delivery description, task title…)
        let detail: String             // real status line (statusLabel, step, count…)
        let progress: Double?          // nil when the kind has none
        let startedAt: Date?           // attribute start date, or event-log match, else nil
        let propertyName: String?
    }

    private(set) var active: [HubActivity] = []

    private init() {
        favoriteKinds = Set(LiveActivityPrefs.store.stringArray(forKey: Self.favoritesKey) ?? [])
        reloadEvents()
    }

    /// Rebuilds `active` by enumerating the system's running activities for
    /// ALL nine attribute types. Cheap (a handful of items), synchronous, and
    /// safe to call on every pulse — the hub refreshes it every few seconds
    /// while visible.
    func refresh() {
        var items: [HubActivity] = []

        for a in Activity<ShoppingActivityAttributes>.activities {
            let s = a.content.state
            items.append(HubActivity(
                id: a.id, kind: .shopping,
                title: s.listName.isEmpty ? a.attributes.listName : s.listName,
                detail: "\(s.itemsBought)/\(s.totalItems)",
                progress: s.totalItems > 0 ? Double(s.itemsBought) / Double(s.totalItems) : nil,
                startedAt: loggedStart(.shopping, title: s.listName.isEmpty ? a.attributes.listName : s.listName),
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<DeliveryActivityAttributes>.activities {
            let s = a.content.state
            items.append(HubActivity(
                id: a.id, kind: .delivery,
                title: a.attributes.description,
                detail: s.statusLabel,
                progress: s.milestoneIndex.map { Double(min(max($0, 0), 3)) / 3.0 },
                startedAt: loggedStart(.delivery, title: a.attributes.description),
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<MaintenanceActivityAttributes>.activities {
            let s = a.content.state
            items.append(HubActivity(
                id: a.id, kind: .maintenance,
                title: a.attributes.taskTitle,
                detail: s.stepDescription,
                progress: s.progress,
                startedAt: loggedStart(.maintenance, title: a.attributes.taskTitle),
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<PlantCareActivityAttributes>.activities {
            let s = a.content.state
            let count = "\(s.wateredCount)/\(s.totalCount)"
            items.append(HubActivity(
                id: a.id, kind: .plantCare,
                title: String(localized: "Plant watering"),
                detail: s.lastWateredName.map { "\(count) · \($0)" } ?? count,
                progress: s.totalCount > 0 ? Double(s.wateredCount) / Double(s.totalCount) : nil,
                startedAt: loggedStart(.plantCare, title: String(localized: "Plant watering")),
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<WorkSessionActivityAttributes>.activities {
            items.append(HubActivity(
                id: a.id, kind: .workSession,
                title: a.attributes.taskTitle,
                detail: String(localized: "In progress"),
                progress: nil,
                startedAt: a.attributes.startedAt,
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<EmergencyActivityAttributes>.activities {
            items.append(HubActivity(
                id: a.id, kind: .emergency,
                title: String(localized: "Emergency"),
                detail: String(localized: "la_emergency_active"),
                progress: nil,
                startedAt: a.attributes.startedAt,
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<IoTAlertActivityAttributes>.activities {
            let s = a.content.state
            items.append(HubActivity(
                id: a.id, kind: .iotAlert,
                title: a.attributes.sensorName,
                detail: a.attributes.zone.map { "\(s.valueDisplay) · \($0)" } ?? s.valueDisplay,
                progress: nil,
                startedAt: a.attributes.startedAt,
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<EnergyActivityAttributes>.activities {
            let s = a.content.state
            items.append(HubActivity(
                id: a.id, kind: .energy,
                title: String(localized: "Energy"),
                detail: Self.energyDetail(consumptionW: s.consumptionW, productionW: s.productionW),
                progress: nil,
                startedAt: a.attributes.startedAt,
                propertyName: nonEmpty(a.attributes.propertyName)))
        }

        for a in Activity<CoverActivityAttributes>.activities {
            items.append(HubActivity(
                id: a.id, kind: .cover,
                title: a.attributes.deviceName,
                detail: Self.coverStageLabel(a.content.state.stage),
                progress: nil,
                startedAt: a.attributes.startedAt,
                propertyName: nil))
        }

        active = items
    }

    /// Ends that specific activity (matched by ActivityKit id within its
    /// attribute type), logs the end, then refreshes the snapshot.
    func end(_ item: HubActivity) {
        Self.record(kind: item.kind, phase: "ended", title: item.title)
        Task {
            switch item.kind {
            case .shopping:    await Self.end(ShoppingActivityAttributes.self, id: item.id)
            case .delivery:    await Self.end(DeliveryActivityAttributes.self, id: item.id)
            case .maintenance: await Self.end(MaintenanceActivityAttributes.self, id: item.id)
            case .plantCare:   await Self.end(PlantCareActivityAttributes.self, id: item.id)
            case .workSession: await Self.end(WorkSessionActivityAttributes.self, id: item.id)
            case .emergency:   await Self.end(EmergencyActivityAttributes.self, id: item.id)
            case .iotAlert:    await Self.end(IoTAlertActivityAttributes.self, id: item.id)
            case .energy:      await Self.end(EnergyActivityAttributes.self, id: item.id)
            case .cover:       await Self.end(CoverActivityAttributes.self, id: item.id)
            }
            refresh()
        }
    }

    private static func end<A: ActivityAttributes>(_: A.Type, id: String) async {
        for a in Activity<A>.activities where a.id == id {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Favorites (pinned kinds, persisted in the shared prefs suite)

    private static let favoritesKey = "prvio.la.favorites"

    private(set) var favoriteKinds: Set<String> = []

    func isFavorite(_ kind: LiveActivityKind) -> Bool {
        favoriteKinds.contains(kind.rawValue)
    }

    func toggleFavorite(_ kind: LiveActivityKind) {
        if !favoriteKinds.insert(kind.rawValue).inserted {
            favoriteKinds.remove(kind.rawValue)
        }
        LiveActivityPrefs.store.set(favoriteKinds.sorted(), forKey: Self.favoritesKey)
    }

    // MARK: - Lifecycle event log (app-group JSON, 600 newest)

    struct LAEvent: Codable, Identifiable, Equatable {
        let id: UUID
        let kind: String               // LiveActivityKind.rawValue
        let phase: String              // "started" | "updated" | "ended" | "completed"
        let title: String
        let at: Date
    }

    /// Newest first — `events.first` is the most recent lifecycle event.
    private(set) var events: [LAEvent] = []

    /// Re-reads the persisted log off the main thread and publishes it.
    func reloadEvents() {
        LAEventLog.queue.async {
            let list = LAEventLog.load()
            Task { @MainActor in
                LiveActivityHubStore.shared.events = list
            }
        }
    }

    /// Appends one real lifecycle event to the shared log (thread-safe via a
    /// serial queue), pushes the fresh log to the live store, and — when the
    /// user enabled the rule for this kind — posts a local notification for
    /// "ended"/"completed" phases. Callable from any context.
    nonisolated static func record(kind: LiveActivityKind, phase: String, title: String) {
        let event = LAEvent(id: UUID(), kind: kind.rawValue, phase: phase, title: title, at: Date())
        LAEventLog.queue.async {
            var list = LAEventLog.load()
            list.insert(event, at: 0)
            if list.count > LAEventLog.cap { list.removeLast(list.count - LAEventLog.cap) }
            LAEventLog.save(list)
            Task { @MainActor in
                LiveActivityHubStore.shared.events = list
            }

            guard phase == "ended" || phase == "completed",
                  LiveActivityPrefs.bool(LiveActivityPrefs.notifyEndKey(kind.rawValue), default: false)
            else { return }
            postEndNotification(kind: kind, title: title)
        }
    }

    /// Local "activity ended" notification — only ever reached when the user
    /// turned the rule on for this kind. "Silent" priority keeps the banner
    /// but mutes the sound; if notifications aren't authorized the system
    /// simply drops the request.
    private nonisolated static func postEndNotification(kind: LiveActivityKind, title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "la_hub_notify_ended")
        let priority = LiveActivityPrefs.store.string(forKey: LiveActivityPrefs.priorityKey(kind.rawValue)) ?? "normal"
        content.sound = priority == "silent" ? nil : .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "prvio.la.end.\(UUID().uuidString)",
                                  content: content, trigger: nil))
    }

    // MARK: - Helpers

    /// Real start instant recovered from the lifecycle log (newest matching
    /// "started" event). Nil when the activity predates the log — never
    /// estimated or invented.
    private func loggedStart(_ kind: LiveActivityKind, title: String) -> Date? {
        events.first { $0.kind == kind.rawValue && $0.phase == "started" && $0.title == title }?.at
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func energyDetail(consumptionW: Double?, productionW: Double?) -> String {
        func fmt(_ w: Double) -> String {
            w >= 1000 ? String(format: "%.1f kW", w / 1000) : String(format: "%.0f W", w)
        }
        let parts = [consumptionW.map { "↓ " + fmt($0) },
                     productionW.map { "↑ " + fmt($0) }].compactMap { $0 }
        return parts.isEmpty ? String(localized: "la_hub_no_reading")
                             : parts.joined(separator: " · ")
    }

    /// Same stage vocabulary the widget's cover views localize on-device.
    private static func coverStageLabel(_ stage: String) -> String {
        let key: String.LocalizationValue
        switch stage {
        case "sent":    key = "la_cover_sent"
        case "moving":  key = "la_cover_moving"
        case "open":    key = "la_cover_open"
        case "closed":  key = "la_cover_closed"
        case "stopped": key = "la_cover_stopped"
        case "done":    key = "la_cover_done"
        case "timeout": key = "la_cover_timeout"
        default:        key = "la_cover_failed"
        }
        return String(localized: key)
    }
}

// MARK: - Event log persistence
//
// File-scope on purpose: the serial queue and file helpers are shared by the
// main-actor store and the nonisolated `record`, with no actor hops around
// disk I/O. All reads/writes happen on this one queue.

private enum LAEventLog {
    static let queue = DispatchQueue(label: "com.prvio.la.eventlog", qos: .utility)
    static let cap = 600

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: LiveActivityPrefs.suiteName)?
            .appendingPathComponent("la-events.json")
    }

    /// Newest first. Any read/decode failure yields an empty log — the hub
    /// then honestly shows "no history", never placeholder numbers.
    static func load() -> [LiveActivityHubStore.LAEvent] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([LiveActivityHubStore.LAEvent].self, from: data)
        else { return [] }
        return list.sorted { $0.at > $1.at }
    }

    static func save(_ events: [LiveActivityHubStore.LAEvent]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

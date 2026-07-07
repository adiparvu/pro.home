import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

// MARK: - PRVIO for Apple Watch
//
// A working companion: the phone pushes the same snapshot the widgets render
// (plus the task/plant/supply/delivery catalogs) over WatchConnectivity, and
// the watch shows it in vertical pages — Today, Tasks, Plants, Shopping,
// Deliveries. V2 acts from the wrist: completing a task, watering a plant or
// checking off a purchase mutates the local payload instantly and queues the
// action to the phone through transferUserInfo, which WatchConnectivity
// delivers even if the iPhone is unreachable right now.

@main
struct PRVIOWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

// MARK: - Store (session delegate + cache)

@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    private(set) var payload: WatchPayload?

    private static let cacheKey = "prvio.watch.payload"
    /// The App Group suite, so the watch-face complications read the same
    /// payload the app renders. Falls back to standard if the group is
    /// unavailable (e.g. simulator without entitlements).
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    override init() {
        super.init()
        // Render instantly from the last delivery, then refresh live.
        if let data = Self.defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WatchPayload.self, from: data) {
            payload = cached
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func ingest(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data else { return }
        ingestData(data)
    }

    private func ingestData(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        Task { @MainActor in
            self.payload = decoded
            Self.defaults.set(data, forKey: Self.cacheKey)
            // Fresh state → repaint the watch-face complications too.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: On-demand refresh
    //
    // applicationContext delivers "eventually"; when the phone is reachable
    // RIGHT NOW, the live channel answers instantly — and when it isn't, the
    // retry haptic says so instead of pretending.

    private(set) var isRefreshing = false

    func requestRefresh() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.isReachable else {
            WKInterfaceDevice.current().play(.retry)
            return
        }
        isRefreshing = true
        session.sendMessage(["action": "refresh"], replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.isRefreshing = false
                if let data = reply["payload"] as? Data {
                    self?.ingestData(data)
                    WKInterfaceDevice.current().play(.click)
                }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.isRefreshing = false
                WKInterfaceDevice.current().play(.retry)
            }
        })
    }

    // MARK: Wrist actions
    //
    // Mutate the cached payload immediately (the wrist must feel instant),
    // then queue the action to the phone. transferUserInfo persists across
    // unreachability and app restarts, so nothing is lost on a hike; the
    // phone lands it in the same pending-action pipeline the widget buttons
    // use and answers with a fresh authoritative payload.

    func completeTask(_ id: UUID) {
        mutate { payload in
            guard let i = payload.tasks.firstIndex(where: { $0.id == id }) else { return }
            payload.tasks[i].isCompleted = true
            payload.tasks[i].isOverdue = false
            payload.snapshot.openTaskCount = payload.tasks.filter { !$0.isCompleted }.count
            payload.snapshot.overdueTaskCount = payload.tasks.filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
            if payload.snapshot.criticalTaskTitle == payload.tasks[i].title {
                payload.snapshot.criticalTaskTitle = nil
            }
        }
        queue(action: "completeTask", id: id, haptic: .success)
    }

    func waterPlant(_ id: UUID) {
        mutate { payload in
            guard let i = payload.plants.firstIndex(where: { $0.id == id }) else { return }
            payload.plants[i].needsWatering = false
            let thirsty = payload.plants.filter(\.needsWatering)
            payload.snapshot.plantsNeedingWater = thirsty.count
            payload.snapshot.plantNames = Array(thirsty.prefix(3).map(\.name))
        }
        queue(action: "waterPlant", id: id, haptic: .directionUp)
    }

    func checkSupply(_ id: UUID) {
        mutate { payload in
            guard let i = payload.supplies.firstIndex(where: { $0.id == id }) else { return }
            payload.supplies[i].isCompleted = true
            payload.snapshot.pendingSupplyCount = payload.supplies.filter { !$0.isCompleted }.count
        }
        queue(action: "checkSupply", id: id, haptic: .click)
    }

    /// Dictated on the wrist; the phone creates the real task. Optimistic:
    /// it appears in the local list immediately so the wrist feels instant.
    func createTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { payload in
            payload.tasks.insert(TaskCatalogEntry(id: UUID(), title: trimmed,
                                                  priority: "medium",
                                                  isCompleted: false,
                                                  isOverdue: false), at: 0)
            payload.snapshot.openTaskCount += 1
        }
        WKInterfaceDevice.current().play(.success)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "createTask", "title": trimmed])
    }

    /// One tap, every thirsty plant — each watering still syncs individually.
    func waterAllPlants() {
        let thirsty = payload?.plants.filter(\.needsWatering) ?? []
        for plant in thirsty { waterPlant(plant.id) }
    }

    /// One unit off the pantry stock, from the wrist.
    func consumePantry(_ id: UUID) {
        mutate { payload in
            guard let i = payload.pantry.firstIndex(where: { $0.id == id }) else { return }
            payload.pantry[i].quantity = max(0, ((payload.pantry[i].quantity - 1) * 10).rounded() / 10)
        }
        queue(action: "consumePantry", id: id, haptic: .click)
    }

    // MARK: Work session (a maintenance timer on the wrist)
    //
    // Honest scope: the elapsed time is computed from the persisted start
    // date, so the session survives the app closing and the watch sleeping —
    // but the quarter-hour haptic only fires while the session screen is up
    // (background haptics would require a workout session we can't justify).

    struct WorkSession: Codable, Equatable {
        var taskId: UUID
        var title: String
        var startedAt: Date
    }

    private static let sessionKey = "prvio.watch.session"

    private(set) var activeSession: WorkSession? = {
        guard let data = (UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard)
            .data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(WorkSession.self, from: data)
    }()

    func startSession(taskId: UUID, title: String) {
        let session = WorkSession(taskId: taskId, title: title, startedAt: Date())
        activeSession = session
        if let data = try? JSONEncoder().encode(session) {
            Self.defaults.set(data, forKey: Self.sessionKey)
        }
        WKInterfaceDevice.current().play(.start)
        // Mirror on the iPhone as a Live Activity. The phone can only start
        // one while foregrounded, so this queues honestly via userInfo — the
        // Dynamic Island appears the next time the phone is active, showing
        // the TRUE elapsed time (the start date rides along).
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([
            "action": "sessionStart",
            "id": taskId.uuidString,
            "title": title,
            "startedAt": String(session.startedAt.timeIntervalSince1970),
        ])
    }

    /// Ends the session; optionally completes the task it timed.
    func endSession(completingTask: Bool) {
        let session = activeSession
        activeSession = nil
        Self.defaults.removeObject(forKey: Self.sessionKey)
        if completingTask, let session { completeTask(session.taskId) }
        else { WKInterfaceDevice.current().play(.stop) }
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sessionEnd"])
    }

    /// Dictated on the wrist for the house chat — the phone sends the real
    /// message on its next beat. transferUserInfo persists across
    /// unreachability, so nothing dictated is ever lost.
    func sendChatMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        WKInterfaceDevice.current().play(.success)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sendMessage", "text": trimmed])
    }

    private func mutate(_ change: (inout WatchPayload) -> Void) {
        guard var current = payload else { return }
        change(&current)
        payload = current
        if let data = try? JSONEncoder().encode(current) {
            Self.defaults.set(data, forKey: Self.cacheKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Each action speaks its own haptic dialect — completing lands with
    /// success, watering lifts, checking off clicks.
    private func queue(action: String, id: UUID, haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": action, "id": id.uuidString])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // applicationContext is persisted by the system — the newest push is
        // already waiting here even if the watch app wasn't running for it.
        guard activationState == .activated else { return }
        ingest(session.receivedApplicationContext)
        // Actions performed on the face (interactive complications) queued in
        // the App Group while the app was closed — forward them to the phone.
        for entry in WatchActionRelay.drain() {
            guard let action = entry["action"], let id = entry["id"] else { continue }
            session.transferUserInfo(["action": action, "id": id])
        }
        Task { @MainActor [weak self] in
            // Re-read the cache: the widget may have mutated it while we slept.
            if let data = Self.defaults.data(forKey: Self.cacheKey),
               let cached = try? JSONDecoder().decode(WatchPayload.self, from: data) {
                self?.payload = cached
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }
}

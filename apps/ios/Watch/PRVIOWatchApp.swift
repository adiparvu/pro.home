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
        guard let data = context["payload"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        Task { @MainActor in
            self.payload = decoded
            Self.defaults.set(data, forKey: Self.cacheKey)
            // Fresh state → repaint the watch-face complications too.
            WidgetCenter.shared.reloadAllTimelines()
        }
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
        queue(action: "completeTask", id: id)
    }

    func waterPlant(_ id: UUID) {
        mutate { payload in
            guard let i = payload.plants.firstIndex(where: { $0.id == id }) else { return }
            payload.plants[i].needsWatering = false
            let thirsty = payload.plants.filter(\.needsWatering)
            payload.snapshot.plantsNeedingWater = thirsty.count
            payload.snapshot.plantNames = Array(thirsty.prefix(3).map(\.name))
        }
        queue(action: "waterPlant", id: id)
    }

    func checkSupply(_ id: UUID) {
        mutate { payload in
            guard let i = payload.supplies.firstIndex(where: { $0.id == id }) else { return }
            payload.supplies[i].isCompleted = true
            payload.snapshot.pendingSupplyCount = payload.supplies.filter { !$0.isCompleted }.count
        }
        queue(action: "checkSupply", id: id)
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

    private func queue(action: String, id: UUID) {
        WKInterfaceDevice.current().play(.success)
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
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }
}

import Foundation
import WatchConnectivity
import WidgetKit

// MARK: - Watch sync (phone side)
//
// Pushes the widget snapshot + catalogs to the paired Apple Watch through
// `updateApplicationContext` — the fire-and-forget WatchConnectivity channel
// that always carries the LATEST state and survives the watch app being
// closed. Called from the same place the widget snapshot is written, so the
// watch can never drift from what the widgets show.
//
// The reverse channel makes the wrist ACT: the watch queues actions through
// `transferUserInfo` (guaranteed delivery, survives unreachability) and this
// service lands them in the exact pipeline the widget App Intents already
// use — pending queue + instant local catalog mutation + Supabase
// reconciliation on the app's next foreground beat.

final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    /// The payload that arrived before the session finished activating —
    /// pushed as soon as activation completes so a cold start isn't dropped.
    private var pending: WatchPayload?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ payload: WatchPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = payload
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // applicationContext keeps only the newest value — exactly right for
        // a state snapshot; no queue to back up, nothing to retry.
        try? session.updateApplicationContext(["payload": data])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated, let payload = pending else { return }
        pending = nil
        push(payload)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A watch switch deactivates the session; re-activate for the new watch.
        session.activate()
    }

    // MARK: Wrist actions

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let action = userInfo["action"] as? String else { return }
        // Dictated from the wrist: park the title; the app creates the real
        // task through TaskService on its next foreground beat.
        if action == "createTask", let title = userInfo["title"] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async {
                SharedDataStore.appendPendingWatchTask(title)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        guard let idString = userInfo["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.apply(action: action, id: id)
        }
    }

    private func apply(action: String, id: UUID) {
        switch action {
        case "completeTask":
            SharedDataStore.appendPendingCompletion(id)
            SharedDataStore.applyLocalTaskCompletion(id)
        case "waterPlant":
            SharedDataStore.appendPendingWatering(id)
            SharedDataStore.applyLocalWatering(id)
        case "checkSupply":
            SharedDataStore.appendPendingSupplyCheck(id)
            SharedDataStore.applyLocalSupplyCheck(id)
        default:
            return
        }
        // Every glass repaints from the mutated catalogs: home-screen widgets,
        // the watch (fresh context push), and — if the app is live — Supabase
        // itself through the same reconciliation the widget buttons use.
        WidgetCenter.shared.reloadAllTimelines()
        if let payload = SharedDataStore.currentWatchPayload() { push(payload) }
        NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
    }
}

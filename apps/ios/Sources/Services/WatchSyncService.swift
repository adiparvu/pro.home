import Foundation
import WatchConnectivity

// MARK: - Watch sync (phone side)
//
// Pushes the widget snapshot + catalogs to the paired Apple Watch through
// `updateApplicationContext` — the fire-and-forget WatchConnectivity channel
// that always carries the LATEST state and survives the watch app being
// closed. Called from the same place the widget snapshot is written, so the
// watch can never drift from what the widgets show.

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
}

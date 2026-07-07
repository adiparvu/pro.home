import SwiftUI
import WatchConnectivity
import WidgetKit

// MARK: - PRVIO for Apple Watch
//
// A glanceable companion: the phone pushes the same snapshot the widgets
// render (plus the task/plant catalogs) over WatchConnectivity, and the
// watch shows it in three vertical pages — Today, Tasks, Plants. Read-only
// by design in V1: the wrist answers "what needs me?", the phone acts.

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

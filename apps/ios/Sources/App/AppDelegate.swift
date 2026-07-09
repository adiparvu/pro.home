import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        ProactiveEngine.registerBackgroundTask()
        ProactiveEngine.scheduleBackgroundRefresh()
        // Apple's own crash/hang/battery telemetry, persisted on-device —
        // the measured ground any future self-healing must stand on.
        MetricsMonitor.shared.start()
        // Ask APNs for a token if the user already granted notifications.
        PushTokenService.registerIfAuthorized()
        // AsyncImage (chat photos, avatars, stickers) loads through
        // URLCache.shared; the system default is small enough that scrolling a
        // media-heavy chat re-fetches images. Give it room: 48 MB RAM / 256 MB disk.
        URLCache.shared = URLCache(memoryCapacity: 48 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
        return true
    }

    // MARK: - Remote notifications (APNs)

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushTokenService.logDebug("didRegister", detail: "len=\(deviceToken.count) prefix=\(hex.prefix(8))") }
        Task { await PushTokenService.handle(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        let ns = error as NSError
        Task { @MainActor in
            PushTokenService.logDebug("didFail", detail: "\(ns.domain)#\(ns.code): \(ns.localizedDescription)")
        }
#if DEBUG
        debugLog("[Push] APNs registration failed: \(error)")
#endif
    }

    // Scene-based apps (every SwiftUI app) deliver Home Screen quick actions
    // to the SCENE delegate, never to the app-delegate callback below — so we
    // must hand UIKit a scene-delegate class to receive them. SwiftUI keeps
    // managing the window; the delegate only taps the callbacks.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Legacy path (non-scene delivery) — kept as belt and suspenders.
        QuickActionSceneDelegate.deliver(shortcutItem.type)
        completionHandler(true)
    }
}

/// Owns every external entry point of the scene. Installing a custom scene
/// delegate also takes URL/activity delivery away from SwiftUI's internal
/// one, so this class must forward ALL of it — quick actions, prvio:// URLs
/// (widgets, Control Center controls) and Spotlight/Handoff activities —
/// through the same pending-key + notification funnel PRVIOApp consumes.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch: quick action / deep link / activity ride the connection
    /// options (the per-event callbacks are NOT called for them). Stash them —
    /// PRVIOApp consumes the pending keys when the scene becomes active, and
    /// the router buffers routes until MainTabView has mounted.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            UserDefaults.standard.set(item.type, forKey: "prvio.pendingQuickAction")
        }
        if let url = connectionOptions.urlContexts.first?.url {
            UserDefaults.standard.set(url.absoluteString, forKey: "prvio.pendingDeepLink")
        }
        if let activity = connectionOptions.userActivities.first {
            Self.stash(activity)
        }
    }

    /// Warm launch: the app is running (or suspended) and the user picked a
    /// quick action from the icon menu.
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Self.deliver(shortcutItem.type)
        completionHandler(true)
    }

    /// prvio:// deep links while running — widgets, Control Center controls,
    /// notification actions.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        NotificationCenter.default.post(name: .prvioOpenURL, object: url)
    }

    /// Spotlight results and Handoff while running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        NotificationCenter.default.post(name: .prvioUserActivity, object: userActivity)
    }

    static func deliver(_ type: String) {
        // Store for the cold-ish case (SwiftUI onReceive not registered yet)…
        UserDefaults.standard.set(type, forKey: "prvio.pendingQuickAction")
        // …and post immediately for the running-app case. PRVIOApp clears the
        // pending key when it handles either signal.
        NotificationCenter.default.post(name: .prvioQuickAction, object: type)
    }

    /// NSUserActivity isn't UserDefaults-friendly; keep just what routing needs.
    private static func stash(_ activity: NSUserActivity) {
        var payload: [String: String] = ["type": activity.activityType]
        if let id = activity.userInfo?["kCSSearchableItemActivityIdentifier"] as? String {
            payload["spotlightId"] = id
        }
        if let tab = activity.userInfo?["tab"] as? String {
            payload["tab"] = tab
        }
        UserDefaults.standard.set(payload, forKey: "prvio.pendingActivity")
    }
}

extension Notification.Name {
    static let prvioQuickAction    = Notification.Name("prvio.quickAction")
    static let prvioProcessPending = Notification.Name("prvio.processPending")
    static let prvioOpenURL        = Notification.Name("prvio.openURL")
    static let prvioUserActivity   = Notification.Name("prvio.userActivity")
}

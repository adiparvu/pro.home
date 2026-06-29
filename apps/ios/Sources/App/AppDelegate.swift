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
        // Ask APNs for a token if the user already granted notifications.
        PushTokenService.registerIfAuthorized()
        return true
    }

    // MARK: - Remote notifications (APNs)

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushTokenService.handle(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
#if DEBUG
        print("[Push] APNs registration failed: \(error)")
#endif
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Store for cold-launch case (SwiftUI onReceive may not be registered yet)
        UserDefaults.standard.set(shortcutItem.type, forKey: "prvio.pendingQuickAction")
        // Also post immediately for warm-launch (app already running)
        NotificationCenter.default.post(
            name: .prvioQuickAction,
            object: shortcutItem.type
        )
        completionHandler(true)
    }
}

extension Notification.Name {
    static let prvioQuickAction    = Notification.Name("prvio.quickAction")
    static let prvioProcessPending = Notification.Name("prvio.processPending")
}

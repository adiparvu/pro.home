import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
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

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
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

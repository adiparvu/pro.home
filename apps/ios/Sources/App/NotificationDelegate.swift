import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "TASK_COMPLETE":
            if let idStr = info["taskId"] as? String, let id = UUID(uuidString: idStr) {
                SharedDataStore.appendPendingCompletion(id)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }

        case "TASK_REMIND":
            if let idStr = info["taskId"] as? String {
                let content = (response.notification.request.content.mutableCopy() as? UNMutableNotificationContent)
                    ?? UNMutableNotificationContent()
                guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { break }
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = 9; comps.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: "task.remind.\(idStr)", content: content, trigger: trigger)
                try? await center.add(req)
            }

        case "PLANT_WATERED":
            if let idStr = info["plantId"] as? String, let id = UUID(uuidString: idStr) {
                SharedDataStore.appendPendingWatering(id)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }

        case "PLANT_REMIND":
            if let idStr = info["plantId"] as? String {
                let content = (response.notification.request.content.mutableCopy() as? UNMutableNotificationContent)
                    ?? UNMutableNotificationContent()
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 7200, repeats: false)
                let req = UNNotificationRequest(identifier: "plant.remind.\(idStr)", content: content, trigger: trigger)
                try? await center.add(req)
            }

        case "SUPPLY_ADD":
            NotificationCenter.default.post(name: .prvioQuickAction, object: "com.prvio.action.shopping")

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification body — route to correct screen
            if let taskIdStr = info["taskId"] as? String, UUID(uuidString: taskIdStr) != nil {
                NotificationCenter.default.post(name: .prvioQuickAction, object: "com.prvio.action.addtask")
            } else if info["plantId"] != nil {
                NotificationCenter.default.post(name: .prvioQuickAction, object: "com.prvio.action.plants")
            }

        default:
            break
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}

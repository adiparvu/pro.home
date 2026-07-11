import UIKit
import UserNotifications

/// Where a tapped chat push should land. Persisted (not just posted) so a tap
/// that COLD-LAUNCHES the app still routes once the conversation list exists.
enum ChatNotificationTarget {
    private static let key = "prvio.pending.chatTarget"

    /// "group" for the household chat, or a peer auth-user id for a DM.
    static func store(_ target: String) {
        UserDefaults.standard.set(target, forKey: key)
    }

    static func take() -> String? {
        guard let v = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return v
    }
}

/// The conversation currently on screen, so a foreground push for the chat you
/// are already reading is suppressed (WhatsApp behavior) — the message is
/// inserted live instead. Set by the chat views on appear/disappear; read by
/// `willPresent`. Keys are normalized (lowercased uuids): "group",
/// "dm:<peer_user_id>", "grp:<community_group_id>".
@MainActor
enum ActiveChat {
    private static var _current: String?
    static var current: String? { _current }
    static func set(_ key: String) { _current = key }
    /// Clear only if still ours — a push/pop can fire the old view's
    /// onDisappear AFTER the new view's onAppear, which would otherwise wipe
    /// the conversation just opened.
    static func clear(ifCurrent key: String) { if _current == key { _current = nil } }

    static func dmKey(_ peerUserId: UUID) -> String { "dm:\(peerUserId.uuidString.lowercased())" }
    static func groupKey(_ groupId: UUID?) -> String {
        groupId.map { "grp:\($0.uuidString.lowercased())" } ?? "group"
    }

    /// The normalized key a chat push refers to (nil = not a chat push).
    nonisolated static func key(forPayload chat: [String: Any]) -> String {
        let kind = chat["kind"] as? String
        if kind == "dm", let peer = chat["peer_user_id"] as? String {
            return "dm:\(peer.lowercased())"
        }
        if kind == "community", let gid = chat["group_id"] as? String {
            return "grp:\(gid.lowercased())"
        }
        return "group"
    }
}

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

        case "DOC_REMIND_WEEK":
            let content = (response.notification.request.content.mutableCopy() as? UNMutableNotificationContent)
                ?? UNMutableNotificationContent()
            if let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date()) {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: nextWeek)
                comps.hour = 9; comps.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: "doc.remind.\(UUID().uuidString)",
                                                content: content, trigger: trigger)
                try? await center.add(req)
            }

        case "PROACTIVE_OPEN":
            NotificationCenter.default.post(name: .prvioQuickAction, object: "com.prvio.action.home")

        case "MESSAGE_REPLY":
            // Typed, scribbled or dictated on the notification itself. The
            // app sends it on its next beat — into the conversation the push
            // came from (the `chat` payload carries it), never blindly into
            // the group chat.
            if let textResponse = response as? UNTextInputNotificationResponse {
                let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    var target = "group"
                    if let chat = info["chat"] as? [String: Any] {
                        let kind = chat["kind"] as? String
                        if kind == "dm",
                           let peer = chat["peer_user_id"] as? String,
                           UUID(uuidString: peer) != nil {
                            target = "dm:\(peer)"
                        } else if kind == "community" {
                            // Community sub-group: route via its group id. A
                            // community push without one never carries the
                            // MESSAGE category (send-chat-push guards it), so
                            // this branch can't misdeliver into the household
                            // chat — but guard anyway rather than fall through.
                            guard let gid = chat["group_id"] as? String,
                                  UUID(uuidString: gid) != nil else { break }
                            target = "grp:\(gid)"
                        }
                    }
                    SharedDataStore.appendPendingChatReply(text, target: target)
                    NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
                }
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification body — route to correct screen.
            // Chat pushes carry a `chat` dictionary (kind + identifiers) from
            // the send-chat-push function: a DM lands directly in that thread,
            // a community message opens its sub-group (via the existing
            // prvio://communities/<id> deep link, which survives cold launch
            // through the pendingDeepLink stash), anything else lands in the
            // household chat.
            if let chat = info["chat"] as? [String: Any] {
                let kind = chat["kind"] as? String
                if kind == "dm", let peer = chat["peer_user_id"] as? String, UUID(uuidString: peer) != nil {
                    ChatNotificationTarget.store(peer)
                    NotificationCenter.default.post(name: .prvioOpenChat, object: nil)
                } else if kind == "community", let gid = chat["group_id"] as? String,
                          UUID(uuidString: gid) != nil {
                    // Same belt-and-suspenders as the task branch below: the
                    // stash covers a cold launch, the post covers a warm one.
                    let link = "prvio://communities/\(gid)"
                    UserDefaults.standard.set(link, forKey: "prvio.pendingDeepLink")
                    if let url = URL(string: link) {
                        NotificationCenter.default.post(name: .prvioOpenURL, object: url)
                    }
                } else {
                    ChatNotificationTarget.store("group")
                    NotificationCenter.default.post(name: .prvioOpenChat, object: nil)
                }
            } else if let task = info["task"] as? [String: Any],
                      let id = task["id"] as? String, UUID(uuidString: id) != nil {
                // Task-assignment push (send-chat-push, migration 145) — land
                // on that task's detail page. Belt and suspenders: the stash
                // covers a cold launch (the post below fires before PRVIOApp
                // subscribes); PRVIOApp clears the stash when the live post
                // is handled so it can't replay on a later foreground.
                let link = "prvio://tasks/\(id)"
                UserDefaults.standard.set(link, forKey: "prvio.pendingDeepLink")
                if let url = URL(string: link) {
                    NotificationCenter.default.post(name: .prvioOpenURL, object: url)
                }
            } else if let taskIdStr = info["taskId"] as? String, UUID(uuidString: taskIdStr) != nil {
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
        // WhatsApp behavior: never banner a message for the conversation you're
        // already reading — it's inserted live instead. Only chat pushes carry
        // a `chat` dict; everything else always presents.
        let info = notification.request.content.userInfo
        if let chat = info["chat"] as? [String: Any] {
            let key = ActiveChat.key(forPayload: chat)
            if await ActiveChat.current == key { return [] }
        }
        return [.banner, .badge, .sound]
    }
}

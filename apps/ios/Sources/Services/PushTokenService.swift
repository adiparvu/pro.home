import Foundation
import UIKit
import UserNotifications

/// Registers the device for APNs and uploads the token to `device_tokens`
/// so the backend can deliver chat (and other) push notifications.
@MainActor
enum PushTokenService {

    private static let pendingKey = "prvio.pendingPushTokenHex"

    /// APNs environment is tied to the build's provisioning, mirrored here so
    /// the sender knows which APNs host to use.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Asks APNs for a token if the user has already granted (or provisionally
    /// granted) notification permission. Safe to call on every launch.
    static func registerIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Ensures the device is registered for push once the user is signed in.
    /// If permission was never asked (the common case — it used to live only
    /// behind a Settings toggle, so most people never granted it and no APNs
    /// token ever existed, which is why chat pushes never arrived), request it
    /// now that the user is inside the app and the value is obvious. Then
    /// register with APNs and flush any token captured before sign-in. Idempotent
    /// and safe to call on every foreground/login.
    static func ensureRegistered() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            case .authorized, .provisional:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            default:
                break // explicitly denied — respect it; the Settings page can re-prompt to system settings
            }
        }
        // A token that landed before login is still sitting in UserDefaults —
        // upload it now that there's a session to attach it to.
        Task { await uploadPendingIfNeeded() }
    }

    /// Called from AppDelegate once APNs hands us a token.
    static func handle(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        await upload(hex: hex)
    }

    /// Re-uploads a token that arrived before the user was signed in.
    static func uploadPendingIfNeeded() async {
        guard let hex = UserDefaults.standard.string(forKey: pendingKey), !hex.isEmpty else { return }
        await upload(hex: hex)
    }

    private static func upload(hex: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else {
            // Not signed in yet — stash it and upload after login.
            UserDefaults.standard.set(hex, forKey: pendingKey)
            return
        }
        struct Row: Encodable {
            let user_id: String
            let token: String
            let platform: String
            let environment: String
            let app_version: String?
        }
        let row = Row(
            user_id: uid.uuidString,
            token: hex,
            platform: "ios",
            environment: environment,
            app_version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
        do {
            try await supabase
                .from("device_tokens")
                .upsert(row, onConflict: "token")
                .execute()
            UserDefaults.standard.removeObject(forKey: pendingKey)
        } catch {
#if DEBUG
            debugLog("[Push] token upload failed: \(error)")
#endif
        }
    }
}

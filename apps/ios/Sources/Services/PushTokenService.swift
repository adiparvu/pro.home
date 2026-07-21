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

    /// The device's current APNs token, kept so account switches can bind the
    /// incoming account and sign-out can unbind exactly the leaving one.
    private static let currentTokenKey = "push.token.current"

    /// Called from AppDelegate once APNs hands us a token.
    static func handle(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: currentTokenKey)
        await upload(hex: hex)
    }

    /// Binds the device token to the CURRENT session's account. Called after an
    /// account switch: bindings are per (token, user), so every account signed
    /// into this phone keeps receiving its own pushes — like any multi-account
    /// messenger. No-op until APNs has issued a token.
    static func bindCurrentAccount() async {
        guard let hex = UserDefaults.standard.string(forKey: currentTokenKey), !hex.isEmpty else { return }
        await upload(hex: hex)
    }

    /// Removes ONLY the signed-out account's binding for this device. Must run
    /// while that account's session is still valid (RLS lets an account delete
    /// only its own rows). Other accounts' bindings survive.
    static func unbindCurrentAccount() async {
        guard let hex = UserDefaults.standard.string(forKey: currentTokenKey), !hex.isEmpty,
              let uid = supabase.auth.currentSession?.user.id else { return }
        _ = try? await supabase.from("device_tokens")
            .delete()
            .eq("token", value: hex)
            .eq("user_id", value: uid.uuidString)
            .execute()
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
            // Conflict target is (token, user_id): a phone signed into several
            // accounts holds one binding per account, so switching accounts
            // ADDS a binding instead of stealing the token from the previous
            // account — all signed-in accounts keep receiving their pushes.
            try await supabase
                .from("device_tokens")
                .upsert(row, onConflict: "token,user_id")
                .execute()
            UserDefaults.standard.removeObject(forKey: pendingKey)
        } catch {
#if DEBUG
            debugLog("[Push] token upload failed: \(error)")
#endif
        }
    }
}

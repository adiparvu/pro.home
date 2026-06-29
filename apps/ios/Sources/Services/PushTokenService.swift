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
            print("[Push] token upload failed: \(error)")
#endif
        }
    }
}

import SwiftUI
import LocalAuthentication

/// App-level security lock. Enforces biometric/passcode authentication when
/// the user has enabled it in Security settings, applies an auto-lock timeout
/// based on how long the app was backgrounded, supports a stricter "lockdown"
/// mode (lock on every return to foreground), and shows a privacy cover in the
/// app switcher so sensitive data isn't visible in snapshots.
@MainActor
final class AppLockManager: ObservableObject {
    @Published var isLocked = false
    @Published var privacyCover = false
    @Published var authFailed = false

    private var backgroundedAt: Date?

    // Live reads of the user's Security preferences.
    private var lockEnabled: Bool { UserDefaults.standard.bool(forKey: "prvio.biometrics") }
    private var lockdown: Bool    { UserDefaults.standard.bool(forKey: "prvio.lockMode") }
    private var autoLockMinutes: Int {
        UserDefaults.standard.object(forKey: "prvio.autoLockMinutes") as? Int ?? 5
    }

    /// Cold launch — lock immediately if protection is on.
    func appDidLaunch() {
        if lockEnabled { isLocked = true }
    }

    func willResignActive() {
        if lockEnabled { privacyCover = true }
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive() {
        privacyCover = false
        guard lockEnabled else { isLocked = false; backgroundedAt = nil; return }
        if isLocked { return }

        if lockdown {
            // Lockdown: always re-authenticate when returning to foreground.
            isLocked = true
        } else if autoLockMinutes > 0, let bg = backgroundedAt,
                  Date().timeIntervalSince(bg) >= Double(autoLockMinutes) * 60 {
            isLocked = true
        }
        backgroundedAt = nil
    }

    func authenticate() async {
        let context = LAContext()
        context.localizedFallbackTitle = "Folosește codul de acces"

        // Prefer biometrics, but allow the device passcode as a fallback so the
        // user is never locked out (HIG-compliant).
        var policyError: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthentication

        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: "Deblochează PRVIO")
            if ok {
                isLocked = false
                authFailed = false
                backgroundedAt = nil
            } else {
                authFailed = true
            }
        } catch {
            authFailed = true
        }
    }
}

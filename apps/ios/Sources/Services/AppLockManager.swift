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
    private var lastUnlockedAt: Date?
    private var isAuthenticating = false

    // Persisted across calls within one lock session so iOS accumulates
    // biometric failures and automatically offers passcode after 5 attempts.
    private var authContext: LAContext?

    private var lockEnabled: Bool { UserDefaults.standard.bool(forKey: "prvio.biometrics") }
    private var lockdown: Bool    { UserDefaults.standard.bool(forKey: "prvio.lockMode") }
    private var autoLockMinutes: Int {
        UserDefaults.standard.object(forKey: "prvio.autoLockMinutes") as? Int ?? 5
    }
    // Only used when autoLockMinutes == -2 (sub-minute seconds mode)
    private var autoLockSeconds: Int {
        UserDefaults.standard.object(forKey: "prvio.autoLockSeconds") as? Int ?? 30
    }

    /// Cold launch — lock immediately if protection is on and auto-prompt.
    func appDidLaunch() {
        guard lockEnabled else { return }
        engageLock()
    }

    func willResignActive() {
        if lockEnabled { privacyCover = true }
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive() {
        privacyCover = false
        guard lockEnabled else { isLocked = false; backgroundedAt = nil; return }

        // Don't interfere while a biometric/passcode prompt is running.
        if isAuthenticating { return }

        // Grace period: skip re-lock checks for 2 seconds after a successful
        // unlock to absorb the .inactive→.active cycle that iOS fires when the
        // authentication dialog dismisses.
        if let lu = lastUnlockedAt, Date().timeIntervalSince(lu) < 2.0 {
            backgroundedAt = nil
            return
        }

        // Already locked — lock screen is visible, nothing to do.
        if isLocked { return }

        let shouldLock: Bool
        if lockdown {
            shouldLock = true
        } else if autoLockMinutes == -1 {
            // "Immediately" — lock every time the app backgrounds
            shouldLock = true
        } else if autoLockMinutes == -2,
                  let bg = backgroundedAt,
                  Date().timeIntervalSince(bg) >= Double(autoLockSeconds) {
            // Sub-minute seconds mode
            shouldLock = true
        } else if autoLockMinutes > 0,
                  let bg = backgroundedAt,
                  Date().timeIntervalSince(bg) >= Double(autoLockMinutes) * 60 {
            shouldLock = true
        } else {
            shouldLock = false
        }
        backgroundedAt = nil

        if shouldLock { engageLock() }
    }

    /// Prompts Face ID / Touch ID / passcode. Safe to call concurrently — only
    /// one evaluation runs at a time.
    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true

        // Reuse context within the same lock session so failure count persists.
        if authContext == nil {
            let ctx = LAContext()
            ctx.localizedFallbackTitle = "Use passcode"
            authContext = ctx
        }

        do {
            guard let ctx = authContext else { isAuthenticating = false; return }
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock PRVIO"
            )
            if ok {
                // Set lastUnlockedAt BEFORE clearing isLocked so that the
                // .active scene phase fired by dialog-dismiss is absorbed by
                // the grace period check in didBecomeActive().
                lastUnlockedAt = Date()
                isLocked = false
                authFailed = false
                backgroundedAt = nil
                authContext = nil
            } else {
                authFailed = true
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                // User or system dismissed — not a real failure; don't show error.
                break
            default:
                authFailed = true
            }
        } catch {
            authFailed = true
        }

        isAuthenticating = false
    }

    // MARK: - Private

    private func engageLock() {
        // Reset per-session state.
        authContext = nil
        authFailed = false
        isLocked = true
        // Auto-prompt immediately — Task is detached from any view so it
        // won't be cancelled by view removal.
        Task { await authenticate() }
    }
}

import SwiftUI

/// Full-screen lock shown when the app is protected and locked. Auto-prompts
/// for Face ID / Touch ID / passcode (triggered by AppLockManager) and offers
/// a manual retry button.
struct LockScreenView: View {
    @ObservedObject var manager: AppLockManager

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                PRVIOLogoView(size: 84)
                VStack(spacing: 6) {
                    Text("PRVIO is locked")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(manager.authFailed
                         ? "Authentication failed. Try again."
                         : "Authenticate to continue")
                        .font(.system(size: 14))
                        .foregroundStyle(manager.authFailed ? .red : Color.primary.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task { await manager.authenticate() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text("Unlock")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
        // No .task auto-trigger here — AppLockManager fires authenticate()
        // via engageLock() so the prompt is tied to the lock session, not
        // view lifecycle. This prevents a new LAContext (and reset failure
        // counter) from being created each time SwiftUI rebuilds the view.
    }
}

/// Branded blur shown in the app switcher so sensitive content isn't captured
/// in snapshots while the app is backgrounded.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                PRVIOLogoView(size: 72)
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
        }
    }
}

import SwiftUI

/// Full-screen lock shown when the app is protected and locked. Auto-prompts
/// for Face ID / Touch ID / passcode (triggered by AppLockManager) and offers
/// a manual retry button.
struct LockScreenView: View {
    var manager: AppLockManager

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                PRVIOLogoView(size: 84)
                VStack(spacing: 6) {
                    Text("PRVIO is locked")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    if manager.authFailed {
                        Text("Authentication failed. Try again.")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Authenticate to continue")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
                Button {
                    Task { await manager.authenticate() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text("Unlock")
                    }
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous), interactive: true)
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
                    .font(AppFont.title3)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
        }
    }
}

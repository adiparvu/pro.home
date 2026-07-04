import SwiftUI

/// Wraps a sensitive destination so its content stays hidden behind a Face ID /
/// passcode challenge until the user authenticates. Once unlocked the content
/// shows for the rest of the foreground session; it re-locks when the app is
/// backgrounded (handled by `SectionLockManager`).
///
/// Use via the `.sectionLock(_:)` modifier on any pushed destination:
///
///     DocumentsView().sectionLock(.documents)
struct SectionLockGate<Content: View>: View {
    let section: SectionLockManager.Section
    @ViewBuilder var content: () -> Content

    @State private var manager = SectionLockManager.shared
    @State private var authenticating = false
    @State private var failed = false

    var body: some View {
        Group {
            if manager.needsAuth(section) {
                lockedPlaceholder
                    .task { await attempt() }   // auto-prompt on first appear
            } else {
                content()
            }
        }
    }

    private var lockedPlaceholder: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: AppSpacing.xl) {
                ZStack {
                    Circle()
                        .fill(section.color.opacity(0.16))
                        .frame(width: 108, height: 108)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(section.color)
                }

                VStack(spacing: AppSpacing.xs) {
                    Text(section.titleKey)
                        .font(AppFont.title2)
                        .foregroundStyle(.primary)
                    Text(failed ? "Authentication failed. Try again."
                                : "This section is locked. Authenticate to continue.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(failed ? Color.brandDanger : Color.secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Button {
                    Task { await attempt() }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "faceid")
                        Text("Unlock")
                    }
                    .font(AppFont.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(section.color, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(authenticating)
                .padding(.horizontal, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func attempt() async {
        guard !authenticating else { return }
        authenticating = true
        let ok = await manager.unlock(section)
        failed = !ok
        authenticating = false
    }
}

extension View {
    /// Requires Face ID / passcode before this view's content is shown, when the
    /// user has enabled a lock for `section` in Security settings.
    func sectionLock(_ section: SectionLockManager.Section) -> some View {
        SectionLockGate(section: section) { self }
    }
}

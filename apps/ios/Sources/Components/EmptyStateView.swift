import SwiftUI

// MARK: - The app's one empty-state voice
//
// Every list, gallery and feed speaks the same way when it has nothing to
// show: a soft glass disc with the feature's symbol, a calm title, one
// optional explanatory line, and (when there's an obvious next step) a
// single capsule action. Empty is a starting point, not an error — the
// tone stays warm and the layout identical everywhere, so the app feels
// written by one hand.

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var actionLabel: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    /// Accent of the disc + action; defaults to the app accent.
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(tint.opacity(0.08))
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(tint.opacity(0.85))
            }
            .frame(width: 76, height: 76)
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.25), tint.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
            )

            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionLabel, let action {
                Button {
                    HapticFeedback.impact(.light)
                    action()
                } label: {
                    Text(actionLabel)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.sm)
                        .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, AppSpacing.xl)
    }
}

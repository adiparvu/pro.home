import SwiftUI

// MARK: - The app's one empty-state voice
//
// Every list, gallery and feed speaks the same way when it has nothing to
// show: the feature's symbol on a clear Liquid Glass disc, a calm title,
// one optional explanatory line, and (when there's an obvious next step) a
// single glass capsule action. Monochrome and adaptive — the glyph renders
// hierarchically in the label color, never in an accent tint, so the state
// reads native in both light and dark. Empty is a starting point, not an
// error — the tone stays warm and the layout identical everywhere.

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var actionLabel: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFont.scaled(30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .glassCircle()

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
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.sm)
                        .glassCapsule()
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

import SwiftUI

// MARK: - Multi-select mode (iMessage "Select" from the long-press menu)
//
// Shared between the group chat (`ChatView`) and the 1-on-1 thread
// (`DirectMessageView`). Entering the mode swaps the compose bar for a
// selection toolbar (delete + forward), prefixes every message row with a
// leading checkbox, and toggles a message on tap — exactly like Messages.app.

/// The leading circular checkbox iMessage draws on every row while selecting.
/// Empty = hairline ring; selected = filled accent circle with a white tick.
struct ChatSelectCheck: View {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5)
            if isSelected {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(12, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isSelected)
        .accessibilityHidden(true)
    }
}

/// The bottom bar shown in place of the composer while selecting — trash on
/// the leading edge, forward on the trailing, a live count between them.
/// Both actions disable at zero selection so they are never dead controls.
struct ChatSelectionToolbar: View {
    let count: Int
    let onDelete: () -> Void
    let onForward: () -> Void

    private var title: String {
        count == 0
            ? String(localized: "Select messages")
            : String(format: String(localized: "%lld selected"), count)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(AppFont.title3)
                    .foregroundStyle(count == 0 ? Color.secondaryTextColor : Color.brandDanger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .accessibilityLabel(Text("Delete selected"))

            Spacer(minLength: 0)
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Spacer(minLength: 0)

            Button(action: onForward) {
                Image(systemName: "square.and.arrow.up")
                    .font(AppFont.title3)
                    .foregroundStyle(count == 0 ? Color.secondaryTextColor : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .accessibilityLabel(Text("Forward selected"))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(.bar)
    }
}

extension View {
    /// Wraps a message bubble for selection mode: when `active`, prefixes a
    /// leading checkbox and makes the whole row a single tap target that
    /// toggles the message (the bubble's own gestures are suspended so a tap
    /// never fires reply/react/long-press). When inactive it returns the
    /// bubble untouched — zero layout cost on the hot path.
    @ViewBuilder
    func chatSelectable(active: Bool, selected: Bool,
                        onToggle: @escaping () -> Void) -> some View {
        if active {
            HStack(spacing: AppSpacing.sm) {
                ChatSelectCheck(isSelected: selected)
                self.allowsHitTesting(false)
            }
            .padding(.leading, AppSpacing.md)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            self
        }
    }
}

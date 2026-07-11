import SwiftUI

/// A reusable floating speed-dial button.
/// - When given multiple actions it expands into a menu.
/// - When given a single action, tapping triggers that action directly.
/// - When given no actions it renders nothing (hidden).
struct FloatingSpeedDial: View {
    let actions: [DashboardQuickAction]
    let onSelect: (DashboardQuickAction) -> Void
    var bottomPadding: CGFloat = 16
    var trailingPadding: CGFloat = 20

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMenu: Bool { actions.count > 1 }

    /// The dial's spring, flattened to a plain fade when the user asks for
    /// reduced motion.
    private var dialAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.72)
    }

    var body: some View {
        if actions.isEmpty {
            EmptyView()
        } else {
            ZStack(alignment: .bottomTrailing) {
                if expanded && isMenu {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { collapse() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                // On iOS 26 the dial's glass shapes (FAB, action pills and
                // circles) render as ONE Liquid Glass group: a single blended
                // pass instead of a separate material layer per element, and
                // the shapes can morph into each other while expanding.
                Group {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer { dialStack }
                    } else {
                        dialStack
                    }
                }
                .padding(.trailing, trailingPadding)
                .padding(.bottom, bottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private var dialStack: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if expanded && isMenu {
                ForEach(actions) { action in
                    actionRow(action)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            mainButton
        }
    }

    // Glass and shadow are on the Button itself (not inside the label) so
    // the glass layer never intercepts touches before the button action fires.
    private var mainButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            if isMenu {
                withAnimation(dialAnimation) { expanded.toggle() }
            } else if let only = actions.first {
                onSelect(only)
            }
        } label: {
            // The app's monogram is the FAB's face (user's brand mark);
            // expanding swaps it for the close affordance.
            Group {
                if isMenu && !expanded {
                    Image("BrandMark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                } else if isMenu {
                    Image(systemName: "xmark")
                        .font(AppFont.scaled(20, weight: .bold))
                } else {
                    Image(systemName: actions.first?.icon ?? "plus")
                        .font(AppFont.scaled(20, weight: .bold))
                }
            }
            .foregroundStyle(.primary)
            .animation(dialAnimation, value: expanded)
            .frame(width: 58, height: 58)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .shadow(color: Color.primary.opacity(0.22), radius: 20, y: 6)
        .accessibilityLabel(isMenu ? String(localized: "Quick actions") : (actions.first?.title ?? ""))
        .accessibilityHint(isMenu ? String(localized: "Opens the quick actions menu") : "")
        .accessibilityValue(isMenu && expanded ? String(localized: "Expanded") : "")
    }

    private func actionRow(_ action: DashboardQuickAction) -> some View {
        Button {
            collapse()
            onSelect(action)
        } label: {
            HStack(spacing: 10) {
                Text(action.title)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 7)
                    .glassCapsule()
                    .allowsHitTesting(false)
                    .shadow(color: Color.primary.opacity(0.08), radius: 6, y: 2)

                // Native pattern: Liquid Glass circle with a primary glyph —
                // no tinted discs (the colour survives only in the page that
                // configures the action, not on the button).
                Image(systemName: action.icon)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassCircle()
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func collapse() {
        withAnimation(dialAnimation) { expanded = false }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Overlays a customizable floating speed-dial driven by the per-page
    /// settings for `host`. All actions are routed through `AppRouter`.
    func floatingSpeedDial(_ host: FloatingButtonHost, bottomPadding: CGFloat = 16) -> some View {
        modifier(FloatingSpeedDialModifier(host: host, bottomPadding: bottomPadding))
    }
}

private struct FloatingSpeedDialModifier: ViewModifier {
    let host: FloatingButtonHost
    var bottomPadding: CGFloat
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            FloatingSpeedDial(
                actions: appSettings.fabVisible(host) ? appSettings.fabActions(host) : [],
                onSelect: { router.perform($0) },
                bottomPadding: bottomPadding
            )
        }
    }
}

import SwiftUI

/// A reusable floating speed-dial button.
/// - When given multiple actions it expands into a menu.
/// - When given a single action, tapping triggers that action directly.
/// - When given no actions it renders nothing (hidden).
struct FloatingSpeedDial: View {
    let actions: [DashboardQuickAction]
    let onSelect: (DashboardQuickAction) -> Void
    var bottomPadding: CGFloat = 100
    var trailingPadding: CGFloat = 20

    @State private var expanded = false

    private var isMenu: Bool { actions.count > 1 }

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
                }

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
                .padding(.trailing, trailingPadding)
                .padding(.bottom, bottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    // Glass and shadow are on the Button itself (not inside the label) so
    // the glass layer never intercepts touches before the button action fires.
    private var mainButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            if isMenu {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { expanded.toggle() }
            } else if let only = actions.first {
                onSelect(only)
            }
        } label: {
            Image(systemName: isMenu ? "plus" : (actions.first?.icon ?? "plus"))
                .font(.system(size: isMenu ? 22 : 20, weight: .bold))
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(expanded && isMenu ? 45 : 0))
                .animation(.spring(response: 0.38, dampingFraction: 0.72), value: expanded)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .shadow(color: Color.primary.opacity(0.22), radius: 20, y: 6)
    }

    private func actionRow(_ action: DashboardQuickAction) -> some View {
        Button {
            collapse()
            onSelect(action)
        } label: {
            HStack(spacing: 10) {
                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCapsule()
                    .allowsHitTesting(false)
                    .shadow(color: Color.primary.opacity(0.08), radius: 6, y: 2)

                Image(systemName: action.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .background(alignment: .trailing) {
            Circle()
                .frame(width: 44, height: 44)
                .glassCircle()
                .shadow(color: Color.primary.opacity(0.1), radius: 8, y: 2)
                .allowsHitTesting(false)
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { expanded = false }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Overlays a customizable floating speed-dial driven by the per-page
    /// settings for `host`. All actions are routed through `AppRouter`.
    func floatingSpeedDial(_ host: FloatingButtonHost, bottomPadding: CGFloat = 100) -> some View {
        modifier(FloatingSpeedDialModifier(host: host, bottomPadding: bottomPadding))
    }
}

private struct FloatingSpeedDialModifier: ViewModifier {
    let host: FloatingButtonHost
    var bottomPadding: CGFloat
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var router: AppRouter

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

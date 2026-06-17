import SwiftUI

final class TabBarVisibility: ObservableObject {
    @Published var isHidden = false
    @Published var scrollOffset: CGFloat = 0

    // 0 = fully shown, 1 = fully hidden — drives continuous zoom-out
    var hideProgress: CGFloat {
        if isHidden { return 1.0 }
        let start: CGFloat = -28
        let end: CGFloat = -110
        guard scrollOffset < start else { return 0 }
        return min((scrollOffset - start) / (end - start), 1.0)
    }

    var scrolledDown: Bool { hideProgress > 0.55 }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum AppTab: String, CaseIterable {
    case home, digitalTwin, tasks, chat, settings

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .digitalTwin: return "square.stack.3d.up.fill"
        case .tasks:       return "checklist"
        case .chat:        return "sparkles"
        case .settings:    return "person.crop.circle.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home:        return "house"
        case .digitalTwin: return "square.stack.3d.up"
        case .tasks:       return "checklist"
        case .chat:        return "sparkles"
        case .settings:    return "person.crop.circle"
        }
    }

    var label: String {
        switch self {
        case .home:        return "Home"
        case .digitalTwin: return "Property"
        case .tasks:       return "Tasks"
        case .chat:        return "AI"
        case .settings:    return "You"
        }
    }
}

// MARK: - Scroll-direction tracker (Instagram-style tab hide)

struct TabScrollDetector: ViewModifier {
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
                    tabBarVis.scrollOffset = offset
                }
            }
    }
}

extension View {
    func trackTabScroll() -> some View { modifier(TabScrollDetector()) }
}

// MARK: - Animated tab bar
// iOS 26+: floating Liquid Glass pill (native glassEffect)
// iOS 17–25: full-width ultraThinMaterial bar

struct AnimatedTabBar: View {
    @Binding var selected: AppTab
    @Binding var bounceTab: AppTab?
    let overdueCount: Int
    let bottomPad: CGFloat
    let hideProgress: CGFloat

    @EnvironmentObject private var profileService: ProfileService

    var body: some View {
        if #available(iOS 26, *) {
            floatingPill
        } else {
            legacyBar
        }
    }

    // MARK: iOS 26+ — floating Liquid Glass pill

    @available(iOS 26, *)
    private var floatingPill: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    HapticFeedback.selection()
                    bounceTab = tab
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { selected = tab }
                } label: {
                    tabItemPill(tab)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, bottomPad + 4)
        .scaleEffect(1.0 - hideProgress * 0.08, anchor: .bottom)
        .opacity(max(0, 1.0 - hideProgress * 2.2))
        .offset(y: hideProgress * 90)
        .allowsHitTesting(hideProgress < 0.45)
    }

    // MARK: iOS 17–25 — full-width material bar

    private var legacyBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    HapticFeedback.selection()
                    bounceTab = tab
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { selected = tab }
                } label: {
                    tabItem(tab)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, bottomPad)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .scaleEffect(1.0 - hideProgress * 0.08, anchor: .bottom)
        .opacity(max(0, 1.0 - hideProgress * 2.2))
        .offset(y: hideProgress * 90)
        .allowsHitTesting(hideProgress < 0.45)
    }

    // MARK: - Tab item (pill variant — iOS 26+)

    @ViewBuilder
    private func tabItemPill(_ tab: AppTab) -> some View {
        let isSelected = tab == selected
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                iconView(tab, isSelected: isSelected)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: bounceTab == tab)
                    .scaleEffect(isSelected ? 1.10 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)

                Circle()
                    .fill(Color.primary)
                    .frame(width: isSelected ? 4 : 0, height: isSelected ? 4 : 0)
                    .opacity(isSelected ? 0.6 : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
            }

            if tab == .tasks && overdueCount > 0 {
                Text(overdueCount < 10 ? "\(overdueCount)" : "9+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .offset(x: 8, y: -1)
            }
        }
    }

    // MARK: - Tab item (legacy full-width variant — iOS 17–25)

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = tab == selected
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                iconView(tab, isSelected: isSelected)
                    .font(.system(size: 23, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.33))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: bounceTab == tab)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)

                Circle()
                    .fill(Color.primary)
                    .frame(width: isSelected ? 4 : 0, height: isSelected ? 4 : 0)
                    .opacity(isSelected ? 0.7 : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
            }

            if tab == .tasks && overdueCount > 0 {
                Text(overdueCount < 10 ? "\(overdueCount)" : "9+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .offset(x: 8, y: -1)
            }
        }
    }

    // MARK: - Icon (shared)

    @ViewBuilder
    private func iconView(_ tab: AppTab, isSelected: Bool) -> some View {
        if tab == .settings, let urlStr = profileService.profile?.avatarUrl,
           let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(
                            isSelected ? Color.primary : Color.primary.opacity(0.25),
                            lineWidth: isSelected ? 2.5 : 1.5
                        ))
                } else {
                    Image(systemName: isSelected ? tab.icon : tab.inactiveIcon)
                }
            }
            .frame(width: 26, height: 26)
        } else {
            Image(systemName: isSelected ? tab.icon : tab.inactiveIcon)
        }
    }
}

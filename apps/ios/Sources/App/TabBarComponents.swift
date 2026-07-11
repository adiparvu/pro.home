import SwiftUI
import Observation

@Observable
final class TabBarVisibility {
    var isHidden = false
    var scrollOffset: CGFloat = 0

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
        case .home:        return String(localized: "Home")
        case .digitalTwin: return String(localized: "Property")
        case .tasks:       return String(localized: "Tasks")
        case .chat:        return String(localized: "AI")
        case .settings:    return String(localized: "You")
        }
    }

    /// Tabs a property role may see. Exhaustive over `PropertyRole` so a new
    /// role can't slip through an open `default:`; unknown role strings have
    /// already collapsed to `.guest` in `PropertyRole.resolve`. nil = role
    /// still loading → everything, so the owner's UI never flashes trimmed
    /// at startup. This is navigation convenience — real per-module data
    /// security is server-side RLS. Chat + settings (your own profile) stay
    /// available to everyone.
    static func visible(for role: String?) -> Set<AppTab> {
        guard let role = PropertyRole.resolve(role) else { return Set(AppTab.allCases) }
        switch role {
        case .guest:
            return [.chat, .settings]
        case .serviceProvider:
            return [.tasks, .chat, .settings]
        case .tenant, .familyChild, .familyTeen:
            return [.home, .tasks, .chat, .settings]
        case .owner, .partner, .familyAdult, .familyElderly:
            return Set(AppTab.allCases)
        }
    }
}

// MARK: - Scroll-direction tracker (Instagram-style tab hide)

struct TabScrollDetector: ViewModifier {
    @Environment(TabBarVisibility.self) private var tabBarVis

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

import SwiftUI
import Observation

/// The one remaining job of this class: the FULL tab-bar hide inside an open
/// conversation (ChatView). Minimize-on-scroll everywhere else is the
/// system's — `.tabBarMinimizeBehavior(.onScrollDown)` on the TabView — so
/// the old scroll-offset pipeline (a GeometryReader preference invalidating
/// a dozen pages on every scroll frame) is gone (WWDC26 gap map).
@Observable
final class TabBarVisibility {
    var isHidden = false
}

enum AppTab: String, CaseIterable {
    case home, digitalTwin, tasks, chat, settings

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .digitalTwin: return "square.split.2x2.fill"
        case .tasks:       return "checklist"
        case .chat:        return "bubble.left.and.bubble.right.fill"
        case .settings:    return "person.crop.circle.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home:        return "house"
        case .digitalTwin: return "square.split.2x2"
        case .tasks:       return "checklist"
        case .chat:        return "bubble.left.and.bubble.right"
        case .settings:    return "person.crop.circle"
        }
    }

    /// The tab's single-word name — VOICEOVER ONLY (user-decreed): the bar
    /// shows icons without visible labels; MainTabView attaches this as the
    /// accessibility label so the tabs still speak their names.
    var label: String {
        switch self {
        case .home:        return String(localized: "Home")
        case .digitalTwin: return String(localized: "Spaces")
        case .tasks:       return String(localized: "Tasks")
        case .chat:        return String(localized: "Chat")
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

// MARK: - Tab bar visibility policy (user-decreed: always visible)

/// The bar NEVER minimizes or hides on scroll (user verdict over both the
/// system's minimize-on-scroll and the old Instagram-style zoom-out, which
/// was deleted in 1082 as the imitation anti-pattern). Explicit `.never`
/// rather than relying on `.automatic`, so no OS default can ever shrink
/// it. The one full hide — an open conversation — stays on
/// `TabBarVisibility.isHidden`.
struct SystemTabBarMinimize: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

import SwiftUI

// MARK: - Canonical Live Activity kind
//
// The single source of truth for every Live Activity's identity: symbol,
// tint, deep link and preference keys. Compiled into BOTH the app and the
// widgets target — the extension renders the activities, so the identity
// must live where both sides can see it (the raw strings scattered through
// the island views and the settings-only enum used to drift apart; the
// work session, notably, could never be customized because the settings
// enum didn't know it existed).

enum LiveActivityKind: String, CaseIterable, Identifiable {
    case shopping, delivery, maintenance, plantCare, workSession, emergency

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .shopping:    return "Shopping list"
        case .delivery:    return "Deliveries"
        case .maintenance: return "Maintenance tasks"
        case .plantCare:   return "Plant care"
        case .workSession: return "Work session"
        case .emergency:   return "Emergency"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .shopping:    return "Track items as you check them off"
        case .delivery:    return "Follow a package until it arrives"
        case .maintenance: return "Watch progress on an active task"
        case .plantCare:   return "Watering progress for your plants"
        case .workSession: return "Time a task from start to done"
        case .emergency:   return "Keep the emergency page one tap away"
        }
    }

    var icon: String {
        switch self {
        case .shopping:    return "cart.fill"
        case .delivery:    return "shippingbox.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .plantCare:   return "leaf.fill"
        case .workSession: return "timer"
        case .emergency:   return "light.beacon.max.fill"
        }
    }

    /// Brand tint — one hue per activity family so the island reads at a
    /// glance (the old views hand-picked `.blue`/`.orange`/`.teal` and three
    /// activities ended up the same blue). Red belongs to emergency alone.
    var color: Color {
        switch self {
        case .shopping:    return .brandSkyBlue
        case .delivery:    return .brandPrimaryBlue
        case .maintenance: return .brandWarning
        case .plantCare:   return .brandSuccess
        case .workSession: return .brandTeal
        case .emergency:   return .brandDanger
        }
    }

    /// Where tapping the activity lands in the app.
    var deepLink: URL? {
        switch self {
        case .shopping:    return URL(string: "prvio://shopping")
        case .delivery:    return URL(string: "prvio://deliveries")
        case .maintenance: return URL(string: "prvio://tasks")
        case .plantCare:   return URL(string: "prvio://plants")
        case .workSession: return URL(string: "prvio://tasks")
        case .emergency:   return URL(string: "prvio://emergency")
        }
    }

    /// Whether the app may start this activity by itself. The work session
    /// and the emergency pin are always explicit human actions, so they have
    /// no auto-start toggle — only appearance customization.
    var supportsAutoStart: Bool {
        switch self {
        case .workSession, .emergency: return false
        default:                       return true
        }
    }

    var storageKey: String {
        switch self {
        case .shopping:    return LiveActivityPrefs.autoShoppingKey
        case .delivery:    return LiveActivityPrefs.autoDeliveryKey
        case .maintenance: return LiveActivityPrefs.autoMaintKey
        case .plantCare:   return LiveActivityPrefs.autoPlantKey
        // Unused (no auto-start), but @AppStorage still needs a stable key.
        case .workSession: return "prvio.la.auto.workSession"
        case .emergency:   return "prvio.la.auto.emergency"
        }
    }

    var defaultAuto: Bool {
        switch self {
        case .shopping, .delivery: return true
        default:                   return false
        }
    }
}

extension LiveActivityPrefs {
    /// Whether the app may start this kind on its own right now. Kinds
    /// without an auto-start toggle are always allowed — their starts are
    /// explicit user actions gated only by the master switch.
    static func autoStart(for kind: LiveActivityKind) -> Bool {
        guard kind.supportsAutoStart else { return true }
        return bool(kind.storageKey, default: kind.defaultAuto)
    }
}

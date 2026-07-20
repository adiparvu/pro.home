import Foundation

// MARK: - The one place a role string becomes power
//
// Property-role gating used to be string switches scattered across the
// tab bar, Settings and the member admin — each with its own `default:`
// that silently granted everything to any string it didn't recognize.
// `PropertyRole` replaces that: raw strings resolve through one door,
// unknown values collapse to `.guest` (fail CLOSED), and call sites
// switch exhaustively so adding a role forces every gate to decide.
//
// nil stays distinct on purpose: it means "membership not resolved yet",
// and the UI deliberately fails open during that window so the owner's
// screen never flashes empty at startup. `PropertyService.loadMyRole`
// clamps to "guest" the moment the answer is definitive.

enum PropertyRole: String, CaseIterable {
    case owner
    case partner
    case familyAdult    = "family_adult"
    case familyTeen     = "family_teen"
    case familyChild    = "family_child"
    case familyElderly  = "family_elderly"
    case tenant
    case guest
    case serviceProvider = "service_provider"

    /// nil in → nil out ("still loading"); anything unrecognized → guest.
    static func resolve(_ raw: String?) -> PropertyRole? {
        guard let raw else { return nil }
        return PropertyRole(rawValue: raw) ?? .guest
    }

    // MARK: Shared capabilities (one truth, however many gates)

    /// Managing the household roster and member accounts is landlord-class.
    var canManageMembers: Bool {
        switch self {
        case .owner, .partner:
            return true
        case .familyAdult, .familyTeen, .familyChild, .familyElderly,
             .tenant, .guest, .serviceProvider:
            return false
        }
    }

    /// The family core shares the house's life; outsiders (tenant, guest,
    /// service provider) keep strictly to their own things — DMs, groups they
    /// were added to, tasks they're tagged in. Mirrors the server-side
    /// has_family_access() gate so the UI never shows surfaces RLS will empty.
    var isFamilyMember: Bool {
        switch self {
        case .owner, .partner, .familyAdult, .familyTeen, .familyChild, .familyElderly:
            return true
        case .tenant, .guest, .serviceProvider:
            return false
        }
    }
}

extension PropertyService {
    /// The typed role for the primary property. nil while loading.
    var role: PropertyRole? { PropertyRole.resolve(myRole) }

    /// Whether the current user belongs to the family core. nil role (still
    /// loading) fails OPEN — consistent with the documented pattern above, so
    /// the owner's screen never flashes trimmed UI at startup.
    var isFamilyMember: Bool { role?.isFamilyMember ?? true }
}

import Foundation
import Observation

// MARK: - Member invitation (audit trail row from migration 095)

struct MemberInvitation: Identifiable, Codable, Hashable {
    let id: UUID
    let email: String
    let name: String?
    let role: String
    let createdAt: String
    let expiresAt: String
    let revokedAt: String?
    let accepted: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, name, role, accepted
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }

    var createdDate: Date? { ISODate.date(from: createdAt) }
    var expiresDate: Date? { ISODate.date(from: expiresAt) }
    var isRevoked: Bool { revokedAt != nil }

    /// Whole days until the invite link stops working (negative = expired).
    var daysLeft: Int {
        guard let exp = expiresDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
    }
    var isExpired: Bool { (expiresDate ?? .distantPast) < Date() }

    var sentDisplay: String {
        guard let d = createdDate else { return "" }
        return AppDateDisplay.dayMonthCommaTime.string(from: d)
    }
}

// MARK: - Service

@MainActor
@Observable
final class InvitationService {
    var invitations: [MemberInvitation] = []
    var isLoading = false
    var error: String?

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            invitations = try await supabase
                .rpc("list_member_invitations", params: ["p_property_id": propertyId.uuidString])
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Marks the invitation revoked and (server-side) removes the invitee's
    /// membership + unlinks their contact row.
    func revoke(_ invitation: MemberInvitation, propertyId: UUID) async {
        do {
            try await supabase
                .rpc("revoke_member_invitation", params: ["p_invitation_id": invitation.id.uuidString])
                .execute()
            await load(propertyId: propertyId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Removes a member entirely: contact row + property membership (never the
    /// owner) + revokes any invitation for their email.
    func removeMember(familyMemberId: UUID) async throws {
        try await supabase
            .rpc("remove_property_member", params: ["p_family_member_id": familyMemberId.uuidString])
            .execute()
    }
}

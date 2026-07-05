import Foundation
import Observation
import Supabase

// MARK: - Account members (people with real PRVIO accounts)
//
// Reads property_members joined with profiles (household-readable since
// migration 106) so the Members hub can show everyone who actually has an
// account — and lets the owner administer them: change role, block access
// for a period (server RPCs from migration 108) or delete the account
// entirely (admin-delete-member edge function).

struct AccountMember: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var role: String
    var status: String
    var nickname: String?
    var blockedUntil: String?
    var joinedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, status, nickname
        case userId       = "user_id"
        case blockedUntil = "blocked_until"
        case joinedAt     = "joined_at"
    }

    var blockedUntilDate: Date? { blockedUntil.flatMap { ISODate.date(from: $0) } }
    var joinedDate: Date? { joinedAt.flatMap { ISODate.date(from: $0) } }

    /// Blocked right now — suspended with no end date, or an end date ahead.
    var isBlocked: Bool {
        guard status == "suspended" else { return false }
        guard let until = blockedUntilDate else { return true }
        return until > Date()
    }
}

struct AccountProfile: Codable, Hashable {
    let id: UUID
    var displayName: String?
    var fullName: String?
    var email: String?
    var phone: String?
    var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email, phone
        case displayName = "display_name"
        case fullName    = "full_name"
        case avatarUrl   = "avatar_url"
    }

    var bestName: String {
        let d = displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !d.isEmpty { return d }
        let f = fullName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !f.isEmpty { return f }
        return email ?? ""
    }
}

@MainActor
@Observable
final class AccountMemberService {
    var members: [AccountMember] = []
    var profiles: [UUID: AccountProfile] = [:]
    var isLoading = false
    var error: String?

    var currentUserId: UUID? { supabase.auth.currentSession?.user.id }

    /// True when the signed-in user can administer accounts.
    var canAdminister: Bool {
        guard let uid = currentUserId else { return false }
        return members.contains { $0.userId == uid && ["owner", "partner"].contains($0.role) }
    }

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [AccountMember] = try await supabase
                .from("property_members")
                .select("id, user_id, role, status, nickname, blocked_until, joined_at")
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            members = rows

            let ids = rows.map { $0.userId.uuidString.lowercased() }
            if !ids.isEmpty {
                let profs: [AccountProfile] = try await supabase
                    .from("profiles")
                    .select("id, display_name, full_name, email, phone, avatar_url")
                    .in("id", values: ids)
                    .execute().value
                profiles = Dictionary(profs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateRole(_ member: AccountMember, to role: String) async throws {
        try await supabase
            .from("property_members")
            .update(["role": role])
            .eq("id", value: member.id.uuidString)
            .execute()
        if let i = members.firstIndex(where: { $0.id == member.id }) {
            members[i].role = role
        }
    }

    /// Blocks access until the given date; nil = indefinitely.
    func block(_ member: AccountMember, until: Date?) async throws {
        struct Params: Encodable {
            let p_member_id: String
            let p_until: String?
        }
        let iso = until.map { ISO8601DateFormatter().string(from: $0) }
        try await supabase
            .rpc("block_property_member", params: Params(p_member_id: member.id.uuidString, p_until: iso))
            .execute()
        if let i = members.firstIndex(where: { $0.id == member.id }) {
            members[i].status = "suspended"
            members[i].blockedUntil = iso
        }
    }

    func unblock(_ member: AccountMember) async throws {
        struct Params: Encodable { let p_member_id: String }
        try await supabase
            .rpc("unblock_property_member", params: Params(p_member_id: member.id.uuidString))
            .execute()
        if let i = members.firstIndex(where: { $0.id == member.id }) {
            members[i].status = "active"
            members[i].blockedUntil = nil
        }
    }

    /// Permanently deletes the member's account (auth user + data links).
    func deleteAccount(_ member: AccountMember) async throws {
        struct Payload: Encodable { let memberId: String }
        _ = try await supabase.functions.invoke(
            "admin-delete-member",
            options: .init(body: Payload(memberId: member.id.uuidString))
        )
        members.removeAll { $0.id == member.id }
        profiles[member.userId] = nil
    }
}

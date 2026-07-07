import Foundation
import Observation
import Supabase
import SwiftUI

// MARK: - Communities: multiple chat groups per property (workers, family, …)
//
// Backed by `chat_groups` + `chat_group_members` (migration 078). Membership is
// contact-based (member_id is the FamilyMember UUID as text, or "you" for the
// current user) so it works for family members who aren't app auth users.

struct ChatGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var propertyId: UUID?
    var name: String
    var description: String
    var avatarUrl: String?
    var kind: String            // "family" | "work" | "custom"
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, kind
        case propertyId = "property_id"
        case avatarUrl  = "avatar_url"
        case createdAt  = "created_at"
    }

    var kindIcon: String {
        switch kind {
        case "family": return "house.fill"
        case "work":   return "hammer.fill"
        default:       return "person.3.fill"
        }
    }

    var kindLabel: String {
        switch kind {
        case "family": return String(localized: "Familie")
        case "work":   return String(localized: "Muncă")
        default:       return String(localized: "Grup")
        }
    }

    var kindTint: Color {
        switch kind {
        case "family": return Color.brandSuccess
        case "work":   return .orange
        default:       return Color.brandPurple
        }
    }
}

/// The newest message of a community group, for the list preview line.
struct GroupMessagePreview: Decodable {
    let groupId: UUID
    let senderName: String?
    let body: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case body
        case groupId    = "group_id"
        case senderName = "sender_name"
        case createdAt  = "created_at"
    }
}

struct ChatGroupMember: Identifiable, Codable, Hashable {
    var id: String { memberId }
    let groupId: UUID
    let memberId: String
    var memberName: String
    var role: String

    enum CodingKeys: String, CodingKey {
        case role
        case groupId    = "group_id"
        case memberId   = "member_id"
        case memberName = "member_name"
    }
}

@MainActor
@Observable
final class ChatGroupService {
    var groups: [ChatGroup] = []
    var membersByGroup: [UUID: [ChatGroupMember]] = [:]
    var latestByGroup: [UUID: GroupMessagePreview] = [:]
    var isLoading = false
    var error: String?

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [ChatGroup] = try await supabase
                .from("chat_groups")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            groups = rows
            await loadAllMembers()
            await loadPreviews(propertyId: propertyId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Latest message per group in ONE query: the newest ~80 group-scoped
    /// rows for the property, reduced client-side to the first per group.
    func loadPreviews(propertyId: UUID) async {
        let ids = groups.map { $0.id.uuidString }
        guard !ids.isEmpty else { latestByGroup = [:]; return }
        do {
            let rows: [GroupMessagePreview] = try await supabase
                .from("messages")
                .select("group_id, sender_name, body, created_at")
                .eq("property_id", value: propertyId.uuidString)
                .in("group_id", values: ids)
                .order("created_at", ascending: false)
                .limit(80)
                .execute()
                .value
            var latest: [UUID: GroupMessagePreview] = [:]
            for row in rows where latest[row.groupId] == nil { latest[row.groupId] = row }
            latestByGroup = latest
        } catch {
            // Non-fatal: rows fall back to the member-count line.
        }
    }

    /// "Ana: vin mâine" — the preview line for a group's row, with structured
    /// bodies (shared contacts) rendered as their human meaning.
    func previewLine(for group: ChatGroup) -> (text: String, date: Date?)? {
        guard let p = latestByGroup[group.id] else { return nil }
        let contacts = SharedContactPayload.decode(p.body)
        let bodyText = contacts.isEmpty
            ? (p.body ?? "")
            : String(format: String(localized: "search_shared_contact"),
                     contacts.map(\.name).joined(separator: ", "))
        let prefix = (p.senderName?.isEmpty == false) ? "\(p.senderName ?? ""): " : ""
        return (prefix + bodyText, p.createdAt.flatMap { AppDate.timestamp(from: $0) })
    }

    private func loadAllMembers() async {
        guard !groups.isEmpty else { membersByGroup = [:]; return }
        do {
            let rows: [ChatGroupMember] = try await supabase
                .from("chat_group_members")
                .select()
                .execute()
                .value
            membersByGroup = Dictionary(grouping: rows, by: { $0.groupId })
        } catch {
            // Non-fatal: keep groups list even if member fetch fails.
        }
    }

    func members(for group: ChatGroup) -> [ChatGroupMember] {
        membersByGroup[group.id] ?? []
    }

    /// Creates a group and inserts its members in one flow. `selected` are the
    /// family members to add; the current user ("you") is always included.
    @discardableResult
    func create(propertyId: UUID, name: String, kind: String,
                selected: [FamilyMember], myName: String) async -> ChatGroup? {
        struct NewGroup: Encodable {
            let property_id: String
            let name: String
            let kind: String
            let created_by: String?
        }
        do {
            let payload = NewGroup(
                property_id: propertyId.uuidString,
                name: name,
                kind: kind,
                created_by: supabase.auth.currentSession?.user.id.uuidString
            )
            let created: ChatGroup = try await supabase
                .from("chat_groups")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            struct NewMember: Encodable {
                let group_id: String
                let member_id: String
                let member_name: String
                let role: String
            }
            var rows: [NewMember] = [
                NewMember(group_id: created.id.uuidString, member_id: "you",
                          member_name: myName, role: "admin")
            ]
            for m in selected {
                rows.append(NewMember(group_id: created.id.uuidString,
                                      member_id: m.id.uuidString,
                                      member_name: m.name, role: "member"))
            }
            try await supabase.from("chat_group_members").insert(rows).execute()

            groups.append(created)
            await loadAllMembers()
            return created
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func delete(_ group: ChatGroup) async {
        do {
            try await supabase.from("chat_groups")
                .delete().eq("id", value: group.id.uuidString).execute()
            groups.removeAll { $0.id == group.id }
            membersByGroup[group.id] = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Renames a group in place.
    func rename(_ group: ChatGroup, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await supabase.from("chat_groups")
                .update(["name": trimmed])
                .eq("id", value: group.id.uuidString)
                .execute()
            if let i = groups.firstIndex(where: { $0.id == group.id }) { groups[i].name = trimmed }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Adds family members to a group (each as a regular member).
    func addMembers(_ selected: [FamilyMember], to group: ChatGroup) async {
        guard !selected.isEmpty else { return }
        struct NewMember: Encodable {
            let group_id: String
            let member_id: String
            let member_name: String
            let role: String
        }
        let rows = selected.map {
            NewMember(group_id: group.id.uuidString, member_id: $0.id.uuidString,
                      member_name: $0.name, role: "member")
        }
        do {
            try await supabase.from("chat_group_members").insert(rows).execute()
            await loadAllMembers()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Removes one member from a group.
    func removeMember(_ member: ChatGroupMember, from group: ChatGroup) async {
        do {
            try await supabase.from("chat_group_members")
                .delete()
                .eq("group_id", value: group.id.uuidString)
                .eq("member_id", value: member.memberId)
                .execute()
            membersByGroup[group.id]?.removeAll { $0.memberId == member.memberId }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

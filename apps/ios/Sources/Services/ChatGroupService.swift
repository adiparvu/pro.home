import Foundation
import Supabase

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
final class ChatGroupService: ObservableObject {
    @Published var groups: [ChatGroup] = []
    @Published var membersByGroup: [UUID: [ChatGroupMember]] = [:]
    @Published var isLoading = false
    @Published var error: String?

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
        } catch {
            self.error = error.localizedDescription
        }
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
}

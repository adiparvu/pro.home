import Foundation
import Supabase

// MARK: - Cross-device sync for conversation prefs & blocks (Phase 2: A2 + S7)
//
// These back the UserDefaults stores in ConversationsView so pin / mute / archive
// and Block sync across devices via Supabase (chat_user_prefs, chat_blocks).
// UserDefaults stays as an instant-load offline cache; Supabase is the source of
// truth. Conversation key (conv_id) is the same string the UI already uses:
// 'group', a Communities group UUID, or the DM peer's display name.

enum ChatPrefsSync {
    struct PrefRow: Decodable {
        let convId: String
        let pinned: Bool
        let muted: Bool
        let archived: Bool
        /// Optional so rows decode even before migration 119 lands.
        let manualUnread: Bool?
        let clearedAt: String?
        enum CodingKeys: String, CodingKey {
            case convId = "conv_id"
            case pinned, muted, archived
            case manualUnread = "manual_unread"
            case clearedAt = "cleared_at"
        }
    }

    static func load() async -> [PrefRow] {
        (try? await supabase.from("chat_user_prefs").select().execute().value) ?? []
    }

    static func upsert(convId: String, pinned: Bool, muted: Bool, archived: Bool,
                       manualUnread: Bool, propertyId: UUID?) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        struct Payload: Encodable {
            let user_id: String
            let conv_id: String
            let property_id: String?
            let pinned: Bool
            let muted: Bool
            let archived: Bool
            let manual_unread: Bool
        }
        let p = Payload(user_id: uid.uuidString, conv_id: convId,
                        property_id: propertyId?.uuidString,
                        pinned: pinned, muted: muted, archived: archived,
                        manual_unread: manualUnread)
        _ = try? await supabase.from("chat_user_prefs")
            .upsert(p, onConflict: "user_id,conv_id").execute()
    }

    /// Records the "clear conversation" cutoff. Upserts only cleared_at, so the
    /// pin/mute/archive flags on the same row are preserved.
    static func setCleared(convId: String, propertyId: UUID?) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        struct Payload: Encodable {
            let user_id: String
            let conv_id: String
            let property_id: String?
            let cleared_at: String
        }
        let p = Payload(user_id: uid.uuidString, conv_id: convId,
                        property_id: propertyId?.uuidString,
                        cleared_at: ISODate.string(from: Date()))
        _ = try? await supabase.from("chat_user_prefs")
            .upsert(p, onConflict: "user_id,conv_id").execute()
    }
}

enum ChatBlockSync {
    struct BlockRow: Decodable {
        let blockedName: String
        /// Stable identity (migration 120); nil only on pre-phase-A rows.
        let blockedMemberId: UUID?
        enum CodingKeys: String, CodingKey {
            case blockedName = "blocked_name"
            case blockedMemberId = "blocked_member_id"
        }
    }

    struct Blocked {
        var memberIds: Set<UUID> = []
        var names: Set<String> = []
    }

    /// Who the current user has blocked — member ids (rename-proof) plus the
    /// display names still carried by legacy rows.
    static func load() async -> Blocked {
        let rows: [BlockRow] = (try? await supabase.from("chat_blocks")
            .select("blocked_name, blocked_member_id").execute().value) ?? []
        var out = Blocked()
        for r in rows {
            if let id = r.blockedMemberId { out.memberIds.insert(id) }
            out.names.insert(r.blockedName)
        }
        return out
    }

    static func block(member: FamilyMember, myName: String, propertyId: UUID?) async {
        struct Payload: Encodable {
            let blocker_name: String
            let blocked_name: String
            let blocked_member_id: String
            let property_id: String?
        }
        // blocker_id is stamped server-side (chat_blocks_fill_ids trigger);
        // names ride along as display snapshots and for pre-120 clients.
        let p = Payload(blocker_name: myName, blocked_name: member.name,
                        blocked_member_id: member.id.uuidString,
                        property_id: propertyId?.uuidString)
        _ = try? await supabase.from("chat_blocks")
            .upsert(p, onConflict: "blocker_name,blocked_name").execute()
    }

    static func unblock(member: FamilyMember) async {
        // Two keyed deletes: the id form for phase-A rows, the name form for
        // legacy ones. RLS scopes both to the caller's own blocks.
        _ = try? await supabase.from("chat_blocks")
            .delete().eq("blocked_member_id", value: member.id.uuidString).execute()
        _ = try? await supabase.from("chat_blocks")
            .delete().eq("blocked_name", value: member.name).execute()
    }
}

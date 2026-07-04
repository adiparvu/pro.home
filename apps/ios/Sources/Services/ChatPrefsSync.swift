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
        let clearedAt: String?
        enum CodingKeys: String, CodingKey {
            case convId = "conv_id"
            case pinned, muted, archived
            case clearedAt = "cleared_at"
        }
    }

    static func load() async -> [PrefRow] {
        (try? await supabase.from("chat_user_prefs").select().execute().value) ?? []
    }

    static func upsert(convId: String, pinned: Bool, muted: Bool, archived: Bool,
                       propertyId: UUID?) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        struct Payload: Encodable {
            let user_id: String
            let conv_id: String
            let property_id: String?
            let pinned: Bool
            let muted: Bool
            let archived: Bool
        }
        let p = Payload(user_id: uid.uuidString, conv_id: convId,
                        property_id: propertyId?.uuidString,
                        pinned: pinned, muted: muted, archived: archived)
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
                        cleared_at: ISO8601DateFormatter().string(from: Date()))
        _ = try? await supabase.from("chat_user_prefs")
            .upsert(p, onConflict: "user_id,conv_id").execute()
    }
}

enum ChatBlockSync {
    struct BlockRow: Decodable {
        let blockedName: String
        enum CodingKeys: String, CodingKey { case blockedName = "blocked_name" }
    }

    /// Display names the current user has blocked.
    static func load() async -> Set<String> {
        let rows: [BlockRow] = (try? await supabase.from("chat_blocks")
            .select("blocked_name").execute().value) ?? []
        return Set(rows.map { $0.blockedName })
    }

    static func block(name: String, myName: String, propertyId: UUID?) async {
        struct Payload: Encodable {
            let blocker_name: String
            let blocked_name: String
            let property_id: String?
        }
        let p = Payload(blocker_name: myName, blocked_name: name,
                        property_id: propertyId?.uuidString)
        _ = try? await supabase.from("chat_blocks")
            .upsert(p, onConflict: "blocker_name,blocked_name").execute()
    }

    static func unblock(name: String) async {
        _ = try? await supabase.from("chat_blocks")
            .delete().eq("blocked_name", value: name).execute()
    }
}

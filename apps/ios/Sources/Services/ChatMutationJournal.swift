import Foundation
import Supabase

// MARK: - Chat mutation journal (P0b — no silent losses)
//
// A pin, a mark, a reaction, an edit or a delete that failed on the wire
// used to end as a DEBUG log line: the user's intent evaporated. Every such
// mutation is idempotent-by-content — absolute values keyed by message id —
// so the honest fix is a journal: the failed intent is recorded here and
// replayed on the next foreground beat until it lands or expires.
//
// Deliberately NOT journaled: the group chat's pin/mark/reaction paths.
// Those roll back their optimistic patch visibly, so the user already SEES
// the failure and can retry — journaling on top would let a stale intent
// overwrite a newer manual choice. The journal exists for the silent sites
// only, where the alternative is nothing at all.

struct ChatMutationJournal: Codable {
    enum Kind: String, Codable {
        case flag        // dm_set_pin / dm_set_mark RPC — value is absolute
        case reaction    // message_reactions delete-own (+ optional insert)
        case edit        // body + edited_at UPDATE
        case tombstone   // deleted_for_all UPDATE
        case hardDelete  // row DELETE
    }

    let kind: Kind
    let messageId: UUID
    let createdAt: Date
    // flag
    var rpc: String?
    var value: Bool?
    // edit / tombstone / hardDelete
    var table: String?
    var body: String?
    var editedAt: String?
    // reaction
    var propertyId: UUID?
    var userId: UUID?
    var reactorName: String?
    var emoji: String?
    var insertNew: Bool?

    /// Journaled intents older than this replay no more — a week-old pin is
    /// likelier to contradict the user than to serve them.
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    // MARK: Recording (call sites are the catch blocks)

    static func recordFlag(rpc: String, messageId: UUID, value: Bool) {
        append(.init(kind: .flag, messageId: messageId, createdAt: Date(),
                     rpc: rpc, value: value))
    }

    static func recordReaction(messageId: UUID, propertyId: UUID, userId: UUID,
                               reactorName: String, emoji: String, insertNew: Bool) {
        append(.init(kind: .reaction, messageId: messageId, createdAt: Date(),
                     propertyId: propertyId, userId: userId,
                     reactorName: reactorName, emoji: emoji, insertNew: insertNew))
    }

    static func recordEdit(table: String, messageId: UUID, body: String, editedAtISO: String) {
        append(.init(kind: .edit, messageId: messageId, createdAt: Date(),
                     table: table, body: body, editedAt: editedAtISO))
    }

    static func recordTombstone(table: String, messageId: UUID) {
        append(.init(kind: .tombstone, messageId: messageId, createdAt: Date(), table: table))
    }

    static func recordHardDelete(table: String, messageId: UUID) {
        append(.init(kind: .hardDelete, messageId: messageId, createdAt: Date(), table: table))
    }

    private static func append(_ entry: ChatMutationJournal) {
        guard let data = try? JSONEncoder().encode(entry),
              let json = String(data: data, encoding: .utf8) else { return }
        SharedDataStore.appendPendingChatMutation(json)
    }

    // MARK: Replay (one pass per foreground beat)

    /// Pops every journaled mutation and applies it; failures go straight
    /// back, expired entries are dropped. The apply path passes
    /// `journal: false` into ChatMessageStore, so a replay that fails again
    /// cannot re-record itself into a duplicate.
    static func replayAll() async {
        let raw = SharedDataStore.popPendingChatMutations()
        guard !raw.isEmpty else { return }
        for json in raw {
            guard let data = json.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(ChatMutationJournal.self, from: data)
            else { continue }   // undecodable: drop, never spin forever
            guard Date().timeIntervalSince(entry.createdAt) < maxAge else { continue }
            if await entry.apply() == false {
                SharedDataStore.appendPendingChatMutation(json)
            }
        }
    }

    private func apply() async -> Bool {
        switch kind {
        case .flag:
            guard let rpc, let value else { return true }
            do {
                try await supabase
                    .rpc(rpc, params: ["p_message": AnyJSON.string(messageId.uuidString),
                                       "p_value": AnyJSON.bool(value)])
                    .execute()
                return true
            } catch { return false }
        case .reaction:
            guard let propertyId, let userId, let reactorName, let emoji else { return true }
            do {
                // removeExisting is always true on replay: deleting my own
                // (possibly absent) row is a safe no-op, and it normalizes
                // whatever happened between the failure and now.
                try await ChatEngineCore.persistReactionToggle(
                    messageId: messageId, propertyId: propertyId, userId: userId,
                    reactorName: reactorName, emoji: emoji,
                    removeExisting: true, insertNew: insertNew ?? true)
                return true
            } catch { return false }
        case .edit:
            guard let table, let body, let editedAt else { return true }
            return await ChatMessageStore.editRow(
                table: table, id: messageId, newBody: body,
                editedAtISO: editedAt, tag: "Journal", journal: false)
        case .tombstone:
            guard let table else { return true }
            return await ChatMessageStore.tombstoneRow(
                table: table, id: messageId, tag: "Journal", journal: false)
        case .hardDelete:
            guard let table else { return true }
            return await ChatMessageStore.deleteRow(
                table: table, id: messageId, tag: "Journal", journal: false)
        }
    }
}

import Foundation

// MARK: - Shared message-row operations (Chat unification P3c)
//
// The delete/tombstone/hide mechanics both chat engines duplicated: a hard
// DELETE of one row, the "delete for everyone" tombstone (deleted_for_all),
// and the device-local "delete for me" hidden-id set in UserDefaults. The
// engines keep their own local-state patches (they differ: DM bumps its
// revision counters, the group removes the row) and their own table/key —
// only the row mechanics live here once.
enum ChatMessageStore {
    /// Hard-deletes a message row. Returns false on failure (logged in
    /// DEBUG); the engine patches its local array only on success — exactly
    /// the do/catch shape both engines had.
    static func deleteRow(table: String, id: UUID, tag: String,
                          journal: Bool = true) async -> Bool {
        do {
            try await supabase
                .from(table)
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            return true
        } catch {
#if DEBUG
            debugLog("[\(tag)] delete error: \(error)")
#endif
            // P0b: a failed delete is an intent, not a log line — journal it
            // for the next foreground beat (replay passes journal: false so
            // a failing replay can't re-record itself).
            if journal { ChatMutationJournal.recordHardDelete(table: table, messageId: id) }
            return false
        }
    }

    /// Tombstones a row for everyone — keeps it but flips deleted_for_all.
    static func tombstoneRow(table: String, id: UUID, tag: String,
                             journal: Bool = true) async -> Bool {
        struct D: Encodable { let deleted_for_all: Bool }
        do {
            try await supabase
                .from(table)
                .update(D(deleted_for_all: true))
                .eq("id", value: id.uuidString)
                .execute()
            return true
        } catch {
#if DEBUG
            debugLog("[\(tag)] deleteForEveryone error: \(error)")
#endif
            if journal { ChatMutationJournal.recordTombstone(table: table, messageId: id) }
            return false
        }
    }

    /// Edits a row's body and stamps edited_at (P5 — the UPDATE both engines
    /// duplicated; wire payload is byte-identical to both former copies).
    /// The timestamp is the CALLER's, so each engine keeps its own formatter
    /// and patches its local row with exactly the value it persisted.
    static func editRow(table: String, id: UUID, newBody: String,
                        editedAtISO: String, tag: String,
                        journal: Bool = true) async -> Bool {
        struct E: Encodable { let body: String; let edited_at: String }
        do {
            try await supabase
                .from(table)
                .update(E(body: newBody, edited_at: editedAtISO))
                .eq("id", value: id.uuidString)
                .execute()
            return true
        } catch {
#if DEBUG
            debugLog("[\(tag)] editMessage error: \(error)")
#endif
            if journal {
                ChatMutationJournal.recordEdit(table: table, messageId: id,
                                              body: newBody, editedAtISO: editedAtISO)
            }
            return false
        }
    }

    /// The device-local "delete for me" hidden-id set stored under `key`
    /// (`dm.hidden.ids` / `chat.hidden.ids` — unchanged).
    static func hiddenIds(key: String) -> Set<UUID> {
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr.compactMap { UUID(uuidString: $0) })
    }

    /// Hides one id under `key` (persists across reloads).
    static func hide(_ id: UUID, key: String) {
        var h = hiddenIds(key: key)
        h.insert(id)
        UserDefaults.standard.set(h.map(\.uuidString), forKey: key)
    }
}

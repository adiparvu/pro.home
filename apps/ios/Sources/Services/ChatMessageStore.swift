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
    static func deleteRow(table: String, id: UUID, tag: String) async -> Bool {
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
            return false
        }
    }

    /// Tombstones a row for everyone — keeps it but flips deleted_for_all.
    static func tombstoneRow(table: String, id: UUID, tag: String) async -> Bool {
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

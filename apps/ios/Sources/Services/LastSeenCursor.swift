import Foundation

// MARK: - Last-seen cursor (Chat unification P3b)
//
// The device-local "when did I last have this conversation open" timestamp
// both chat engines keep in UserDefaults — its only job is to place the
// "unread messages" divider. The engines carried separate copies of the
// read/write (and the DM side a one-time legacy-key migration); this value
// type owns the mechanics once, parameterized by the exact keys each engine
// already uses, so no stored data moves.
struct LastSeenCursor {
    /// The engine's existing UserDefaults key — preserved byte-for-byte
    /// (`dm.lastseen.id.<storeKey>` / `chat.lastseen.<propertyId>`).
    let key: String
    /// Optional pre-identity key (DM's `dm.lastseen.<memberName>`), migrated
    /// to `key` on first read and removed.
    var legacyKey: String? = nil

    /// The last-seen moment; `.distantPast` when the conversation was never
    /// opened on this device.
    var date: Date {
        let defaults = UserDefaults.standard
        if let d = defaults.object(forKey: key) as? Date { return d }
        if let legacyKey, let legacy = defaults.object(forKey: legacyKey) as? Date {
            defaults.set(legacy, forKey: key)
            defaults.removeObject(forKey: legacyKey)
            return legacy
        }
        return .distantPast
    }

    /// Stamps "seen now".
    func markSeen() {
        UserDefaults.standard.set(Date(), forKey: key)
    }
}

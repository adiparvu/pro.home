import Foundation

// MARK: - Account ID authority
//
// The user-facing account identity, derived deterministically from the
// Supabase user UUID. Every surface that displays or searches an account ID
// goes through here, so the format can never drift between screens — and
// because it is pure derivation, the ID is permanently tied to the account
// itself, not a cosmetic string.

enum AccountID {
    /// "PRVIO-3F2A9C1B" — brand prefix + the first UUID group, uppercase.
    static func display(for userId: UUID) -> String {
        "PRVIO-" + String(userId.uuidString.prefix(8)).uppercased()
    }

    /// True when a typed query targets this account. Accepts the full form
    /// ("PRVIO-3F2A9C1B"), the bare hex ("3F2A9C1B"), lowercase, and any
    /// dash/space arrangement. Requires at least 4 hex characters after the
    /// prefix so short generic queries don't surface the account row.
    static func matches(_ query: String, userId: UUID) -> Bool {
        var q = query.uppercased().filter { $0.isLetter || $0.isNumber }
        if q.hasPrefix("PRVIO") { q.removeFirst(5) }
        guard q.count >= 4 else { return false }
        return String(userId.uuidString.prefix(8)).uppercased().hasPrefix(q)
    }
}

import SwiftUI

// MARK: - ChatPeer (identity-based DM counterpart)
//
// A DM thread's identity is the peer's AUTH USER ID; the name and avatar are
// display data hydrated from `profiles` (via MemberDirectory — the app's one
// batched, cached, realtime-fresh profiles query). A peer needs NO
// family_members row to exist: the property owner is typically absent from
// the roster, which is exactly how roster-derived conversation lists lost
// the owner's threads on every other device.
struct ChatPeer: Identifiable, Hashable {
    /// The peer's auth.users id — the durable identity of the thread.
    let id: UUID
    /// Trimmed display name (profiles carry stray whitespace in production,
    /// e.g. "Adi " with a trailing space).
    let displayName: String
    /// The peer's live profile photo, when they have one.
    var avatarUrl: String?

    init(id: UUID, displayName: String, avatarUrl: String? = nil) {
        self.id = id
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = trimmed.isEmpty ? String(localized: "dm_peer_unknown") : trimmed
        self.avatarUrl = avatarUrl
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    /// Deterministic tint for peers without a roster colour — derived from the
    /// id's raw bytes (never `hashValue`, which is randomized per launch).
    var swiftColor: Color {
        let palette: [Color] = [.brandPrimaryBlue, .brandPurple, .brandSuccess,
                                .brandWarning, .brandSkyBlue, .brandIndigo]
        let byte = Int(id.uuid.0) ^ Int(id.uuid.15)
        return palette[byte % palette.count]
    }
}

extension ChatPeer {
    /// Hydrates display data from the cached profiles directory, falling back
    /// to whatever snapshot the caller already holds (roster name, stored URL).
    @MainActor
    init(userId: UUID, fallbackName: String? = nil, fallbackAvatar: String? = nil) {
        let entry = MemberDirectory.shared.byId[userId]
        let liveName = entry?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let liveAvatar = entry?.avatarUrl
        self.init(id: userId,
                  displayName: liveName.isEmpty ? (fallbackName ?? "") : liveName,
                  avatarUrl: (liveAvatar?.isEmpty == false) ? liveAvatar : fallbackAvatar)
    }

    /// The peer behind a roster row — nil when the member holds no account
    /// (a thread identity can't exist without an auth user).
    @MainActor
    init?(member: FamilyMember) {
        guard let uid = member.userId else { return nil }
        self.init(userId: uid, fallbackName: member.name, fallbackAvatar: member.avatarUrl)
    }
}

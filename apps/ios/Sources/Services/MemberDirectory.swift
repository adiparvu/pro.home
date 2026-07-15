import Foundation
import Observation
import Supabase

/// Household member profiles (real accounts), keyed by auth user id — the
/// source of truth for avatars and display names of the people in the
/// property. RLS (migration 106) lets active members of the same property
/// read each other's profile rows, so this resolves every sender in chat,
/// not just the signed-in user.
///
/// This is the ONE authority every avatar reads from, so a photo is never a
/// stale snapshot: `family_members.avatar_url` (and any other row that once
/// copied an avatar) is ignored for account holders in favor of the live
/// `profiles.avatar_url` here. Because the type is `@Observable`, mutating
/// `byId` repaints every `MemberAvatar` on screen instantly — no manual
/// refresh, no per-view cache to invalidate.
@MainActor
@Observable
final class MemberDirectory {
    static let shared = MemberDirectory()
    private init() {}

    private var realtimeChannel: RealtimeChannelV2?
    private var reloadTask: Task<Void, Never>?

    struct Entry: Codable, Identifiable, Hashable {
        let id: UUID
        var displayName: String?
        var fullName: String?
        var avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case fullName    = "full_name"
            case avatarUrl   = "avatar_url"
        }

        var name: String { displayName ?? fullName ?? "" }
    }

    private(set) var byId: [UUID: Entry] = [:]
    private var loaded = false

    func loadIfNeeded() async {
        if !loaded { await reload() }
        subscribeRealtime()
    }

    func reload() async {
        let rows: [Entry]? = try? await supabase
            .from("profiles")
            .select("id, display_name, full_name, avatar_url")
            .execute()
            .value
        guard let rows else { return }
        byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        loaded = true
    }

    /// Coalesced background refresh — called on foreground and when an
    /// avatar-bearing screen appears, so another member's newly-uploaded
    /// photo lands here (and thus on every avatar) without a manual pull.
    func refreshSoon() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reload()
        }
    }

    /// Instant local write when THIS device changes an avatar — the photo
    /// appears on every `MemberAvatar` before the network round-trip even
    /// starts, because the `@Observable` mutation repaints them synchronously.
    func setAvatar(userId: UUID, urlString: String?) {
        if var entry = byId[userId] {
            entry.avatarUrl = urlString
            byId[userId] = entry
        } else {
            byId[userId] = Entry(id: userId, displayName: nil, fullName: nil, avatarUrl: urlString)
        }
    }

    /// Live cross-device sync: when any member changes their profile photo on
    /// their own device, the change streams in here and every avatar updates.
    /// Best-effort — if `profiles` isn't in the realtime publication the
    /// foreground/on-appear `refreshSoon()` path still keeps avatars fresh.
    private func subscribeRealtime() {
        guard realtimeChannel == nil else { return }
        let channel = realtimeAnon.channel("profiles-directory")
        _ = channel.onPostgresChange(AnyAction.self, schema: "public", table: "profiles") { [weak self] _ in
            Task { @MainActor in self?.refreshSoon() }
        }
        realtimeChannel = channel
        Task { try? await channel.subscribeWithError() }
    }

    func avatarURL(for userId: UUID?) -> URL? {
        guard let userId, let s = byId[userId]?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Resolve a member by their display name — used where only a name is
    /// known (e.g. a chat notification titled with the sender). Case- and
    /// diacritic-insensitive; returns nil on no match or an ambiguous match,
    /// so a wrong avatar is never shown.
    func entry(matchingName name: String) -> Entry? {
        let needle = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let hits = byId.values.filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines) == needle
        }
        return hits.count == 1 ? hits.first : nil
    }

    /// The freshest avatar string for a member: the live profile photo when
    /// the member holds an account, else whatever snapshot the row carried.
    /// Reading this from a view `body` subscribes it to live updates.
    func avatarString(userId: UUID?, fallback: String?) -> String? {
        if let userId, let s = byId[userId]?.avatarUrl, !s.isEmpty { return s }
        return fallback
    }
}

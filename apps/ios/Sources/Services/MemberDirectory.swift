import Foundation
import Observation

/// Household member profiles (real accounts), keyed by auth user id — the
/// source of truth for avatars and display names of the people in the
/// property. RLS (migration 106) lets active members of the same property
/// read each other's profile rows, so this resolves every sender in chat,
/// not just the signed-in user.
@MainActor
@Observable
final class MemberDirectory {
    static let shared = MemberDirectory()
    private init() {}

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
        guard !loaded else { return }
        await reload()
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

    func avatarURL(for userId: UUID?) -> URL? {
        guard let userId, let s = byId[userId]?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

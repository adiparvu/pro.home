import Foundation

struct ProfileData: Codable, Equatable {
    let id: UUID
    var email: String
    var fullName: String
    var displayName: String?
    var firstName: String?
    var lastName: String?
    var birthDate: String?
    var avatarUrl: String?
    var phone: String?
    var socialLinks: [SocialLink]?
    var notes: String?
    var locale: String?
    var theme: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, phone, locale, theme, notes
        case fullName    = "full_name"
        case displayName = "display_name"
        case firstName   = "first_name"
        case lastName    = "last_name"
        case birthDate   = "birth_date"
        case avatarUrl   = "avatar_url"
        case socialLinks = "social_links"
        case createdAt   = "created_at"
    }

    var preferredName: String {
        // The ONE name authority — always trimmed: a single edge space here
        // forked every name-keyed DM surface app-wide ("Adi " vs "Adi", the
        // 2026-07-19 vanishing-thread field failure). Emptiness is judged
        // AFTER trimming so a whitespace-only field can't win the cascade.
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let full = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        return email.components(separatedBy: "@").first?.capitalized ?? "User"
    }

    var initial: String { String(preferredName.prefix(1)).uppercased() }
}

struct ProfileUpdate: Encodable {
    let fullName: String
    let displayName: String
    let firstName: String?
    let lastName: String?
    let birthDate: String?
    let phone: String?
    let email: String?
    let socialLinks: [SocialLink]
    let notes: String?
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
        case phone, email, notes
        case socialLinks = "social_links"
        case updatedAt = "updated_at"
    }
}


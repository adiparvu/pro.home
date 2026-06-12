import Foundation

struct ProfileData: Codable, Equatable {
    let id: UUID
    var email: String
    var fullName: String
    var displayName: String?
    var avatarUrl: String?
    var phone: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, phone
        case fullName = "full_name"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }

    var preferredName: String {
        if let d = displayName, !d.isEmpty { return d }
        if !fullName.isEmpty { return fullName }
        return email.components(separatedBy: "@").first?.capitalized ?? "User"
    }

    var initial: String { String(preferredName.prefix(1)).uppercased() }
}

struct ProfileUpdate: Encodable {
    let fullName: String
    let displayName: String
    let phone: String?
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case displayName = "display_name"
        case phone
        case updatedAt = "updated_at"
    }
}

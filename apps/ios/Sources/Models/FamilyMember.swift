import SwiftUI

struct FamilyMember: Identifiable, Codable, Hashable {
    let id: UUID
    let ownerId: UUID
    var propertyId: UUID?
    var name: String
    var email: String?
    var phone: String?
    var role: String
    var avatarUrl: String?
    var color: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, role, color
        case ownerId    = "owner_id"
        case propertyId = "property_id"
        case avatarUrl  = "avatar_url"
        case createdAt  = "created_at"
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var swiftColor: Color {
        Color(hex: color) ?? Color.blue
    }

    var roleLabel: String {
        switch role {
        case "owner":   return "Owner"
        case "partner": return "Partner"
        case "child":   return "Child"
        case "tenant":  return "Tenant"
        case "guest":   return "Guest"
        default:        return "Member"
        }
    }
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

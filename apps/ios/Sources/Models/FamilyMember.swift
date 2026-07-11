import SwiftUI

struct SocialLink: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var platform: String
    var handle: String

    var platformLabel: String {
        switch platform {
        case "instagram": return "Instagram"
        case "facebook":  return "Facebook"
        case "whatsapp":  return "WhatsApp"
        case "linkedin":  return "LinkedIn"
        case "tiktok":    return "TikTok"
        case "twitter":   return "X (Twitter)"
        case "telegram":  return "Telegram"
        default:          return platform.capitalized
        }
    }

    var platformIcon: String {
        switch platform {
        case "instagram": return "camera.filters"
        case "facebook":  return "hand.thumbsup.fill"
        case "whatsapp":  return "message.fill"
        case "linkedin":  return "briefcase.fill"
        case "tiktok":    return "music.note"
        case "twitter":   return "bird"
        case "telegram":  return "paperplane.fill"
        default:          return "link"
        }
    }

    var platformColor: Color {
        switch platform {
        case "instagram": return Color(red: 0.85, green: 0.20, blue: 0.55)
        case "facebook":  return Color(red: 0.23, green: 0.35, blue: 0.68)
        case "whatsapp":  return Color(red: 0.16, green: 0.72, blue: 0.37)
        case "linkedin":  return Color(red: 0.10, green: 0.47, blue: 0.71)
        case "tiktok":    return .primary
        case "twitter":   return Color(red: 0.10, green: 0.55, blue: 0.92)
        case "telegram":  return Color(red: 0.13, green: 0.60, blue: 0.87)
        default:          return .blue
        }
    }

    var openURL: URL? {
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
                      .replacingOccurrences(of: "@", with: "")
        switch platform {
        case "instagram": return URL(string: "https://instagram.com/\(h)")
        case "facebook":  return URL(string: "https://facebook.com/\(h)")
        case "whatsapp":  return URL(string: "https://wa.me/\(h.filter { $0.isNumber })")
        case "linkedin":  return URL(string: "https://linkedin.com/in/\(h)")
        case "tiktok":    return URL(string: "https://tiktok.com/@\(h)")
        case "twitter":   return URL(string: "https://x.com/\(h)")
        case "telegram":  return URL(string: "https://t.me/\(h)")
        default:          return URL(string: h)
        }
    }
}

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
    var birthday: String?
    var socialLinks: [SocialLink]?
    let createdAt: String
    /// auth.users id when this member holds an account (identity backbone —
    /// chat threads/blocks key on ids, names are display only). Defaulted so
    /// existing memberwise constructions (tests) stay source-compatible.
    var userId: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, role, color, birthday
        case ownerId     = "owner_id"
        case propertyId  = "property_id"
        case avatarUrl   = "avatar_url"
        case socialLinks = "social_links"
        case createdAt   = "created_at"
        case userId      = "user_id"
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var swiftColor: Color { Color(hex: color) ?? .blue }

    var roleLabel: String {
        switch role {
        case "owner":   return String(localized: "Owner")
        case "partner": return String(localized: "Partner")
        case "teen":    return String(localized: "Teen")
        case "child":   return String(localized: "Child")
        case "tenant":  return String(localized: "Tenant")
        case "worker":  return String(localized: "Worker")
        case "guest":   return String(localized: "Guest")
        default:        return String(localized: "Member")
        }
    }

    var birthdayDate: Date? {
        guard let b = birthday else { return nil }
        return AppDateDisplay.dayUTC.date(from: b)
    }
}

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

    /// The platform's accent for text, rings and tinted chips — the official
    /// brand color, mirroring the fields SocialBrandIcon paints (the badge
    /// itself is always drawn by SocialBrandIcon, never composed from this).
    /// TikTok and X are brand-black, so they use `.primary` to stay legible
    /// in both color schemes wherever this drives foreground text.
    var platformColor: Color {
        switch platform {
        case "instagram": return Color(red: 0.882, green: 0.188, blue: 0.424) // #E1306C
        case "facebook":  return Color(red: 0.094, green: 0.467, blue: 0.949) // #1877F2
        case "whatsapp":  return Color(red: 0.145, green: 0.827, blue: 0.400) // #25D366
        case "linkedin":  return Color(red: 0.039, green: 0.400, blue: 0.761) // #0A66C2
        case "tiktok":    return .primary
        case "twitter":   return .primary
        case "telegram":  return Color(red: 0.133, green: 0.620, blue: 0.851) // #229ED9
        default:          return .blue
        }
    }

    /// The stored handle trimmed and with a leading "@" stripped — the form
    /// every profile URL is built from (and the honest thing to display).
    var sanitizedHandle: String {
        var h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("@") { h.removeFirst() }
        return h
    }

    /// wa.me only resolves phone numbers, never usernames — a link built
    /// from anything else would be a lie. Digits plus common phone
    /// punctuation, with enough digits to plausibly dial.
    var isPhoneLikeHandle: Bool {
        let h = sanitizedHandle
        guard h.filter(\.isNumber).count >= 6 else { return false }
        return h.allSatisfy { $0.isNumber || "+ ()-.".contains($0) }
    }

    /// Web profile URL for the saved handle. Deliberately https (not the
    /// app's custom scheme): universal links route into the installed app
    /// anyway, and the browser is an honest fallback when it isn't there.
    /// nil when no truthful destination exists — an empty handle, or a
    /// WhatsApp value that isn't a phone number — so callers must render
    /// those entries as non-tappable.
    var openURL: URL? {
        let h = sanitizedHandle
        guard !h.isEmpty,
              let enc = h.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        switch platform {
        case "instagram": return URL(string: "https://instagram.com/\(enc)")
        case "facebook":  return URL(string: "https://facebook.com/\(enc)")
        case "whatsapp":
            guard isPhoneLikeHandle else { return nil }
            return URL(string: "https://wa.me/\(h.filter { $0.isNumber })")
        case "linkedin":  return URL(string: "https://linkedin.com/in/\(enc)")
        case "tiktok":    return URL(string: "https://tiktok.com/@\(enc)")
        case "twitter":   return URL(string: "https://x.com/\(enc)")
        case "telegram":  return URL(string: "https://t.me/\(enc)")
        default:
            // "other" platforms: only a value that is (or clearly wants to
            // be) a web address earns a link.
            let lower = h.lowercased()
            if lower.hasPrefix("https://") || lower.hasPrefix("http://") { return URL(string: h) }
            if h.contains("."), !h.contains(" ") { return URL(string: "https://\(h)") }
            return nil
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

    /// The family core — the roster roles that belong to the property-wide
    /// family chat. Outsiders (tenants, guests, service providers, plain
    /// contacts) keep to their own DMs and groups; the server's
    /// has_family_access() gate mirrors this, so the group-info roster must
    /// never show anyone the chat itself excludes.
    var isFamilyCore: Bool {
        ["owner", "partner", "member", "teen", "child"].contains(role)
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

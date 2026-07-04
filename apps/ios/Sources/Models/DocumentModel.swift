import Foundation

struct DocumentModel: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var description: String?
    var category: String
    var fileUrl: String
    var fileName: String
    var fileSize: Int64?
    var mimeType: String?
    var expiresAt: String?
    var isCritical: Bool
    var tags: [String]
    var elementId: UUID?
    let createdAt: String
    var sharedMemberIds: [String] = []   // family_members.id shared this doc with (see migration 094)

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, tags
        case propertyId  = "property_id"
        case fileUrl     = "file_url"
        case fileName    = "file_name"
        case fileSize    = "file_size"
        case mimeType    = "mime_type"
        case expiresAt   = "expires_at"
        case isCritical  = "is_critical"
        case elementId   = "element_id"
        case createdAt   = "created_at"
        case sharedMemberIds = "shared_member_ids"
    }

    var categoryIcon: String {
        switch category {
        case "warranty":    return "checkmark.seal.fill"
        case "contract":    return "doc.text.fill"
        case "legal":       return "building.columns.fill"
        case "insurance":   return "shield.fill"
        case "certificate": return "rosette"
        case "manual":      return "book.fill"
        case "invoice":     return "receipt.fill"
        case "permit":      return "checkmark.shield.fill"
        case "tax":         return "percent"
        case "utility":     return "bolt.fill"
        case "photo":       return "photo.fill"
        default:            return "doc.fill"
        }
    }

    var fileSizeDisplay: String {
        guard let size = fileSize else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    var expiresDisplay: String? {
        guard let ds = expiresAt else { return nil }
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        guard let d = iso.date(from: ds) else { return ds }
        let out = DateFormatter(); out.dateFormat = "d MMM yyyy"
        return out.string(from: d)
    }

    var isExpiringSoon: Bool {
        guard let ds = expiresAt else { return false }
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        guard let d = iso.date(from: ds) else { return false }
        return d < (Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
    }
}

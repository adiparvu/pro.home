import Foundation

/// The rich-record fields the D1 dynamic form collects, bundled so the
/// service's `add`/`update` stay readable instead of taking 25 arguments.
struct DocumentExtra: Encodable, Equatable {
    var subcategory: String?
    var priority: String = "normal"
    var issuedAt: String?
    var renewAt: String?
    var notifyAt: String?
    var issuerCompany: String?
    var issuerContact: String?
    var issuerPhone: String?
    var issuerEmail: String?
    var issuerWebsite: String?
    var clientNumber: String?
    var docNumber: String?
    var series: String?
    var contractCode: String?
    var clientCode: String?
    var fiscalCode: String?
    var policyNumber: String?
    var barcode: String?
    var value: Double?
    var currency: String?
    var vat: Double?
    var recurrence: String?
    var tags: [String] = []

    enum CodingKeys: String, CodingKey {
        case subcategory, priority, series, barcode, value, vat, recurrence, currency, tags
        case issuedAt      = "issued_at"
        case renewAt       = "renew_at"
        case notifyAt      = "notify_at"
        case issuerCompany = "issuer_company"
        case issuerContact = "issuer_contact"
        case issuerPhone   = "issuer_phone"
        case issuerEmail   = "issuer_email"
        case issuerWebsite = "issuer_website"
        case clientNumber  = "client_number"
        case docNumber     = "doc_number"
        case contractCode  = "contract_code"
        case clientCode    = "client_code"
        case fiscalCode    = "fiscal_code"
        case policyNumber  = "policy_number"
    }
}

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

    // ── Document Intelligence (migration 121, phase D1) ──────────────────────
    // The rich record the dynamic per-category form fills. All optional so
    // pre-121 rows and older clients decode unchanged.
    var subcategory: String?
    var priority: String?                // normal/important/critical/urgent
    var issuedAt: String?
    var renewAt: String?
    var notifyAt: String?
    var issuerCompany: String?
    var issuerContact: String?
    var issuerPhone: String?
    var issuerEmail: String?
    var issuerWebsite: String?
    var clientNumber: String?
    var docNumber: String?
    var series: String?
    var contractCode: String?
    var clientCode: String?
    var fiscalCode: String?
    var policyNumber: String?
    var barcode: String?
    var value: Double?
    var currency: String?
    var vat: Double?
    var recurrence: String?              // one-off/monthly/quarterly/yearly

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, tags, series, barcode, value, vat, priority, recurrence, currency
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
        case subcategory
        case issuedAt      = "issued_at"
        case renewAt       = "renew_at"
        case notifyAt      = "notify_at"
        case issuerCompany = "issuer_company"
        case issuerContact = "issuer_contact"
        case issuerPhone   = "issuer_phone"
        case issuerEmail   = "issuer_email"
        case issuerWebsite = "issuer_website"
        case clientNumber  = "client_number"
        case docNumber     = "doc_number"
        case contractCode  = "contract_code"
        case clientCode    = "client_code"
        case fiscalCode    = "fiscal_code"
        case policyNumber  = "policy_number"
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
        guard let d = AppDate.day(from: ds) else { return ds }
        return AppDate.monthDayYear.string(from: d)
    }

    var isExpiringSoon: Bool {
        guard let ds = expiresAt, let d = AppDate.day(from: ds) else { return false }
        return d < (Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
    }
}

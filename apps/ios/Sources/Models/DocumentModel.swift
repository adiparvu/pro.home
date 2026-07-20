import Foundation

/// The rich-record fields the D1 dynamic form collects, bundled so the
/// service's `add`/`update` stay readable instead of taking 25 arguments.
struct DocumentExtra: Encodable, Equatable {
    var subcategory: String?
    var description: String?
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
        case subcategory, description, priority, series, barcode, value, vat, recurrence, currency, tags
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

    // ── Security + search (migration 132, phase D6) ──────────────────────────
    // All optional so pre-132 rows and older cached JSON decode unchanged.
    var readOnly: Bool?                  // read-only lock (client + DB guard)
    var hiddenFromFamily: Bool?          // owner-only visibility (RLS)
    var uploadedBy: String?              // profiles.id of the creator (= auth uid)
    var ocrText: String?                 // recognized text, for keyword search

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
        case readOnly          = "read_only"
        case hiddenFromFamily  = "hidden_from_family"
        case uploadedBy        = "uploaded_by"
        case ocrText           = "ocr_text"
    }

    /// Non-optional views over the D6 security flags.
    var isReadOnly: Bool { readOnly ?? false }
    var isHiddenFromFamily: Bool { hiddenFromFamily ?? false }

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

    /// Whole calendar days until the expiry day: 0 = expires today, negative =
    /// already expired, nil = no expiry date. Drives the visible expiry chip.
    var daysUntilExpiry: Int? {
        guard let ds = expiresAt, let d = AppDate.day(from: ds) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: d)).day
    }

    /// The glyph for the document's primary file (PDF / image / generic).
    var fileGlyph: String {
        if mimeType == "application/pdf" { return "doc.richtext.fill" }
        if mimeType?.hasPrefix("image/") == true { return "photo.fill" }
        return "doc.fill"
    }
}

// MARK: - Localized document type names
//
// Categories are STORED as fixed English tokens ("invoice", "warranty", …) —
// that never changes. Display goes through this one mapping so the type badge,
// pickers, filters and detail header all say "Factură" on a Romanian device
// instead of leaking the raw stored value.
enum DocumentTypeDisplay {
    static func name(_ category: String) -> String {
        switch category {
        case "warranty":    return String(localized: "doc_type_warranty")
        case "contract":    return String(localized: "doc_type_contract")
        case "legal":       return String(localized: "doc_type_legal")
        case "insurance":   return String(localized: "doc_type_insurance")
        case "certificate": return String(localized: "doc_type_certificate")
        case "manual":      return String(localized: "doc_type_manual")
        case "invoice":     return String(localized: "doc_type_invoice")
        case "permit":      return String(localized: "doc_type_permit")
        case "tax":         return String(localized: "doc_type_tax")
        case "utility":     return String(localized: "doc_type_utility")
        case "photo":       return String(localized: "doc_type_photo")
        default:            return String(localized: "doc_type_other")
        }
    }
}

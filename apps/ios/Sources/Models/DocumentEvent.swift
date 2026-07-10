import Foundation

/// One entry in a document's history timeline (Document Intelligence D5).
///
/// Events are append-only and logged at the honest moment an action actually
/// happens (created / edited / a file added or removed / opened for viewing).
/// `details` is a small, flat context bag — kept as `[String: String]?` so the
/// model stays trivially Codable without an AnyCodable dependency.
struct DocumentEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let documentId: UUID
    let kind: String
    let actorId: UUID?
    let details: [String: String]?
    let at: String

    enum CodingKeys: String, CodingKey {
        case id, kind, details, at
        case documentId = "document_id"
        case actorId    = "actor_id"
    }

    /// The known event kinds. `kindEnum` resolves the stored string; an
    /// unrecognised value (a newer client wrote it) falls back to `.other`,
    /// so the row still renders rather than being dropped.
    enum Kind: String {
        case created, edited, viewed, shared, downloaded
        case expired, renewed
        case fileAdded    = "file_added"
        case fileRemoved  = "file_removed"
        case replaced     = "replaced"
        case other

        var icon: String {
            switch self {
            case .created:     return "plus"
            case .edited:      return "pencil"
            case .viewed:      return "eye"
            case .shared:      return "person.2"
            case .downloaded:  return "arrow.down"
            case .expired:     return "exclamationmark"
            case .renewed:     return "arrow.triangle.2.circlepath"
            case .fileAdded:   return "paperclip"
            case .fileRemoved: return "trash"
            case .replaced:    return "arrow.2.squarepath"
            case .other:       return "clock"
            }
        }

        /// Localization key for the event's label (RO source / EN).
        var labelKey: String {
            switch self {
            case .created:     return "doc_evt_created"
            case .edited:      return "doc_evt_edited"
            case .viewed:      return "doc_evt_viewed"
            case .shared:      return "doc_evt_shared"
            case .downloaded:  return "doc_evt_downloaded"
            case .expired:     return "doc_evt_expired"
            case .renewed:     return "doc_evt_renewed"
            case .fileAdded:   return "doc_evt_file_added"
            case .fileRemoved: return "doc_evt_file_removed"
            case .replaced:    return "doc_evt_replaced"
            case .other:       return "doc_evt_other"
            }
        }
    }

    var kindEnum: Kind { Kind(rawValue: kind) ?? .other }
    var icon: String { kindEnum.icon }
    var labelKey: String { kindEnum.labelKey }

    /// The event instant parsed from the server `timestamptz`.
    var date: Date? { AppDate.timestamp(from: at) }

    /// The per-field diff carried by an "edited" event, in canonical field
    /// order. Empty for events written before diffs existed — those rows keep
    /// rendering exactly as they always did.
    var fieldChanges: [DocumentFieldChange] { DocumentFieldChange.parse(details) }
}

// MARK: - Per-field change (what an edit actually modified)
//
// Diffs ride in the existing `document_events.details` jsonb column (migration
// 127) as a flat string map, keeping `DocumentEvent` trivially Codable:
//
//     "chg:<field>:old" → the value before the edit ("" when it was unset)
//     "chg:<field>:new" → the value after the edit  ("" when it was cleared)
//
// `<field>` is the documents-table column name (issuer_company, value, …), so
// stored history stays raw and language-neutral; localization happens only at
// display time.
struct DocumentFieldChange: Identifiable, Hashable {
    let field: String
    let old: String
    let new: String
    var id: String { field }

    /// Stable display order — mirrors the form's own top-to-bottom order.
    static let canonicalOrder: [String] = [
        "name", "category", "subcategory", "priority", "description", "tags",
        "issued_at", "expires_at", "renew_at", "notify_at",
        "issuer_company", "issuer_contact", "issuer_phone", "issuer_email",
        "issuer_website", "client_number",
        "doc_number", "series", "contract_code", "client_code", "fiscal_code",
        "policy_number", "barcode",
        "value", "currency", "vat", "recurrence",
    ]

    /// Encodes a diff between two document snapshots as details entries.
    /// Returns only the `chg:` pairs; the caller merges its own context keys.
    static func encode(old: DocumentModel, new: DocumentModel) -> [String: String] {
        var details: [String: String] = [:]
        func put(_ field: String, _ o: String?, _ n: String?) {
            let ov = o ?? "", nv = n ?? ""
            guard ov != nv else { return }
            details["chg:\(field):old"] = ov
            details["chg:\(field):new"] = nv
        }
        func num(_ v: Double?) -> String? {
            guard let v else { return nil }
            return v.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(v)) : String(format: "%.2f", v)
        }
        put("name", old.name, new.name)
        put("category", old.category, new.category)
        put("subcategory", old.subcategory, new.subcategory)
        put("priority", old.priority, new.priority)
        put("description", old.description, new.description)
        put("tags", old.tags.joined(separator: ", "), new.tags.joined(separator: ", "))
        put("issued_at", old.issuedAt, new.issuedAt)
        put("expires_at", old.expiresAt, new.expiresAt)
        put("renew_at", old.renewAt, new.renewAt)
        put("notify_at", old.notifyAt, new.notifyAt)
        put("issuer_company", old.issuerCompany, new.issuerCompany)
        put("issuer_contact", old.issuerContact, new.issuerContact)
        put("issuer_phone", old.issuerPhone, new.issuerPhone)
        put("issuer_email", old.issuerEmail, new.issuerEmail)
        put("issuer_website", old.issuerWebsite, new.issuerWebsite)
        put("client_number", old.clientNumber, new.clientNumber)
        put("doc_number", old.docNumber, new.docNumber)
        put("series", old.series, new.series)
        put("contract_code", old.contractCode, new.contractCode)
        put("client_code", old.clientCode, new.clientCode)
        put("fiscal_code", old.fiscalCode, new.fiscalCode)
        put("policy_number", old.policyNumber, new.policyNumber)
        put("barcode", old.barcode, new.barcode)
        put("value", num(old.value), num(new.value))
        put("currency", old.currency, new.currency)
        put("vat", num(old.vat), num(new.vat))
        put("recurrence", old.recurrence, new.recurrence)
        return details
    }

    /// Reads the `chg:` pairs back out of a details bag, canonically ordered.
    /// Unknown fields (written by a newer client) sort after the known ones so
    /// they still render rather than being dropped.
    static func parse(_ details: [String: String]?) -> [DocumentFieldChange] {
        guard let details else { return [] }
        var byField: [String: (old: String?, new: String?)] = [:]
        for (key, value) in details where key.hasPrefix("chg:") {
            let parts = key.split(separator: ":").map(String.init)
            guard parts.count == 3 else { continue }
            var entry = byField[parts[1]] ?? (nil, nil)
            if parts[2] == "old" { entry.old = value } else if parts[2] == "new" { entry.new = value }
            byField[parts[1]] = entry
        }
        let known = canonicalOrder.compactMap { field -> DocumentFieldChange? in
            guard let e = byField.removeValue(forKey: field) else { return nil }
            return DocumentFieldChange(field: field, old: e.old ?? "", new: e.new ?? "")
        }
        let unknown = byField
            .map { DocumentFieldChange(field: $0.key, old: $0.value.old ?? "", new: $0.value.new ?? "") }
            .sorted { $0.field < $1.field }
        return known + unknown
    }

    /// Localized field label ("Companie", "Valoare", …). Reuses the form's
    /// doc_f_* strings so history and editor always agree on terminology.
    var label: String {
        switch field {
        case "name":           return String(localized: "doc_f_name")
        case "category":       return String(localized: "doc_f_category")
        case "subcategory":    return String(localized: "doc_f_subcategory")
        case "priority":       return String(localized: "doc_f_priority")
        case "description":    return String(localized: "doc_f_description")
        case "tags":           return String(localized: "doc_f_tags")
        case "issued_at":      return String(localized: "doc_f_issued")
        case "expires_at":     return String(localized: "doc_f_expires")
        case "renew_at":       return String(localized: "doc_f_renew")
        case "notify_at":      return String(localized: "doc_f_notify")
        case "issuer_company": return String(localized: "doc_f_company")
        case "issuer_contact": return String(localized: "doc_f_contact")
        case "issuer_phone":   return String(localized: "doc_f_phone")
        case "issuer_email":   return String(localized: "doc_f_email")
        case "issuer_website": return String(localized: "doc_f_website")
        case "client_number":  return String(localized: "doc_f_client_number")
        case "doc_number":     return String(localized: "doc_f_number")
        case "series":         return String(localized: "doc_f_series")
        case "contract_code":  return String(localized: "doc_f_contract_code")
        case "client_code":    return String(localized: "doc_f_client_code")
        case "fiscal_code":    return String(localized: "doc_f_fiscal_code")
        case "policy_number":  return String(localized: "doc_f_policy")
        case "barcode":        return String(localized: "doc_f_barcode")
        case "value":          return String(localized: "doc_f_value")
        case "currency":       return String(localized: "doc_f_currency")
        case "vat":            return String(localized: "doc_f_vat")
        case "recurrence":     return String(localized: "doc_f_recurrence")
        default:               return field
        }
    }

    var oldDisplay: String { Self.display(old, field: field) }
    var newDisplay: String { Self.display(new, field: field) }

    /// Stored raw values rendered for humans: dates in the user's locale,
    /// enum tokens through their localized labels, empty as "—".
    private static func display(_ raw: String, field: String) -> String {
        guard !raw.isEmpty else { return "—" }
        switch field {
        case "issued_at", "expires_at", "renew_at", "notify_at":
            guard let d = AppDate.day(from: raw) else { return raw }
            return AppDate.monthDayYear.string(from: d)
        case "category":   return DocumentTypeDisplay.name(raw)
        case "priority":   return DocPriority.text(raw)
        case "recurrence": return DocRecurrence.text(raw)
        default:           return raw
        }
    }
}

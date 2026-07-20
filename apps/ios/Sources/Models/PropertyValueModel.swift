import Foundation

// MARK: - Typed valuation source
//
// New entries store one of these stable raw tokens in `source`; display maps
// through the string catalog (RO/EN). Legacy rows hold free text — often the
// hardcoded English "Manual estimate" regardless of device language (the
// localization defect this type retires). `match` is the display-side
// migration: it recognizes every string the app itself ever wrote (the raw
// tokens, the old English suggestion chips, their Romanian catalog values and
// the property form's purchase/estimate strings). Anything unrecognized keeps
// displaying verbatim; database rows are never rewritten.
enum PropertyValueSource: String, CaseIterable, Identifiable {
    case manual, bank, agent, purchase, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:   return String(localized: "prop_value_source_manual")
        case .bank:     return String(localized: "prop_value_source_bank")
        case .agent:    return String(localized: "prop_value_source_agent")
        case .purchase: return String(localized: "prop_value_source_purchase")
        case .other:    return String(localized: "prop_value_source_other")
        }
    }

    var icon: String {
        switch self {
        case .manual:   return "pencil.and.ruler.fill"
        case .bank:     return "building.columns.fill"
        case .agent:    return "person.text.rectangle.fill"
        case .purchase: return "key.fill"
        case .other:    return "tag.fill"
        }
    }

    /// Maps a stored `source` string to its typed case, or nil for free text
    /// the app never wrote itself (shown verbatim by callers).
    static func match(_ raw: String?) -> PropertyValueSource? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "manual", "manual estimate", "estimare manuală",
             "owner estimate", "estimare proprietar":
            return .manual
        case "bank", "bank appraisal", "evaluare bancară":
            return .bank
        case "agent", "real estate agent", "agent imobiliar":
            return .agent
        case "purchase", "purchase price", "preț de achiziție":
            return .purchase
        case "other":
            return .other
        default:
            return nil
        }
    }
}

struct PropertyValueEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var valueAmount: Double
    var currency: String
    var source: String?
    var notes: String?
    var enteredAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId   = "property_id"
        case ownerId      = "owner_id"
        case valueAmount  = "value_amount"
        case currency, source, notes
        case enteredAt    = "entered_at"
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoShort: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var enteredDate: Date? {
        PropertyValueEntry.isoFull.date(from: enteredAt)
            ?? PropertyValueEntry.isoShort.date(from: enteredAt)
    }

    /// The typed source when the stored string is one the app ever wrote.
    var typedSource: PropertyValueSource? { PropertyValueSource.match(source) }

    /// What the UI shows for the source: the typed case's localized name,
    /// otherwise the stored free text verbatim. Nil when there is no source.
    var sourceDisplay: String? {
        if let typed = typedSource { return typed.displayName }
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Glyph for the source; free-text sources get the generic document mark.
    var sourceIcon: String { typedSource?.icon ?? "doc.text.fill" }
}

struct NewPropertyValuePayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let valueAmount: Double
    let currency: String
    let source: String?
    let notes: String?
    let enteredAt: String

    enum CodingKeys: String, CodingKey {
        case propertyId  = "property_id"
        case ownerId     = "owner_id"
        case valueAmount = "value_amount"
        case currency, source, notes
        case enteredAt   = "entered_at"
    }
}

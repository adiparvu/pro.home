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
            case .other:       return "doc_evt_other"
            }
        }
    }

    var kindEnum: Kind { Kind(rawValue: kind) ?? .other }
    var icon: String { kindEnum.icon }
    var labelKey: String { kindEnum.labelKey }

    /// The event instant parsed from the server `timestamptz`.
    var date: Date? { AppDate.timestamp(from: at) }
}

import Foundation

/// One attachment on a document (D2). A document's primary file stays on
/// `DocumentModel.fileUrl`; these are the additional pages, scans, receipts
/// and photos that belong to the same record. Stored in the private
/// `documents` bucket, read through signed URLs.
struct DocumentFile: Identifiable, Codable, Hashable {
    let id: UUID
    let documentId: UUID
    var url: String                 // storage path in the `documents` bucket
    var name: String
    var kind: String                // photo / pdf / scan / file
    var mimeType: String?
    var size: Int64?
    var pageCount: Int?
    var version: Int
    let createdAt: String

    // ── Versioning (migration 129, phase D5 part 2) ─────────────────────────
    // Files that occupy the same logical slot share a `versionGroup`; the
    // newest is "current", older ones carry `supersededAt`/`supersededBy`.
    // All optional so pre-129 rows and older clients decode unchanged.
    var versionGroup: UUID?
    var supersededAt: String?
    var supersededBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, url, name, kind, version
        case documentId = "document_id"
        case mimeType   = "mime_type"
        case size
        case pageCount  = "page_count"
        case createdAt  = "created_at"
        case versionGroup = "version_group"
        case supersededAt = "superseded_at"
        case supersededBy = "superseded_by"
    }

    /// The logical slot this file belongs to (its own id when never grouped).
    var groupId: UUID { versionGroup ?? id }

    /// A file the user replaced — hidden from the top-level list, kept as history.
    var isSuperseded: Bool { supersededAt != nil }

    /// "v3" — the version label shown on rows that carry history.
    var versionLabel: String { "v\(version)" }

    var glyph: String {
        switch kind {
        case "photo": return "photo.fill"
        case "pdf":   return "doc.richtext.fill"
        case "scan":  return "doc.viewfinder.fill"
        default:
            if mimeType == "application/pdf" { return "doc.richtext.fill" }
            if mimeType?.hasPrefix("image/") == true { return "photo.fill" }
            return "doc.fill"
        }
    }

    var sizeDisplay: String {
        guard let size else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    var isPreviewable: Bool {
        mimeType == "application/pdf" || mimeType?.hasPrefix("image/") == true
    }
}

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

    enum CodingKeys: String, CodingKey {
        case id, url, name, kind, version
        case documentId = "document_id"
        case mimeType   = "mime_type"
        case size
        case pageCount  = "page_count"
        case createdAt  = "created_at"
    }

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

import Foundation

// A note attached to a property element. When `isLocked`, `body` holds an
// AES-GCM encrypted blob (base64) produced by NoteLockManager; otherwise it is
// plain text.

struct ElementNote: Identifiable, Codable, Equatable {
    let id: UUID
    let elementId: UUID
    let propertyId: UUID
    var body: String
    var isLocked: Bool
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case elementId  = "element_id"
        case propertyId = "property_id"
        case isLocked   = "is_locked"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}

struct NewElementNote: Encodable {
    let elementId: UUID
    let propertyId: UUID
    var body: String
    var isLocked: Bool
    enum CodingKeys: String, CodingKey {
        case body
        case elementId  = "element_id"
        case propertyId = "property_id"
        case isLocked   = "is_locked"
    }
}

struct ElementNoteUpdate: Encodable {
    var body: String
    var isLocked: Bool
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case body
        case isLocked  = "is_locked"
        case updatedAt = "updated_at"
    }
}

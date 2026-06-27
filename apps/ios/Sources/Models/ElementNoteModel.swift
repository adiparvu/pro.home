import Foundation

// A note attached to a property element. When `isLocked`, `body` holds an
// AES-GCM encrypted blob (base64) produced by NoteLockManager; otherwise it is
// plain text.

struct ChecklistItem: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var done: Bool = false
}

struct ElementNote: Identifiable, Codable, Equatable {
    let id: UUID
    let elementId: UUID
    let propertyId: UUID
    var body: String
    var isLocked: Bool
    var checklist: [ChecklistItem]
    var photoUrls: [String]
    let createdAt: String
    var updatedAt: String

    var photos: [String] { photoUrls }
    var checklistProgress: (done: Int, total: Int) {
        (checklist.filter(\.done).count, checklist.count)
    }

    enum CodingKeys: String, CodingKey {
        case id, body, checklist
        case elementId  = "element_id"
        case propertyId = "property_id"
        case isLocked   = "is_locked"
        case photoUrls  = "photo_urls"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        elementId = try c.decode(UUID.self, forKey: .elementId)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        photoUrls = try c.decodeIfPresent([String].self, forKey: .photoUrls) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct NewElementNote: Encodable {
    let elementId: UUID
    let propertyId: UUID
    var body: String
    var isLocked: Bool
    var checklist: [ChecklistItem]
    var photoUrls: [String]
    enum CodingKeys: String, CodingKey {
        case body, checklist
        case elementId  = "element_id"
        case propertyId = "property_id"
        case isLocked   = "is_locked"
        case photoUrls  = "photo_urls"
    }
}

struct ElementNoteUpdate: Encodable {
    var body: String
    var isLocked: Bool
    var checklist: [ChecklistItem]
    var photoUrls: [String]
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case body, checklist
        case isLocked  = "is_locked"
        case photoUrls = "photo_urls"
        case updatedAt = "updated_at"
    }
}

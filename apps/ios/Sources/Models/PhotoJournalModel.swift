import Foundation

struct PhotoJournalEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var zoneId: UUID?
    var title: String
    var caption: String?
    var photoUrl: String
    var takenAt: String
    var tags: [String]?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case zoneId     = "zone_id"
        case title, caption, tags
        case photoUrl   = "photo_url"
        case takenAt    = "taken_at"
        case createdAt  = "created_at"
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

    var takenDate: Date? {
        PhotoJournalEntry.isoFull.date(from: takenAt)
            ?? PhotoJournalEntry.isoShort.date(from: takenAt)
    }
}

struct NewPhotoJournalPayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let zoneId: UUID?
    let title: String
    let caption: String?
    let photoUrl: String
    let takenAt: String
    let tags: [String]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case zoneId     = "zone_id"
        case title, caption, tags
        case photoUrl   = "photo_url"
        case takenAt    = "taken_at"
        case createdAt  = "created_at"
    }
}

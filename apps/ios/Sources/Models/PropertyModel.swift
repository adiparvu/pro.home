import Foundation

struct PropertyModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var addressLine1: String
    var city: String
    var country: String
    var propertyType: String
    var sizeSqm: Double?
    var numRooms: Int?
    var postalCode: String?
    var healthScore: Int?
    var latitude: Double?
    var longitude: Double?
    // Rich profile
    var photoUrl: String?
    var yearBuilt: Int?
    var story: String?
    var renovations: [Renovation]?
    var owners: [OwnerRecord]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, city, country, latitude, longitude, story, owners, renovations
        case addressLine1 = "address_line1"
        case postalCode = "postal_code"
        case propertyType = "property_type"
        case sizeSqm = "size_sqm"
        case numRooms = "num_rooms"
        case healthScore = "health_score"
        case photoUrl = "photo_url"
        case yearBuilt = "year_built"
        case createdAt = "created_at"
    }
}

struct Renovation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var yearFrom: Int
    var yearTo: Int?
    var title: String

    var yearRange: String {
        if let to = yearTo, to != yearFrom { return "\(yearFrom)–\(to)" }
        return "\(yearFrom)"
    }
}

struct OwnerRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var yearFrom: Int
    var yearTo: Int?

    var yearRange: String {
        if let to = yearTo { return "\(yearFrom)–\(to)" }
        return "\(yearFrom)–\(String(localized: "present"))"
    }
}

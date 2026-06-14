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
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, city, country, latitude, longitude
        case addressLine1 = "address_line1"
        case postalCode = "postal_code"
        case propertyType = "property_type"
        case sizeSqm = "size_sqm"
        case numRooms = "num_rooms"
        case healthScore = "health_score"
        case createdAt = "created_at"
    }
}

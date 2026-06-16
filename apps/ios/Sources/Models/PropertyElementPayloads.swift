import Foundation

// MARK: - Write payloads

struct NewPropertyElement: Encodable {
    let propertyId: UUID
    var name: String
    var elementType: String
    var description: String?
    var positionX: Double
    var positionY: Double
    var healthScore: Int
    var technicalCondition: String
    var estimatedValue: Double?
    var valueCurrency: String
    var purchaseDate: String?
    var warrantyUntil: String?
    var brand: String?
    var model: String?
    var serialNumber: String?
    var notes: String?
    var layer: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    var zoneId: UUID? = nil
    var photoUrls: [String]? = nil
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, description, brand, model, notes, layer, latitude, longitude
        case photoUrls         = "photo_urls"
        case propertyId        = "property_id"
        case elementType       = "element_type"
        case positionX         = "position_x"
        case positionY         = "position_y"
        case healthScore       = "health_score"
        case technicalCondition = "technical_condition"
        case estimatedValue    = "estimated_value"
        case valueCurrency     = "value_currency"
        case purchaseDate      = "purchase_date"
        case warrantyUntil     = "warranty_until"
        case serialNumber      = "serial_number"
        case zoneId            = "zone_id"
        case updatedAt         = "updated_at"
    }
}

struct ElementGeoUpdate: Encodable {
    var latitude: Double?
    var longitude: Double?
    var zoneId: UUID?
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case zoneId    = "zone_id"
        case updatedAt = "updated_at"
    }
}

struct ElementPhotosUpdate: Encodable {
    var photoUrls: [String]
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case photoUrls = "photo_urls"
        case updatedAt = "updated_at"
    }
}

struct ElementPositionUpdate: Encodable {
    var positionX: Double
    var positionY: Double
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case positionX = "position_x"
        case positionY = "position_y"
        case updatedAt = "updated_at"
    }
}

struct ElementHealthUpdate: Encodable {
    var healthScore: Int
    var technicalCondition: String
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case healthScore        = "health_score"
        case technicalCondition = "technical_condition"
        case updatedAt          = "updated_at"
    }
}

struct NewElementRecord: Encodable {
    let elementId: UUID
    let propertyId: UUID
    var recordType: String
    var title: String
    var content: String?
    var cost: Double?
    var currency: String
    var recordDate: String
    var performedBy: String?
    var nextActionDate: String?

    enum CodingKeys: String, CodingKey {
        case title, content, currency, cost
        case elementId      = "element_id"
        case propertyId     = "property_id"
        case recordType     = "record_type"
        case performedBy    = "performed_by"
        case recordDate     = "record_date"
        case nextActionDate = "next_action_date"
    }
}

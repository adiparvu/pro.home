import Foundation

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

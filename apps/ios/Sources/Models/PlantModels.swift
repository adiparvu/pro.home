import SwiftUI

// MARK: - Plant

struct Plant: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var name: String
    var species: String?
    var location: String?
    var lastWateredAt: String?
    var wateringIntervalDays: Int
    var healthStatus: String
    var notes: String?
    var emoji: String
    var photoUrl: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case name, species, location
        case lastWateredAt        = "last_watered_at"
        case wateringIntervalDays = "watering_interval_days"
        case healthStatus         = "health_status"
        case notes, emoji
        case photoUrl  = "photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: Computed

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoShort: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    private func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        return Plant.isoFull.date(from: str) ?? Plant.isoShort.date(from: str)
    }

    var needsWatering: Bool {
        guard let last = parseDate(lastWateredAt) else { return true }
        let next = Calendar.current.date(byAdding: .day, value: wateringIntervalDays, to: last) ?? last
        return next <= Date()
    }

    var daysUntilWatering: Int {
        guard let last = parseDate(lastWateredAt) else { return -wateringIntervalDays }
        let next = Calendar.current.date(byAdding: .day, value: wateringIntervalDays, to: last) ?? last
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: next)).day ?? 0
    }

    var healthColor: Color {
        switch healthStatus {
        case "great":       return Color(red: 0.15, green: 0.80, blue: 0.4)
        case "good":        return Color(red: 0.25, green: 0.72, blue: 0.35)
        case "needs_water": return Color(red: 1.0,  green: 0.62, blue: 0.1)
        case "critical":    return .red
        default:            return .gray
        }
    }

    var healthIcon: String {
        switch healthStatus {
        case "great":       return "checkmark.circle.fill"
        case "good":        return "leaf.fill"
        case "needs_water": return "drop.fill"
        case "critical":    return "exclamationmark.triangle.fill"
        default:            return "leaf.fill"
        }
    }

    var wateringLabel: String {
        if needsWatering { return "Are nevoie de apă" }
        let d = daysUntilWatering
        if d == 0 { return "Udă azi" }
        if d == 1 { return "Udă mâine" }
        return "Peste \(d) zile"
    }

    var lastWateredDisplay: String {
        guard let d = parseDate(lastWateredAt) else { return "Niciodată" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Azi" }
        if cal.isDateInYesterday(d) { return "Ieri" }
        let fmt = DateFormatter(); fmt.dateFormat = "d MMM"
        return fmt.string(from: d)
    }

    static let emojiOptions = ["🌿","🌱","🌸","🌺","🌻","🌹","🌷","🌵","🪴","🌾","🍀","🍃","🌳","🌲","🌊","🪸"]

    static let healthOptions: [(id: String, label: String)] = [
        ("great",       "Excelent"),
        ("good",        "Bine"),
        ("needs_water", "Nevoie de apă"),
        ("critical",    "Critic"),
    ]
}

// MARK: - Payloads

struct NewPlantPayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let name: String
    let species: String?
    let location: String?
    let wateringIntervalDays: Int
    let healthStatus: String
    let notes: String?
    let emoji: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case name, species, location
        case wateringIntervalDays = "watering_interval_days"
        case healthStatus         = "health_status"
        case notes, emoji
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlantUpdate: Encodable {
    let name: String
    let species: String?
    let location: String?
    let wateringIntervalDays: Int
    let healthStatus: String
    let notes: String?
    let emoji: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, species, location
        case wateringIntervalDays = "watering_interval_days"
        case healthStatus         = "health_status"
        case notes, emoji
        case updatedAt = "updated_at"
    }
}

struct PlantWateringUpdate: Encodable {
    let lastWateredAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case lastWateredAt = "last_watered_at"
        case updatedAt     = "updated_at"
    }
}

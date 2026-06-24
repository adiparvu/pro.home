import SwiftUI

enum ApplianceCategory: String, CaseIterable, Codable {
    case hvac
    case kitchen
    case laundry
    case bathroom
    case security
    case entertainment
    case other

    var displayName: LocalizedStringKey {
        switch self {
        case .hvac:          return "HVAC"
        case .kitchen:       return "Kitchen"
        case .laundry:       return "Laundry"
        case .bathroom:      return "Bathroom"
        case .security:      return "Security"
        case .entertainment: return "Entertainment"
        case .other:         return "Other"
        }
    }

    var icon: String {
        switch self {
        case .hvac:          return "thermometer.medium"
        case .kitchen:       return "fork.knife"
        case .laundry:       return "washer.fill"
        case .bathroom:      return "shower.fill"
        case .security:      return "lock.shield.fill"
        case .entertainment: return "tv.fill"
        case .other:         return "wrench.and.screwdriver.fill"
        }
    }
}

struct Appliance: Identifiable, Codable, Equatable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var name: String
    var brand: String?
    var modelNumber: String?
    var serialNumber: String?
    var location: String?
    var category: ApplianceCategory
    var purchaseDate: String?
    var warrantyUntil: String?
    var purchasePrice: Double?
    var notes: String?
    var photoUrl: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId    = "property_id"
        case ownerId       = "owner_id"
        case name, brand, location, category, notes
        case modelNumber   = "model_number"
        case serialNumber  = "serial_number"
        case purchaseDate  = "purchase_date"
        case warrantyUntil = "warranty_until"
        case purchasePrice = "purchase_price"
        case photoUrl      = "photo_url"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
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
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        return Appliance.isoFull.date(from: str)
            ?? Appliance.isoShort.date(from: str)
            ?? Appliance.dateOnly.date(from: str)
    }

    var isWarrantyExpired: Bool {
        guard let d = parseDate(warrantyUntil) else { return false }
        return d < Date()
    }

    var isWarrantyExpiringSoon: Bool {
        guard let d = parseDate(warrantyUntil) else { return false }
        let threshold = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        return d >= Date() && d <= threshold
    }

    var warrantyStatus: String {
        guard let d = parseDate(warrantyUntil) else { return String(localized: "No Warranty") }
        if d < Date() { return String(localized: "Expired") }
        let threshold = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        if d <= threshold { return String(localized: "Expiring Soon") }
        return String(localized: "Active")
    }

    var warrantyColor: Color {
        guard let d = parseDate(warrantyUntil) else { return .secondary }
        if d < Date() { return .red }
        let threshold = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        if d <= threshold { return Color(red: 1.0, green: 0.62, blue: 0.1) }
        return Color(red: 0.15, green: 0.80, blue: 0.4)
    }

    var categoryIcon: String { category.icon }

    var categoryColor: Color {
        switch category {
        case .hvac:          return Color(red: 0.20, green: 0.60, blue: 0.90)
        case .kitchen:       return Color(red: 0.95, green: 0.45, blue: 0.20)
        case .laundry:       return Color(red: 0.40, green: 0.65, blue: 0.95)
        case .bathroom:      return Color(red: 0.30, green: 0.75, blue: 0.80)
        case .security:      return Color(red: 0.55, green: 0.35, blue: 0.90)
        case .entertainment: return Color(red: 0.85, green: 0.30, blue: 0.55)
        case .other:         return Color(red: 0.55, green: 0.55, blue: 0.60)
        }
    }
}

struct NewAppliancePayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let name: String
    let brand: String?
    let modelNumber: String?
    let serialNumber: String?
    let location: String?
    let category: String
    let purchaseDate: String?
    let warrantyUntil: String?
    let purchasePrice: Double?
    let notes: String?
    let photoUrl: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case propertyId    = "property_id"
        case ownerId       = "owner_id"
        case name, brand, location, category, notes
        case modelNumber   = "model_number"
        case serialNumber  = "serial_number"
        case purchaseDate  = "purchase_date"
        case warrantyUntil = "warranty_until"
        case purchasePrice = "purchase_price"
        case photoUrl      = "photo_url"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }
}

struct ApplianceUpdate: Encodable {
    var name: String?
    var brand: String?
    var modelNumber: String?
    var serialNumber: String?
    var location: String?
    var category: String?
    var purchaseDate: String?
    var warrantyUntil: String?
    var purchasePrice: Double?
    var notes: String?
    var photoUrl: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case name, brand, location, category, notes
        case modelNumber   = "model_number"
        case serialNumber  = "serial_number"
        case purchaseDate  = "purchase_date"
        case warrantyUntil = "warranty_until"
        case purchasePrice = "purchase_price"
        case photoUrl      = "photo_url"
        case updatedAt     = "updated_at"
    }
}

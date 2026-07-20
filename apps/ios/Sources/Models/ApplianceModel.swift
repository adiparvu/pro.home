import SwiftUI

enum ApplianceCategory: String, CaseIterable, Codable {
    case hvac
    case kitchen
    case laundry
    case bathroom
    case security
    case entertainment
    case other

    var displayName: String {
        switch self {
        case .hvac:          return String(localized: "HVAC")
        case .kitchen:       return String(localized: "Kitchen")
        case .laundry:       return String(localized: "Laundry")
        case .bathroom:      return String(localized: "Bathroom")
        case .security:      return String(localized: "Security")
        case .entertainment: return String(localized: "Entertainment")
        case .other:         return String(localized: "Other")
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

    private func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        return ISODate.date(from: str) ?? AppDate.day(from: str)
    }

    /// The parsed purchase day, tolerant of both ISO timestamps (what the
    /// form writes) and bare "yyyy-MM-dd" date columns.
    var purchaseDateValue: Date? { parseDate(purchaseDate) }

    /// The parsed warranty-end day, same tolerance as `purchaseDateValue`.
    var warrantyDateValue: Date? { parseDate(warrantyUntil) }

    /// Whole calendar days from today to the warranty end (negative when the
    /// warranty already expired), or nil when no warranty is recorded.
    var warrantyDaysRemaining: Int? {
        guard let d = warrantyDateValue else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: d)).day
    }

    /// Age in fractional years since purchase, or nil without a purchase
    /// date. Future-dated purchases clamp to 0 rather than going negative.
    var ageYears: Double? {
        guard let d = purchaseDateValue else { return nil }
        return max(0, Date().timeIntervalSince(d)) / 31_557_600 // 365.25 days
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

    var categoryIcon: String { category.icon }

    var categoryColor: Color {
        switch category {
        case .hvac:          return Color(red: 0.20, green: 0.60, blue: 0.90)
        case .kitchen:       return Color(red: 0.95, green: 0.45, blue: 0.20)
        case .laundry:       return Color.brandSkyBlue
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

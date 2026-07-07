import SwiftUI

// MARK: - Pantry item (real household stock)
//
// One row per product per property, merged by normalized name: receipt scans
// add to `quantity`, consumption from the pantry page subtracts. Units are
// deliberately coarse — pieces, kilograms, litres — because that's how a
// household thinks about stock, and it keeps receipt merging unambiguous.

struct PantryItem: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var name: String
    var normalizedName: String
    var quantity: Double
    var unit: String          // "buc" | "kg" | "l"
    var category: String
    var minQuantity: Double?
    var emoji: String?
    var updatedAt: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category, emoji
        case propertyId     = "property_id"
        case normalizedName = "normalized_name"
        case minQuantity    = "min_quantity"
        case updatedAt      = "updated_at"
        case createdAt      = "created_at"
    }

    // MARK: Computed

    /// Below the owner's threshold, or plain out of stock.
    var isLow: Bool {
        if let minQuantity { return quantity <= minQuantity }
        return quantity <= 0
    }

    /// "3", "0.5 kg", "1.5 l" — one decimal at most, unit only when it says
    /// something a count doesn't.
    var quantityDisplay: String {
        let rounded = (quantity * 10).rounded() / 10
        let number = rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
        return unit == "buc" ? number : "\(number) \(unit)"
    }

    /// The natural +/- step for this unit: whole pieces, half kilos/litres.
    var step: Double { unit == "buc" ? 1 : 0.5 }

    var categoryIcon: String {
        switch category {
        case "food":     return "fork.knife"
        case "drinks":   return "cup.and.saucer.fill"
        case "cleaning": return "sparkles"
        case "bathroom": return "drop.fill"
        default:         return "shippingbox.fill"
        }
    }
}

// MARK: - Payloads

struct NewPantryItemPayload: Encodable {
    let propertyId: UUID
    let name: String
    let normalizedName: String
    let quantity: Double
    let unit: String
    let category: String
    let minQuantity: Double?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, category, emoji
        case propertyId     = "property_id"
        case normalizedName = "normalized_name"
        case minQuantity    = "min_quantity"
    }
}

struct PantryItemUpdate: Encodable {
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let minQuantity: Double?
    let emoji: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, category, emoji
        case minQuantity = "min_quantity"
        case updatedAt   = "updated_at"
    }
}

// MARK: - Pantry categories (chips in the add/edit form)

enum PantryCategory {
    static let all: [(id: String, label: String, icon: String)] = [
        ("food",     String(localized: "pantry_cat_food"),     "fork.knife"),
        ("drinks",   String(localized: "pantry_cat_drinks"),   "cup.and.saucer.fill"),
        ("cleaning", String(localized: "pantry_cat_cleaning"), "sparkles"),
        ("bathroom", String(localized: "pantry_cat_bathroom"), "drop.fill"),
        ("other",    String(localized: "pantry_cat_other"),    "shippingbox.fill"),
    ]
}

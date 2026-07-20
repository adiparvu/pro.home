import SwiftUI

// MARK: - Receipt

struct Receipt: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var storeName: String
    var date: String        // ISO date: YYYY-MM-DD
    var total: Double
    var category: String
    var imageUrl: String?
    var notes: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, total, category, notes, date
        case propertyId = "property_id"
        case storeName  = "store_name"
        case imageUrl   = "image_url"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }

    var dateValue: Date {
        AppDate.day(from: date) ?? Date()
    }

    var formattedDate: String {
        AppDate.medium.string(from: dateValue)
    }

    var categoryColor: Color { ReceiptCategory.color(for: category) }
    var categoryIcon: String { ReceiptCategory.icon(for: category) }

    var formattedTotal: String { Receipt.format(total) }

    static func format(_ amount: Double) -> String {
        // Locale-aware separators — a Romanian user reads "1.234,56",
        // not the hardcoded US "1,234.56" this used to force.
        Decimal(amount).formatted(.number.precision(.fractionLength(2)))
    }
}

// MARK: - ReceiptItem

struct ReceiptItem: Identifiable, Codable, Hashable {
    var id: UUID
    var receiptId: UUID
    var propertyId: UUID
    var name: String
    var quantity: Double
    var unitPrice: Double
    var totalPrice: Double
    var category: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, category
        case receiptId  = "receipt_id"
        case propertyId = "property_id"
        case unitPrice  = "unit_price"
        case totalPrice = "total_price"
        case createdAt  = "created_at"
    }
}

// MARK: - HouseholdBudget

struct HouseholdBudget: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var category: String
    var monthlyLimit: Double
    var month: String       // YYYY-MM
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, category, month
        case propertyId   = "property_id"
        case monthlyLimit = "monthly_limit"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }
}

// MARK: - ReceiptCategory

enum ReceiptCategory {
    static let all: [(id: String, label: String)] = [
        ("food",        String(localized: "expense_cat_food")),
        ("cleaning",    String(localized: "expense_cat_cleaning")),
        ("bathroom",    String(localized: "expense_cat_bathroom")),
        ("garden",      String(localized: "expense_cat_garden")),
        ("diy",         String(localized: "expense_cat_diy")),
        ("electronics", String(localized: "expense_cat_electronics")),
        ("clothing",    String(localized: "expense_cat_clothing")),
        ("health",      String(localized: "expense_cat_health")),
        ("dining",      String(localized: "expense_cat_dining")),
        ("transport",   String(localized: "expense_cat_transport")),
        ("other",       String(localized: "expense_cat_other")),
    ]

    static func icon(for category: String) -> String {
        switch category {
        case "food":        return "cart.fill"
        case "cleaning":    return "sparkles"
        case "bathroom":    return "drop.fill"
        case "garden":      return "leaf.fill"
        case "diy":         return "hammer.fill"
        case "electronics": return "bolt.fill"
        case "clothing":    return "tshirt.fill"
        case "health":      return "cross.fill"
        case "dining":      return "fork.knife"
        case "transport":   return "car.fill"
        default:            return "bag.fill"
        }
    }

    static func color(for category: String) -> Color {
        switch category {
        case "food":        return Color(red: 1.00, green: 0.62, blue: 0.04)
        case "cleaning":    return Color(red: 0.19, green: 0.82, blue: 0.75)
        case "bathroom":    return Color.brandSkyBlue
        case "garden":      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case "diy":         return Color(red: 0.90, green: 0.45, blue: 0.18)
        case "electronics": return Color(red: 1.00, green: 0.85, blue: 0.10)
        case "clothing":    return Color(red: 0.75, green: 0.35, blue: 0.90)
        case "health":      return Color.brandDanger
        case "dining":      return Color(red: 0.97, green: 0.45, blue: 0.55)
        case "transport":   return Color.brandSkyBlue
        default:            return Color.secondary
        }
    }

    static func label(for category: String) -> String {
        all.first { $0.id == category }?.label ?? category.capitalized
    }
}

// MARK: - Aggregates

struct DailySpend: Identifiable {
    let id: String
    let date: Date
    let total: Double
}

struct CategorySpend: Identifiable {
    let id: String
    let category: String
    let total: Double

    var color: Color { ReceiptCategory.color(for: category) }
    var label: String { ReceiptCategory.label(for: category) }
    var icon: String { ReceiptCategory.icon(for: category) }
}

struct RecurringItem: Identifiable {
    let id: String
    let name: String
    let count: Int
    let avgPrice: Double
    let lastDate: Date
}

// MARK: - Payload types

struct NewReceiptPayload: Encodable {
    let propertyId: UUID
    let storeName: String
    let date: String
    let total: Double
    let category: String
    let imageUrl: String?
    let notes: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case total, category, date, notes
        case propertyId = "property_id"
        case storeName  = "store_name"
        case imageUrl   = "image_url"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}

struct NewReceiptItemPayload: Encodable {
    var receiptId: UUID
    let propertyId: UUID
    let name: String
    let quantity: Double
    let unitPrice: Double
    let totalPrice: Double
    let category: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case name, quantity, category
        case receiptId  = "receipt_id"
        case propertyId = "property_id"
        case unitPrice  = "unit_price"
        case totalPrice = "total_price"
        case createdAt  = "created_at"
    }
}

struct BudgetUpsertPayload: Encodable {
    let propertyId: UUID
    let category: String
    let monthlyLimit: Double
    let month: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case category, month
        case propertyId   = "property_id"
        case monthlyLimit = "monthly_limit"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }
}

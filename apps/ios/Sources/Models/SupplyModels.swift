import SwiftUI

// MARK: - SupplyList

struct SupplyList: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var name: String
    var icon: String
    var color: String
    var note: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case name, icon, color, note
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }

    // MARK: Computed

    var swiftColor: Color {
        let hex = color.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6,
              let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(4).prefix(2), radix: 16)
        else { return .blue }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    var iconOptions: [String] {
        ["cart.fill", "fork.knife", "sparkles", "leaf.fill", "hammer.fill",
         "lightbulb.fill", "pawprint.fill", "drop.fill", "house.fill", "bag.fill"]
    }

    static let colorOptions: [(name: String, hex: String)] = [
        ("Albastru",  "007AFF"),
        ("Verde",     "30D158"),
        ("Portocaliu","FF9F0A"),
        ("Roșu",      "FF453A"),
        ("Violet",    "BF5AF2"),
        ("Cyan",      "5AC8FA"),
        ("Roz",       "FF375F"),
        ("Maro",      "A2845E"),
    ]
}

// MARK: - SupplyItem

struct SupplyItem: Identifiable, Codable, Hashable {
    var id: UUID
    var listId: UUID
    var propertyId: UUID
    var name: String
    var quantity: String?
    var category: String
    var priority: String
    var notes: String?
    var isCompleted: Bool
    var location: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case listId     = "list_id"
        case propertyId = "property_id"
        case name, quantity, category, priority, notes, location
        case isCompleted = "is_completed"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    // MARK: Computed

    var categoryIcon: String {
        switch category {
        case "food":        return "fork.knife"
        case "cleaning":    return "sparkles"
        case "bathroom":    return "drop.fill"
        case "garden":      return "leaf.fill"
        case "diy":         return "hammer.fill"
        case "electronics": return "lightbulb.fill"
        case "pet":         return "pawprint.fill"
        default:            return "shippingbox.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "food":        return Color(red: 1.0,  green: 0.62, blue: 0.04)
        case "cleaning":    return Color(red: 0.19, green: 0.82, blue: 0.75)
        case "bathroom":    return Color(red: 0.35, green: 0.65, blue: 1.0)
        case "garden":      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case "diy":         return Color(red: 0.9,  green: 0.45, blue: 0.18)
        case "electronics": return Color(red: 1.0,  green: 0.85, blue: 0.1)
        case "pet":         return Color(red: 0.75, green: 0.55, blue: 0.36)
        default:            return Color.secondary
        }
    }

    var priorityColor: Color {
        switch priority {
        case "low":      return .gray
        case "medium":   return .blue
        case "high":     return .orange
        case "critical": return .red
        default:         return .blue
        }
    }
}

// MARK: - Payload types

struct NewSupplyListPayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let name: String
    let icon: String
    let color: String
    let note: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case name, icon, color, note
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}

struct NewSupplyItemPayload: Encodable {
    let listId: UUID
    let propertyId: UUID
    let name: String
    let quantity: String?
    let category: String
    let priority: String
    let notes: String?
    let isCompleted: Bool
    let location: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case listId     = "list_id"
        case propertyId = "property_id"
        case name, quantity, category, priority, notes, location
        case isCompleted = "is_completed"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

struct SupplyItemUpdate: Encodable {
    let name: String
    let quantity: String?
    let category: String
    let priority: String
    let notes: String?
    let isCompleted: Bool
    let location: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, quantity, category, priority, notes, location
        case isCompleted = "is_completed"
        case updatedAt   = "updated_at"
    }
}

struct SupplyListUpdate: Encodable {
    let name: String
    let icon: String
    let color: String
    let note: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, icon, color, note
        case updatedAt = "updated_at"
    }
}

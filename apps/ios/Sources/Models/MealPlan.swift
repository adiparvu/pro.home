import SwiftUI

// MARK: - Meal planner ("Planificator de mese")
//
// The week's meals as a shared family plan: four slots a day, each meal with
// its real ingredient list. Ingredients flow OUT to the shopping lists (one
// tap sends what's missing) and, when a meal is marked cooked, stock flows
// DOWN in the pantry — the plan, the list and the shelf stay one story.

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .breakfast: return "meal_breakfast"
        case .lunch:     return "meal_lunch"
        case .dinner:    return "meal_dinner"
        case .snack:     return "meal_snack"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "carrot.fill"
        }
    }

    var tint: Color {
        switch self {
        case .breakfast: return .brandWarning
        case .lunch:     return .brandSuccess
        case .dinner:    return .brandPurple
        case .snack:     return .brandSkyBlue
        }
    }

    /// The natural order of a day's table.
    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch:     return 1
        case .dinner:    return 2
        case .snack:     return 3
        }
    }
}

struct MealPlan: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var day: String                // "YYYY-MM-DD"
    var mealType: String
    var title: String
    var ingredients: [String]
    var notes: String?
    var cookedAt: String?
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, day, title, ingredients, notes
        case propertyId = "property_id"
        case mealType   = "meal_type"
        case cookedAt   = "cooked_at"
        case createdBy  = "created_by"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }

    var slot: MealSlot { MealSlot(rawValue: mealType) ?? .dinner }
    var date: Date? { AppDate.day(from: day) }
    var isCooked: Bool { cookedAt != nil }
}

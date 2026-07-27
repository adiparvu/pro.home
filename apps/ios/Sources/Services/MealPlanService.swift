import Foundation
import Observation
import Supabase

// MARK: - Meal plan service ("Planificator de mese")
//
// CRUD over `meal_plans` plus the two bridges that make the plan useful:
// ingredients push INTO the shopping lists (only what isn't already pending),
// and marking a meal cooked consumes matching pantry stock — the plan, the
// list and the shelf stay one consistent story. Lazy like MeterService.

@MainActor
@Observable
final class MealPlanService {
    private(set) var meals: [MealPlan] = []
    var isLoading = false
    var error: String?
    private var loadedPropertyId: UUID?

    // MARK: - Load (lazy — first planner surface)

    func loadIfNeeded() async {
        let pid = PropertyService.activePropertyId
        guard loadedPropertyId != pid || meals.isEmpty else { return }
        await load()
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        if meals.isEmpty, let cached = ServiceCache.load([MealPlan].self, entity: "meal_plans", propertyId: pid) {
            meals = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            meals = try await PropertyRepo.fetch(table: "meal_plans", propertyId: pid,
                                                 order: "day", limit: 500)
            loadedPropertyId = pid
            ServiceCache.save(meals, entity: "meal_plans", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    /// A day's meals in table order (breakfast → snack).
    func meals(on day: Date) -> [MealPlan] {
        let key = AppDate.dayString(from: day)
        return meals.filter { $0.day == key }
            .sorted { $0.slot.order < $1.slot.order }
    }

    func meal(on day: Date, slot: MealSlot) -> MealPlan? {
        meals(on: day).first { $0.slot == slot }
    }

    // MARK: - CRUD

    struct MealPayload: Encodable {
        var propertyId: String?
        let day: String
        let mealType: String
        let title: String
        let ingredients: [String]
        let notes: String?
        var updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case day, title, ingredients, notes
            case propertyId = "property_id"
            case mealType   = "meal_type"
            case updatedAt  = "updated_at"
        }
    }

    func add(_ payload: MealPayload) async throws {
        var p = payload
        p.propertyId = PropertyService.activePropertyId?.uuidString
        try await supabase.from("meal_plans").insert(p).execute()
        await load()
    }

    func update(_ id: UUID, payload: MealPayload) async throws {
        var p = payload
        p.updatedAt = ISODate.string(from: Date())
        try await supabase.from("meal_plans")
            .update(p).eq("id", value: id.uuidString).execute()
        await load()
    }

    func delete(_ meal: MealPlan) async {
        do {
            try await supabase.from("meal_plans")
                .delete().eq("id", value: meal.id.uuidString).execute()
            meals.removeAll { $0.id == meal.id }
        } catch { self.error = error.recordableDescription }
    }

    // MARK: - Bridge 1: ingredients → shopping list

    /// Sends the meal's ingredients to a shopping list, skipping anything
    /// already pending there (case/diacritic-insensitive). Returns how many
    /// items were actually added — never inflate the number.
    @discardableResult
    func sendIngredients(of meal: MealPlan, to listId: UUID,
                         supply: SupplyService) async -> Int {
        guard let pid = PropertyService.activePropertyId else { return 0 }
        let pending = Set(supply.items(for: listId)
            .filter { !$0.isCompleted }
            .map { Self.fold($0.name) })
        var added = 0
        let now = ISODate.string(from: Date())
        for ingredient in meal.ingredients {
            let name = ingredient.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !pending.contains(Self.fold(name)) else { continue }
            let payload = NewSupplyItemPayload(
                listId: listId, propertyId: pid, name: name,
                quantity: nil, category: "food", priority: "medium",
                notes: nil, isCompleted: false, location: nil,
                createdAt: now, updatedAt: now)
            if (try? await supply.addItem(payload)) != nil { added += 1 }
        }
        return added
    }

    // MARK: - Bridge 2: cooked → pantry consumption

    /// Stamps the meal cooked and consumes matching pantry stock: each
    /// ingredient that matches a pantry row by folded name goes down by one
    /// unit. Only exact matches move — the pantry never guesses.
    func markCooked(_ meal: MealPlan, pantry: PantryService) async {
        do {
            try await supabase.from("meal_plans")
                .update(["cooked_at": ISODate.string(from: Date())])
                .eq("id", value: meal.id.uuidString).execute()
        } catch {
            self.error = error.recordableDescription
            return
        }
        for ingredient in meal.ingredients {
            let key = Self.fold(ingredient)
            guard !key.isEmpty,
                  let item = pantry.items.first(where: {
                      Self.fold($0.name) == key || Self.fold($0.normalizedName) == key
                  }),
                  item.quantity > 0 else { continue }
            await pantry.adjust(item, by: -1)
        }
        await load()
    }

    /// Lowercased, diacritic-folded, trimmed — the matching identity for
    /// ingredient ↔ list-item ↔ pantry-row comparisons.
    nonisolated static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

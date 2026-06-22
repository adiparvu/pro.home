import Foundation

@MainActor
final class BudgetService: ObservableObject {
    @Published var budgets: [String: Double] = [:]

    static let categories = ["rent", "utilities", "maintenance", "insurance", "taxes", "mortgage", "supplies", "other"]

    private var currentPropertyId: UUID?

    func load(propertyId: UUID) async {
        currentPropertyId = propertyId
        do {
            struct Row: Codable { let category: String; let amount: Double }
            let rows: [Row] = try await supabase
                .from("property_budgets")
                .select("category,amount")
                .eq("property_id", value: propertyId.uuidString)
                .execute()
                .value
            budgets = Dictionary(uniqueKeysWithValues: rows.map { ($0.category, $0.amount) })
        } catch {
            // ignore — budgets are optional data
        }
    }

    func setBudget(_ amount: Double, for category: String) {
        if amount <= 0 {
            budgets.removeValue(forKey: category)
        } else {
            budgets[category] = amount
        }
        Task { await persist(category: category, amount: amount) }
    }

    func budget(for category: String) -> Double { budgets[category] ?? 0 }
    func totalBudget() -> Double { budgets.values.reduce(0, +) }

    func spendingProgress(for category: String, spent: Double) -> Double {
        let b = budget(for: category)
        guard b > 0 else { return 0 }
        return min(spent / b, 1.0)
    }

    // MARK: - Private

    private func persist(category: String, amount: Double) async {
        guard let propertyId = currentPropertyId else { return }
        if amount <= 0 {
            try? await supabase
                .from("property_budgets")
                .delete()
                .eq("property_id", value: propertyId.uuidString)
                .eq("category", value: category)
                .execute()
        } else {
            struct Payload: Encodable {
                let property_id: String
                let category: String
                let amount: Double
            }
            try? await supabase
                .from("property_budgets")
                .upsert(Payload(property_id: propertyId.uuidString, category: category, amount: amount),
                        onConflict: "property_id,category")
                .execute()
        }
    }
}

import Foundation

@MainActor
final class BudgetService: ObservableObject {
    @Published var budgets: [String: Double] = [:]

    static let categories = ["rent", "utilities", "maintenance", "insurance", "taxes", "mortgage", "supplies", "other"]
    private let key = "prvio.budgets"

    init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            budgets = decoded
        }
    }

    func setBudget(_ amount: Double, for category: String) {
        if amount <= 0 {
            budgets.removeValue(forKey: category)
        } else {
            budgets[category] = amount
        }
        save()
    }

    func budget(for category: String) -> Double { budgets[category] ?? 0 }

    func totalBudget() -> Double { budgets.values.reduce(0, +) }

    func spendingProgress(for category: String, spent: Double) -> Double {
        let b = budget(for: category)
        guard b > 0 else { return 0 }
        return min(spent / b, 1.0)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(budgets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

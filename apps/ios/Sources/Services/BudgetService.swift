import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class BudgetService {
    var budgets: [String: Double] = [:]

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

    // MARK: - Threshold notifications
    //
    // Fires a local notification when a category with a budget crosses 80%
    // and again at 100% of its monthly limit — each threshold at most ONCE
    // per category per calendar month. Fired markers persist in UserDefaults
    // (keyed category + month + threshold) and are pruned to the current
    // month so the list can never grow unbounded.
    private static let firedThresholdsKey = "prvio.budget.firedThresholds"

    /// Called after budgets and the month's records are both freshly loaded.
    /// `spentByCategory` carries the current calendar month's expense totals
    /// keyed by lowercase category — the same numbers BudgetView draws.
    func checkThresholds(spentByCategory: [String: Double]) {
        guard !budgets.isEmpty else { return }
        let monthKey = AppDate.monthKey.string(from: Date())
        let defaults = UserDefaults.standard
        var fired = (defaults.stringArray(forKey: Self.firedThresholdsKey)) ?? []
        var dirty = false

        // Forget previous months' markers — a new month starts clean.
        let pruned = fired.filter { $0.contains("|\(monthKey)|") }
        if pruned.count != fired.count { fired = pruned; dirty = true }

        for (category, budget) in budgets where budget > 0 {
            let ratio = (spentByCategory[category] ?? 0) / budget
            for threshold in [100, 80] where ratio >= Double(threshold) / 100 {
                let marker = "\(category)|\(monthKey)|\(threshold)"
                guard !fired.contains(marker) else { continue }
                fired.append(marker)
                dirty = true
                // A spend that jumps straight past 100% records the 80%
                // marker silently — one honest alert, never two at once.
                if threshold == 80 && ratio >= 1.0 { continue }
                scheduleThresholdNotification(category: category, threshold: threshold, monthKey: monthKey)
            }
        }
        if dirty { defaults.set(fired, forKey: Self.firedThresholdsKey) }
    }

    private func scheduleThresholdNotification(category: String, threshold: Int, monthKey: String) {
        // The categories are a fixed list whose capitalized names already
        // exist as localized keys (BudgetView renders them the same way).
        let name = String(localized: String.LocalizationValue(category.capitalized))
        let content = UNMutableNotificationContent()
        if threshold >= 100 {
            content.title = String(localized: "budget_notif_over_title")
            content.body = String(format: String(localized: "budget_notif_over_body"), name)
        } else {
            content.title = String(localized: "budget_notif_near_title")
            content.body = String(format: String(localized: "budget_notif_near_body"), name)
        }
        content.sound = .default
        content.categoryIdentifier = "PROACTIVE"
        content.userInfo = ["deepLink": "prvio://finances"]
        let request = UNNotificationRequest(
            identifier: "budget.\(category).\(monthKey).\(threshold)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Private

    private func persist(category: String, amount: Double) async {
        guard let propertyId = currentPropertyId else { return }
        if amount <= 0 {
            _ = try? await supabase
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
            _ = try? await supabase
                .from("property_budgets")
                .upsert(Payload(property_id: propertyId.uuidString, category: category, amount: amount),
                        onConflict: "property_id,category")
                .execute()
        }
    }
}

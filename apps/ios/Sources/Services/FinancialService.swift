import Foundation
import Observation

@MainActor
@Observable
final class FinancialService {
    var records: [FinancialRecord] = []
    var isLoading = false
    var error: String?

    // MARK: - Computed stats

    var currentMonthRecords: [FinancialRecord] {
        let cal = Calendar.current
        let now = Date()
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return [] }
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        return records.filter { r in
            guard let d = iso.date(from: r.date) else { return false }
            return d >= first && d <= now
        }
    }

    var currentMonthIncome: Double {
        currentMonthRecords.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
    }
    var currentMonthExpenses: Double {
        currentMonthRecords.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
    }
    var currentMonthNet: Double { currentMonthIncome - currentMonthExpenses }

    // Last 6 months grouped by month
    var monthlyData: [(month: String, income: Double, expenses: Double)] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter(); label.dateFormat = "MMM"
        let cal = Calendar.current
        let now = Date()

        return (0..<6).reversed().compactMap { offset -> (String, Double, Double)? in
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: now),
                  let first = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
                  let last = cal.date(byAdding: .month, value: 1, to: first) else { return nil }
            let monthRecords = records.filter { r in
                guard let d = iso.date(from: r.date) else { return false }
                return d >= first && d < last
            }
            let income = monthRecords.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
            let expenses = monthRecords.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
            return (label.string(from: first), income, expenses)
        }
    }

    var recentRecords: [FinancialRecord] { Array(records.prefix(5)) }

    var currency: String { records.first?.currency ?? "EUR" }
    var currencySymbol: String { currency == "EUR" ? "€" : currency == "USD" ? "$" : currency }

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if records.isEmpty, let cached = ServiceCache.load([FinancialRecord].self, entity: "financial", propertyId: pid) {
            records = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var query = supabase.from("financial_records").select()
            if let pid {
                // Scope to the selected home; legacy rows without a property
                // stay visible rather than silently disappearing.
                query = query.or("property_id.eq.\(pid.uuidString),property_id.is.null")
            }
            records = try await query
                .order("date", ascending: false)
                .execute()
                .value
            ServiceCache.save(records, entity: "financial", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func delete(_ record: FinancialRecord) async {
        do {
            try await supabase
                .from("financial_records")
                .delete()
                .eq("id", value: record.id.uuidString)
                .execute()
            records.removeAll { $0.id == record.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

import Foundation

@MainActor
final class FinancialService: ObservableObject {
    @Published var records: [FinancialRecord] = []
    @Published var isLoading = false
    @Published var error: String?

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
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await supabase
                .from("financial_records")
                .select()
                .order("date", ascending: false)
                .execute()
                .value
        } catch {
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

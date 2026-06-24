import SwiftUI
import Charts

// MARK: - Finances Section

struct FinancesSection: View {
    @ObservedObject var service: FinancialService
    @Binding var displayedMonth: Date

    @State var chartRange: ChartRange = .sixMonths
    @State var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State var customEnd = Date()
    @State var showCustomSheet = false

    private var cal: Calendar { Calendar.current }
    private var isCurrentMonth: Bool { cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) }

    private var monthRecords: [FinancialRecord] {
        service.records.filter { r in
            let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
            guard let d = iso.date(from: r.date) else { return false }
            return cal.isDate(d, equalTo: displayedMonth, toGranularity: .month)
        }
    }

    private var prevMonthRecords: [FinancialRecord] {
        guard let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) else { return [] }
        return service.records.filter { r in
            let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
            guard let d = iso.date(from: r.date) else { return false }
            return cal.isDate(d, equalTo: prev, toGranularity: .month)
        }
    }

    private var income: Double { monthRecords.filter(\.isIncome).map(\.amount).reduce(0, +) }
    private var expenses: Double { monthRecords.filter { $0.type == "expense" }.map(\.amount).reduce(0, +) }
    private var net: Double { income - expenses }
    private var savingsRate: Double { income > 0 ? (net / income) * 100 : 0 }

    private var prevIncome: Double { prevMonthRecords.filter(\.isIncome).map(\.amount).reduce(0, +) }
    private var prevExpenses: Double { prevMonthRecords.filter { $0.type == "expense" }.map(\.amount).reduce(0, +) }

    private var sym: String { service.currencySymbol }

    private func trend(_ current: Double, _ prev: Double) -> Double? {
        guard prev > 0 else { return nil }
        return ((current - prev) / prev) * 100
    }

    private var categoryData: [CategoryStat] {
        let expenseRecords = monthRecords.filter { $0.type == "expense" }
        let grouped = Dictionary(grouping: expenseRecords, by: \.category)
        return grouped.map { key, val in
            CategoryStat(name: key.isEmpty ? "Altele" : key.capitalized,
                         amount: val.map(\.amount).reduce(0, +))
        }
        .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(spacing: 16) {
            periodNavigator
            kpiRow
            if income > 0 || expenses > 0 {
                savingsCard
                if !categoryData.isEmpty { categoryCard }
            }
            chartCard
        }
    }

    // MARK: - Period Navigator

    private var periodNavigator: some View {
        HStack(spacing: 0) {
            Button {
                if let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) {
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = prev }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(LocalizedStringKey(monthLabel))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if isCurrentMonth {
                    Text("current month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                if let next = cal.date(byAdding: .month, value: 1, to: displayedMonth) {
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = next }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrentMonth ? Color.primary.opacity(0.2) : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 8)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth).capitalized
    }

    // MARK: - KPI Row

    private var kpiRow: some View {
        HStack(spacing: 10) {
            TrendKPICard(
                label: "Income",
                value: "\(sym)\(Int(income))",
                icon: "arrow.down.circle.fill",
                trendPct: trend(income, prevIncome),
                trendPositive: income >= prevIncome
            )
            TrendKPICard(
                label: "Expenses",
                value: "\(sym)\(Int(expenses))",
                icon: "arrow.up.circle.fill",
                trendPct: trend(expenses, prevExpenses),
                trendPositive: expenses <= prevExpenses
            )
            TrendKPICard(
                label: "Net",
                value: "\(net >= 0 ? "+" : "")\(sym)\(Int(net))",
                icon: "chart.line.uptrend.xyaxis",
                trendPct: nil,
                trendPositive: net >= 0,
                highlightValue: true,
                positiveValue: net >= 0
            )
        }
    }

    // MARK: - Savings Card

    private var savingsCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Savings rate", systemImage: "leaf.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.0f%%", max(0, savingsRate)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(savingsRate >= 20 ? Color(red: 0.2, green: 0.8, blue: 0.4) : savingsRate >= 0 ? .orange : .red)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(
                                colors: savingsRate > 0
                                    ? [Color(red: 0.3, green: 0.85, blue: 0.5), .blue]
                                    : [.red.opacity(0.8), .orange],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * min(1, max(0, savingsRate / 100)), height: 8)
                            .animation(.spring(response: 0.6), value: savingsRate)
                    }
                }
                .frame(height: 8)
                Text(LocalizedStringKey(savingsInsight))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var savingsInsight: String {
        if savingsRate >= 30 { return String(localized: "Excellent! You're saving more than 30% of your income.") }
        if savingsRate >= 20 { return String(localized: "Good! You're saving \(Int(savingsRate))% of your income.") }
        if savingsRate >= 0  { return String(localized: "You can save more by reducing expenses.") }
        return String(localized: "Expenses exceed income this month.")
    }

    // MARK: - Category Donut Chart

    private var categoryCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Expenses by category")
                    .font(.system(size: 15, weight: .semibold))

                HStack(alignment: .top, spacing: 16) {
                    Chart(categoryData.prefix(6)) { cat in
                        SectorMark(
                            angle: .value("Amount", cat.amount),
                            innerRadius: .ratio(0.60),
                            angularInset: 2
                        )
                        .foregroundStyle(cat.color)
                        .cornerRadius(4)
                    }
                    .frame(width: 110, height: 110)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categoryData.prefix(5)) { cat in
                            HStack(spacing: 6) {
                                Circle().fill(cat.color).frame(width: 8, height: 8)
                                Text(cat.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(sym)\(Int(cat.amount))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

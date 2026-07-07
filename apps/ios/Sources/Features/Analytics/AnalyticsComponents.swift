import SwiftUI
import Charts

// MARK: - Finances Section

struct FinancesSection: View {
    var service: FinancialService
    @Binding var displayedMonth: Date
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    @State var chartRange: ChartRange = .sixMonths
    @State var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State var customEnd = Date()
    @State var showCustomSheet = false

    private var cal: Calendar { Calendar.current }
    private var isCurrentMonth: Bool { cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) }
    private var preferred: String { appSettings.preferredCurrency }

    private var monthRecords: [FinancialRecord] {
        service.records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return cal.isDate(d, equalTo: displayedMonth, toGranularity: .month)
        }
    }

    private var prevMonthRecords: [FinancialRecord] {
        guard let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) else { return [] }
        return service.records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return cal.isDate(d, equalTo: prev, toGranularity: .month)
        }
    }

    /// One pass over a month's records, every amount converted to the
    /// preferred currency — the sums here used to add raw amounts across
    /// currencies, so one EUR salary next to RON expenses skewed every KPI.
    private func stats(for records: [FinancialRecord]) -> MonthFinanceStats {
        var s = MonthFinanceStats()
        for r in records {
            let v = currencyService.convert(r.amount, from: r.currency, to: preferred)
            if r.isIncome {
                s.income += v
            } else if r.type == "expense" {
                s.expenses += v
                let key = r.category.isEmpty ? "other" : r.category.lowercased()
                s.byCategory[key, default: 0] += v
                if let d = AppDate.day(from: r.date) {
                    s.byDay[cal.component(.day, from: d), default: 0] += v
                }
            }
        }
        return s
    }

    private func trend(_ current: Double, _ prev: Double) -> Double? {
        guard prev > 0 else { return nil }
        return ((current - prev) / prev) * 100
    }

    private func money(_ value: Double) -> String {
        CurrencyService.money(value, code: preferred, whole: true)
    }

    /// Internal (not private) — the chart extension in
    /// FinancesSectionChart.swift buckets through this same conversion.
    func convertToPreferred(_ amount: Double, from code: String) -> Double {
        currencyService.convert(amount, from: code, to: preferred)
    }

    var body: some View {
        // One pass per render (the old computed vars re-filtered the whole
        // record list on every access).
        let cur = stats(for: monthRecords)
        let prev = stats(for: prevMonthRecords)
        let cats = cur.byCategory
            .map { CategoryStat(name: $0.key.capitalized, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        VStack(spacing: 16) {
            periodNavigator
            kpiRow(cur: cur, prev: prev)
            if cur.income > 0 || cur.expenses > 0 {
                savingsCard(cur: cur)
                if !cats.isEmpty { categoryCard(cats) }
                MonthInsightsCard(insights: insights(cur: cur, prev: prev))
                dailySpendCard(cur: cur)
            }
            chartCard
        }
    }

    @ViewBuilder
    private func dailySpendCard(cur: MonthFinanceStats) -> some View {
        let daysInMonth = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let peak = cur.byDay.max(by: { $0.value < $1.value })?.key
        DailySpendCard(days: (1...daysInMonth).map {
            DailySpendCard.Day(day: $0, amount: cur.byDay[$0] ?? 0)
        }, peakDay: peak)
    }

    // MARK: - Auto insights (only claims the data actually supports)

    private func insights(cur: MonthFinanceStats, prev: MonthFinanceStats) -> [MonthInsight] {
        var out: [MonthInsight] = []
        // Where the month's money is concentrated.
        if cur.expenses > 0, let top = cur.byCategory.max(by: { $0.value < $1.value }) {
            let pct = Int((top.value / cur.expenses * 100).rounded())
            if pct >= 20 {
                out.append(MonthInsight(icon: "chart.pie.fill", color: .blue,
                    text: String(format: String(localized: "ana_insight_top_cat %@ %lld"),
                                 localizedCategory(top.key), pct)))
            }
        }
        // The category that moved the most vs. last month — only when it is
        // big enough to matter (≥10% of the month) and the move is ≥25%.
        var moveKey: String?
        var movePct = 0.0
        for (key, value) in cur.byCategory {
            let before = prev.byCategory[key] ?? 0
            guard before > 0, value >= cur.expenses * 0.1 else { continue }
            let pct = (value - before) / before * 100
            if abs(pct) >= 25, abs(pct) > abs(movePct) {
                moveKey = key
                movePct = pct
            }
        }
        if let key = moveKey {
            let rising = movePct > 0
            out.append(MonthInsight(
                icon: rising ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                color: rising ? .orange : Color.brandSuccess,
                text: String(format: String(localized: rising ? "ana_insight_jump %@ %lld"
                                                              : "ana_insight_drop %@ %lld"),
                             localizedCategory(key), Int(abs(movePct).rounded()))))
        }
        // The single most expensive day, when spending isn't flat.
        if cur.byDay.count > 1, let peak = cur.byDay.max(by: { $0.value < $1.value }),
           let date = cal.date(byAdding: .day, value: peak.key - 1, to: displayedMonth) {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMMM"
            formatter.locale = .current
            out.append(MonthInsight(icon: "calendar.circle.fill", color: .purple,
                text: String(format: String(localized: "ana_insight_peak_day %@ %@"),
                             formatter.string(from: date), money(peak.value))))
        }
        return out
    }

    /// Category keys are stored lowercased; the catalog localizes their
    /// capitalized form (the same keys the transaction rows display).
    private func localizedCategory(_ raw: String) -> String {
        String(localized: String.LocalizationValue(raw.capitalized))
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
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 1) {
                Text(LocalizedStringKey(monthLabel))
                    .font(AppFont.subheadline)
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
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(isCurrentMonth ? Color.primary.opacity(0.2) : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, AppSpacing.sm)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth).capitalized
    }

    // MARK: - KPI Row

    private func kpiRow(cur: MonthFinanceStats, prev: MonthFinanceStats) -> some View {
        let net = cur.income - cur.expenses
        return HStack(spacing: 10) {
            TrendKPICard(
                label: "Income",
                value: money(cur.income),
                icon: "arrow.down.circle.fill",
                trendPct: trend(cur.income, prev.income),
                trendPositive: cur.income >= prev.income
            )
            TrendKPICard(
                label: "Expenses",
                value: money(cur.expenses),
                icon: "arrow.up.circle.fill",
                trendPct: trend(cur.expenses, prev.expenses),
                trendPositive: cur.expenses <= prev.expenses
            )
            TrendKPICard(
                label: "Net",
                value: "\(net >= 0 ? "+" : "")" + money(net),
                icon: "chart.line.uptrend.xyaxis",
                trendPct: nil,
                trendPositive: net >= 0,
                highlightValue: true,
                positiveValue: net >= 0
            )
        }
    }

    // MARK: - Savings Card

    private func savingsCard(cur: MonthFinanceStats) -> some View {
        let savingsRate = cur.income > 0 ? (cur.income - cur.expenses) / cur.income * 100 : 0
        return GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Savings rate", systemImage: "leaf.fill")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.0f%%", max(0, savingsRate)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(savingsRate >= 20 ? Color.brandSuccess : savingsRate >= 0 ? .orange : .red)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(
                                colors: savingsRate > 0
                                    ? [Color.brandSuccess, .blue]
                                    : [.red.opacity(0.8), .orange],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * min(1, max(0, savingsRate / 100)), height: 8)
                            .animation(.spring(response: 0.6), value: savingsRate)
                    }
                }
                .frame(height: 8)
                Text(LocalizedStringKey(savingsInsight(rate: savingsRate)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func savingsInsight(rate: Double) -> String {
        if rate >= 30 { return String(localized: "Excellent! You're saving more than 30% of your income.") }
        if rate >= 20 { return String(localized: "Good! You're saving \(Int(rate))% of your income.") }
        if rate >= 0  { return String(localized: "You can save more by reducing expenses.") }
        return String(localized: "Expenses exceed income this month.")
    }

    // MARK: - Category Donut Chart

    private func categoryCard(_ categoryData: [CategoryStat]) -> some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Expenses by category")
                    .font(AppFont.subheadline)

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
                                Text(LocalizedStringKey(cat.name))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(money(cat.amount))
                                    .font(AppFont.captionStrong)
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

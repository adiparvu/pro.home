import SwiftUI
import Charts

// MARK: - Finances Section

struct FinancesSection: View {
    var service: FinancialService
    @Binding var displayedMonth: Date
    @Environment(CurrencyService.self) private var currencyService
    // Internal (not private) — the chart extension in FinancesSectionChart.swift
    // reads the same merged ledger (records + scanned receipts).
    @Environment(ReceiptService.self) var receiptService
    @Environment(AppSettings.self) private var appSettings

    @State var chartRange: ChartRange = .sixMonths
    @State var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State var customEnd = Date()
    @State var showCustomSheet = false
    /// The tapped donut slice / legend row, presented as a sheet.
    @State private var drilldown: CategoryDrilldown?
    /// Swift Charts angle selection over the donut (slice taps).
    @State private var donutSelection: Double?

    private var cal: Calendar { Calendar.current }
    private var isCurrentMonth: Bool { cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) }
    private var preferred: String { appSettings.preferredCurrency }

    private var monthRecords: [FinancialRecord] {
        service.records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return cal.isDate(d, equalTo: displayedMonth, toGranularity: .month)
        }
    }

    private var prevMonth: Date? { cal.date(byAdding: .month, value: -1, to: displayedMonth) }

    private var prevMonthRecords: [FinancialRecord] {
        guard let prev = prevMonth else { return [] }
        return service.records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return cal.isDate(d, equalTo: prev, toGranularity: .month)
        }
    }

    /// Scanned receipts of a month — the second half of the household ledger.
    private func receipts(in month: Date) -> [Receipt] {
        receiptService.receipts.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return cal.isDate(d, equalTo: month, toGranularity: .month)
        }
    }

    /// One pass over a month's records AND scanned receipts, every amount in
    /// the preferred currency. Receipts used to be invisible here — the donut
    /// showed only manual records (usually saved as "other"), which is why it
    /// rendered a single 100% "Other" slice while the real categorized
    /// spending sat in the receipts table.
    private func stats(records: [FinancialRecord], receipts: [Receipt]) -> MonthFinanceStats {
        var s = MonthFinanceStats()
        for r in records {
            let v = convertToPreferred(r.amount, from: r.currency)
            if r.isIncome {
                s.income += v
            } else if r.type == "expense" {
                s.expenses += v
                let key = AnalyticsCategoryDisplay.normalize(r.category)
                s.byCategory[key, default: 0] += v
                if let d = AppDate.day(from: r.date) {
                    s.byDay[cal.component(.day, from: d), default: 0] += v
                    s.items.append(MonthExpenseItem(
                        id: "rec-\(r.id.uuidString)", title: r.title,
                        categoryKey: key, date: d, amount: v, isReceipt: false))
                }
            }
        }
        for r in receipts {
            // The receipts table stores no currency column (ExpenseModels) —
            // totals are captured in the household's preferred currency.
            guard r.total > 0, let d = AppDate.day(from: r.date) else { continue }
            let v = r.total
            let key = AnalyticsCategoryDisplay.normalize(r.category)
            s.expenses += v
            s.receiptExpenses += v
            s.byCategory[key, default: 0] += v
            s.byDay[cal.component(.day, from: d), default: 0] += v
            let store = r.storeName.trimmingCharacters(in: .whitespaces)
            let title = store.isEmpty ? String(localized: "ana_receipt_generic") : store
            if !store.isEmpty {
                s.byMerchant[store, default: 0] += v
                s.merchantVisits[store, default: 0] += 1
            }
            s.items.append(MonthExpenseItem(
                id: "rcpt-\(r.id.uuidString)", title: title,
                categoryKey: key, date: d, amount: v, isReceipt: true))
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
        let cur = stats(records: monthRecords, receipts: receipts(in: displayedMonth))
        let prev = stats(records: prevMonthRecords,
                         receipts: prevMonth.map { receipts(in: $0) } ?? [])
        let cats = categoryStats(cur)

        VStack(spacing: 16) {
            periodNavigator
            kpiRow(cur: cur, prev: prev)
            if cur.income > 0 || cur.expenses > 0 {
                savingsCard(cur: cur)
                if !cats.isEmpty { categoryCard(cats, stats: cur) }
                topMerchantsCard(cur)
                MonthInsightsCard(insights: insights(cur: cur, prev: prev))
                dailySpendCard(cur: cur)
            }
            yearPulse
            chartCard
        }
        .sheet(item: $drilldown) { sel in
            CategoryDrilldownSheet(drilldown: sel, format: { money($0) })
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

    // MARK: - Top merchants

    @ViewBuilder
    private func topMerchantsCard(_ cur: MonthFinanceStats) -> some View {
        let top = cur.byMerchant
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { TopMerchantsCard.Merchant(name: $0.key, amount: $0.value,
                                             visits: cur.merchantVisits[$0.key] ?? 1) }
        TopMerchantsCard(merchants: top, format: { money($0) })
    }

    // MARK: - Auto insights (only claims the data actually supports)

    private func insights(cur: MonthFinanceStats, prev: MonthFinanceStats) -> [MonthInsight] {
        var out: [MonthInsight] = []

        // Savings-rate move vs. last month — both months need real income.
        if cur.income > 0, prev.income > 0 {
            let curRate = Int(((cur.income - cur.expenses) / cur.income * 100).rounded())
            let prevRate = Int(((prev.income - prev.expenses) / prev.income * 100).rounded())
            if abs(curRate - prevRate) >= 5 {
                let rising = curRate > prevRate
                out.append(MonthInsight(
                    icon: "leaf.circle.fill",
                    color: rising ? Color.brandSuccess : .orange,
                    text: String(format: String(localized: rising ? "ana_insight_savings_up %lld %lld"
                                                                  : "ana_insight_savings_down %lld %lld"),
                                 prevRate, curRate)))
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
                             AnalyticsCategoryDisplay.label(key), Int(abs(movePct).rounded()))))
        }

        // One unusual single expense — more than 2× the month's median, with
        // enough items for a median to mean anything.
        if cur.items.count >= 5 {
            let sorted = cur.items.map(\.amount).sorted()
            let median = sorted[sorted.count / 2]
            if median > 0, let top = cur.items.max(by: { $0.amount < $1.amount }),
               top.amount > median * 2 {
                out.append(MonthInsight(icon: "exclamationmark.circle.fill", color: .red,
                    text: String(format: String(localized: "ana_insight_outlier %@ %@"),
                                 top.title, money(top.amount))))
            }
        }

        // Where the month's money is concentrated.
        if cur.expenses > 0, let top = cur.byCategory.max(by: { $0.value < $1.value }) {
            let pct = Int((top.value / cur.expenses * 100).rounded())
            if pct >= 20 {
                out.append(MonthInsight(icon: "chart.pie.fill", color: .blue,
                    text: String(format: String(localized: "ana_insight_top_cat %@ %lld"),
                                 AnalyticsCategoryDisplay.label(top.key), pct)))
            }
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

        return Array(out.prefix(3))
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
                        .font(AppFont.scaled(18, weight: .bold))
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
                    .font(AppFont.scaled(12))
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

    /// Top five categories plus one honest remainder bucket — the donut's
    /// slices always sum to the month's total, never just to its top slice.
    private func categoryStats(_ s: MonthFinanceStats) -> [CategoryStat] {
        guard s.expenses > 0 else { return [] }
        let sorted = s.byCategory.sorted { $0.value > $1.value }
        var out: [CategoryStat] = []
        for (i, entry) in sorted.prefix(5).enumerated() {
            out.append(CategoryStat(keys: [entry.key],
                                    name: AnalyticsCategoryDisplay.label(entry.key),
                                    amount: entry.value,
                                    share: entry.value / s.expenses,
                                    color: CategoryStat.palette[i % CategoryStat.palette.count]))
        }
        let rest = sorted.dropFirst(5)
        if !rest.isEmpty {
            let amount = rest.reduce(0) { $0 + $1.value }
            out.append(CategoryStat(keys: rest.map(\.key),
                                    name: String(localized: "ana_cat_rest"),
                                    amount: amount,
                                    share: amount / s.expenses,
                                    color: Color.primary.opacity(0.25)))
        }
        return out
    }

    private func openDrilldown(_ cat: CategoryStat, stats: MonthFinanceStats) {
        let items = stats.items
            .filter { cat.keys.contains($0.categoryKey) }
            .sorted { $0.date > $1.date }
        guard !items.isEmpty else { return }
        HapticFeedback.selection()
        drilldown = CategoryDrilldown(title: cat.name, monthTitle: monthLabel, items: items)
    }

    private func categoryCard(_ categoryData: [CategoryStat], stats: MonthFinanceStats) -> some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Expenses by category")
                    .font(AppFont.subheadline)

                HStack(alignment: .center, spacing: 16) {
                    Chart(categoryData) { cat in
                        SectorMark(
                            angle: .value("Amount", cat.amount),
                            innerRadius: .ratio(0.60),
                            angularInset: 2
                        )
                        .foregroundStyle(cat.color)
                        .cornerRadius(4)
                    }
                    .chartAngleSelection(value: $donutSelection)
                    .onChange(of: donutSelection) { _, raw in
                        guard let raw else { return }
                        // Map the tapped angle back to its slice (slices are
                        // laid out in data order, spanning cumulative sums).
                        var cursor = 0.0
                        for cat in categoryData {
                            cursor += cat.amount
                            if raw <= cursor {
                                openDrilldown(cat, stats: stats)
                                break
                            }
                        }
                        donutSelection = nil
                    }
                    .frame(width: 110, height: 110)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categoryData) { cat in
                            Button {
                                openDrilldown(cat, stats: stats)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(cat.color).frame(width: 8, height: 8)
                                    Text(verbatim: cat.name)
                                        .font(AppFont.scaled(12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(verbatim: "\(Int((cat.share * 100).rounded()))%")
                                        .font(AppFont.scaled(10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                    Text(money(cat.amount))
                                        .font(AppFont.captionStrong)
                                        .foregroundStyle(.primary)
                                        .monospacedDigit()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: cat.name))
                            .accessibilityValue(Text(verbatim: "\(money(cat.amount)), \(Int((cat.share * 100).rounded()))%"))
                            .accessibilityHint(Text("ana_category_hint"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if stats.receiptExpenses > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(AppFont.scaled(9))
                        Text("ana_includes_receipts")
                            .font(AppFont.scaled(10))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Year pulse

    @ViewBuilder
    private var yearPulse: some View {
        let year = cal.component(.year, from: displayedMonth)
        let months = yearMonths(year)
        let total = months.reduce(0) { $0 + $1.amount }
        YearPulseCard(year: String(year), months: months, total: money(total))
    }

    /// The displayed year's twelve expense totals — records + receipts,
    /// converted, same merged ledger as everything else on this tab.
    private func yearMonths(_ year: Int) -> [YearPulseCard.Month] {
        var totals = [Double](repeating: 0, count: 12)
        for r in service.records where r.type == "expense" {
            guard let d = AppDate.day(from: r.date),
                  cal.component(.year, from: d) == year else { continue }
            totals[cal.component(.month, from: d) - 1] += convertToPreferred(r.amount, from: r.currency)
        }
        for r in receiptService.receipts {
            guard r.total > 0, let d = AppDate.day(from: r.date),
                  cal.component(.year, from: d) == year else { continue }
            totals[cal.component(.month, from: d) - 1] += r.total
        }
        let displayedIndex = cal.component(.month, from: displayedMonth)
        return (1...12).map { m in
            YearPulseCard.Month(index: m, amount: totals[m - 1], isDisplayed: m == displayedIndex)
        }
    }
}

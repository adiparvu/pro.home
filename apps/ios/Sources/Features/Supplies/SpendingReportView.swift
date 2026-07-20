import SwiftUI
import Charts

// MARK: - Spending Report View

struct SpendingReportView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    private func money(_ amount: Double, whole: Bool = false) -> String {
        CurrencyService.money(amount, code: appSettings.preferredCurrency, whole: whole)
    }

    enum ReportPeriod: String, CaseIterable {
        case daily, weekly, monthly, yearly
        var label: String {
            switch self {
            case .daily:   return String(localized: "report_period_daily")
            case .weekly:  return String(localized: "report_period_weekly")
            case .monthly: return String(localized: "report_period_monthly")
            case .yearly:  return String(localized: "report_period_yearly")
            }
        }
    }

    @State private var period: ReportPeriod = .monthly
    @State private var selectedMonth: String = ""
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        periodPicker
                        switch period {
                        case .daily:   dailyReport
                        case .weekly:  weeklyReport
                        case .monthly: monthlyReport
                        case .yearly:  yearlyReport
                        }
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle(String(localized: "report_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if selectedMonth.isEmpty { selectedMonth = receiptService.currentMonthKey }
        }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        GlassCard(padding: 4) {
            HStack(spacing: 0) {
                ForEach(ReportPeriod.allCases, id: \.self) { p in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { period = p }
                        HapticFeedback.selection()
                    } label: {
                        Text(p.label)
                            .font(AppFont.scaled(13, weight: period == p ? .semibold : .regular))
                            .foregroundStyle(period == p ? Color(UIColor.systemBackground) : Color.primary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(period == p ? Color.accentColor : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.xxs)
        }
    }

    // MARK: - Daily report (last 30 days)

    private var dailyReport: some View {
        let days = last30Days()
        let topCats = receiptService.spendByCategory(in: selectedMonth)
        return VStack(spacing: 16) {
            if !days.isEmpty {
                reportChartCard(title: String(localized: "report_last_30"), data: days, unit: .day)
            }
            summaryCards(total: days.reduce(0) { $0 + $1.total }, count: receiptsDays(days).count, label: String(localized: "report_days"))
            if !topCats.isEmpty { categoryBreakdown(topCats) }
        }
    }

    // MARK: - Weekly report

    private var weeklyReport: some View {
        let weeks = receiptService.spendByWeek(in: selectedMonth)
        let total = weeks.reduce(0) { $0 + $1.total }
        return VStack(spacing: 16) {
            monthPicker
            if !weeks.isEmpty {
                reportChartCard(title: String(localized: "report_weekly_breakdown"), data: weeks, unit: .weekOfYear)
            } else { emptyState }
            summaryCards(total: total, count: weeks.count, label: String(localized: "report_weeks"))
            let cats = receiptService.spendByCategory(in: selectedMonth)
            if !cats.isEmpty { categoryBreakdown(cats) }
        }
    }

    // MARK: - Monthly report

    private var monthlyReport: some View {
        let months = last12Months()
        return VStack(spacing: 16) {
            if !months.isEmpty {
                reportChartCard(title: String(localized: "report_last_12"), data: months, unit: .month)
            }
            summaryCards(
                total: months.reduce(0) { $0 + $1.total },
                count: receiptService.receipts.count,
                label: String(localized: "expense_receipts")
            )
            let cats = overallCategoryBreakdown()
            if !cats.isEmpty { categoryBreakdown(cats) }
        }
    }

    // MARK: - Yearly report

    private var yearlyReport: some View {
        let data = receiptService.spendForYear(selectedYear)
        let years = availableYears()
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    if years.first.map({ selectedYear > $0 }) ?? false {
                        selectedYear -= 1; HapticFeedback.selection()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(AppFont.captionEmphasis).foregroundStyle(.secondary)
                        .frame(width: 32, height: 32).background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(selectedYear)").font(AppFont.subheadline)
                Spacer()
                Button {
                    if selectedYear < Calendar.current.component(.year, from: Date()) {
                        selectedYear += 1; HapticFeedback.selection()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(selectedYear < Calendar.current.component(.year, from: Date()) ? .secondary : Color.primary.opacity(0.2))
                        .frame(width: 32, height: 32).background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xxs)

            if !data.isEmpty {
                reportChartCard(title: String(format: String(localized: "report_year_spending"), selectedYear), data: data, unit: .month)
            } else { emptyState }
            summaryCards(total: data.reduce(0) { $0 + $1.total }, count: receiptsForYear(), label: String(localized: "expense_receipts"))
        }
    }

    // MARK: - Helpers

    private var monthPicker: some View {
        HStack(spacing: 12) {
            Button {
                selectedMonth = receiptService.previousMonthKey(from: selectedMonth)
                HapticFeedback.selection()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppFont.captionEmphasis).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32).background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")
            Spacer()
            Text(LocalizedStringKey(receiptService.monthDisplayName(selectedMonth))).font(AppFont.subheadline)
            Spacer()
            Button {
                let next = receiptService.nextMonthKey(from: selectedMonth)
                if next != selectedMonth { selectedMonth = next; HapticFeedback.selection() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(selectedMonth == receiptService.currentMonthKey ? Color.primary.opacity(0.2) : .secondary)
                    .frame(width: 32, height: 32).background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(selectedMonth == receiptService.currentMonthKey)
            .accessibilityLabel("Next month")
        }
    }

    private func reportChartCard(title: String, data: [DailySpend], unit: Calendar.Component) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(AppFont.captionStrong).foregroundStyle(.secondary).tracking(0.8)

                let calUnit: Calendar.Component = unit
                Chart(data) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: calUnit),
                        y: .value("Amount", day.total)
                    )
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks { val in
                        if let date = val.as(Date.self) {
                            AxisValueLabel {
                                switch unit {
                                case .month:
                                    Text(date, format: .dateTime.month(.abbreviated)).font(AppFont.scaled(9))
                                case .weekOfYear:
                                    Text("W\(Calendar.current.component(.weekOfYear, from: date))").font(AppFont.scaled(9))
                                default:
                                    Text(date, format: .dateTime.day().month(.abbreviated)).font(AppFont.scaled(9))
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        if let v = val.as(Double.self) {
                            AxisValueLabel { Text(verbatim: money(v, whole: true)).font(AppFont.scaled(9)) }
                        }
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                    }
                }
                .frame(height: 150)

                let maxDay = data.max(by: { $0.total < $1.total })
                let minDay = data.filter { $0.total > 0 }.min(by: { $0.total < $1.total })
                if let maxDay, let minDay {
                    HStack {
                        statBadge(icon: "arrow.up.circle.fill", value: money(maxDay.total), color: .orange)
                        Spacer()
                        statBadge(icon: "arrow.down.circle.fill", value: money(minDay.total), color: Color.brandSuccess)
                    }
                }
            }
        }
    }

    private func statBadge(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(AppFont.scaled(11)).foregroundStyle(color)
            Text(value).font(AppFont.captionStrong).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func summaryCards(total: Double, count: Int, label: String) -> some View {
        HStack(spacing: 12) {
            GlassCard(padding: 14) {
                VStack(spacing: 4) {
                    Text(verbatim: money(total))
                        .font(AppFont.scaled(20, weight: .bold, design: .rounded)).foregroundStyle(.primary).monospacedDigit()
                    Text(String(localized: "report_total_spent")).font(AppFont.scaled(11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            GlassCard(padding: 14) {
                VStack(spacing: 4) {
                    Text("\(count)").font(AppFont.scaled(20, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                    Text(label).font(AppFont.scaled(11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func categoryBreakdown(_ cats: [CategorySpend]) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "expense_section_categories"))
                    .font(AppFont.captionStrong).foregroundStyle(.secondary).tracking(0.8)

                let total = cats.reduce(0) { $0 + $1.total }
                ForEach(cats.prefix(8)) { cat in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: cat.icon).font(AppFont.scaled(11)).foregroundStyle(cat.color)
                            Text(cat.label).font(AppFont.scaled(13, weight: .medium))
                            Spacer()
                            Text(verbatim: money(cat.total)).font(AppFont.captionStrong).foregroundStyle(.secondary).monospacedDigit()
                            let pct = total > 0 ? cat.total / total * 100 : 0
                            Text(String(format: "%.0f%%", pct))
                                .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
                                .frame(width: 35, alignment: .trailing)
                        }
                        // Share bar without GeometryReader: scale a full-width fill.
                        let frac = total > 0 ? cat.total / total : 0
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(AppOpacity.subtleFill))
                            .frame(height: 5)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(cat.color)
                                    .scaleEffect(x: frac, y: 1, anchor: .leading)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(icon: "chart.bar", title: "report_no_data")
    }

    // MARK: - Data helpers

    private func last30Days() -> [DailySpend] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return [] }
        var grouped: [String: (Date, Double)] = [:]
        for r in receiptService.receipts {
            guard let date = AppDate.day(from: r.date), date >= cutoff else { continue }
            grouped[r.date] = (date, (grouped[r.date]?.1 ?? 0) + r.total)
        }
        return grouped.map { DailySpend(id: $0.key, date: $0.value.0, total: $0.value.1) }.sorted { $0.date < $1.date }
    }

    private func last12Months() -> [DailySpend] {
        var grouped: [String: (Date, Double)] = [:]
        for r in receiptService.receipts {
            let key = String(r.date.prefix(7))
            guard let date = AppDate.monthKey.date(from: key) else { continue }
            grouped[key] = (date, (grouped[key]?.1 ?? 0) + r.total)
        }
        return grouped.map { DailySpend(id: $0.key, date: $0.value.0, total: $0.value.1) }.sorted { $0.date < $1.date }.suffix(12).map { $0 }
    }

    private func receiptsDays(_ days: [DailySpend]) -> Set<String> { Set(days.map { $0.id }) }

    private func overallCategoryBreakdown() -> [CategorySpend] {
        var grouped: [String: Double] = [:]
        for r in receiptService.receipts { grouped[r.category, default: 0] += r.total }
        return grouped.map { CategorySpend(id: $0.key, category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }

    private func availableYears() -> [Int] {
        var years = Set<Int>()
        for r in receiptService.receipts {
            if let date = AppDate.day(from: r.date) { years.insert(Calendar.current.component(.year, from: date)) }
        }
        let current = Calendar.current.component(.year, from: Date())
        years.insert(current)
        return years.sorted()
    }

    private func receiptsForYear() -> Int {
        receiptService.receipts.filter { $0.date.hasPrefix("\(selectedYear)") }.count
    }
}

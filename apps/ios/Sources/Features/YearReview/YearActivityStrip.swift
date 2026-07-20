import SwiftUI
import Charts

// MARK: - The year's visual spine — 12 months of real activity
//
// One bar per month combining tasks completed + photos captured + expenses
// recorded, tinted by the month's dominant activity. Tapping a month expands
// an inline summary of exactly what that month held — only the counts that
// are non-zero, per the page's honesty law. Chart styling follows the app's
// existing Swift Charts conventions (Finances / Supplies).

struct YearActivityStrip: View {
    let months: [YearMonthActivity]
    /// Localized month symbols, index 0 = January (built by the parent from
    /// the app locale so the strip stays allocation-free).
    let monthSymbols: [String]
    /// Renders the dominant-currency amount for the expanded month.
    let moneyDisplay: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedKey: String?
    /// Per-month grow-in progress (0→1): the bars rise one after another
    /// with a springy stagger when the strip appears (IMG_8712 "movement").
    @State private var barProgress: [Int: Double] = [:]

    private var selectedMonth: YearMonthActivity? {
        guard let selectedKey, let m = Int(selectedKey) else { return nil }
        return months.first { $0.month == m }
    }

    private static func tint(_ kind: YearMonthActivity.Kind) -> Color {
        switch kind {
        case .tasks:    return Color.brandSuccess
        case .photos:   return .orange
        case .expenses: return Color.brandPurple
        }
    }

    private func symbol(_ month: Int) -> String {
        let idx = month - 1
        guard monthSymbols.indices.contains(idx) else { return "\(month)" }
        return monthSymbols[idx]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("year_activity_title")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            VStack(alignment: .leading, spacing: 12) {
                chart
                legend
                if let month = selectedMonth {
                    monthSummary(month)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(AppSpacing.base)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selectedKey)
        }
    }

    // MARK: Chart

    private var domain: [String] { months.map { String($0.month) } }

    private var chart: some View {
        Chart(months) { m in
            BarMark(
                x: .value("Month", String(m.month)),
                y: .value("Activity", Double(m.total) * (barProgress[m.month] ?? 0)),
                width: .ratio(0.55)
            )
            .foregroundStyle(Self.tint(m.dominant).opacity(barOpacity(m)))
            .cornerRadius(3)
        }
        .onAppear { growBarsIn() }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedKey)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: domain) { value in
                AxisValueLabel {
                    if let key = value.as(String.self), let m = Int(key) {
                        Text(verbatim: String(symbol(m).prefix(1)).uppercased())
                            .font(AppFont.scaled(9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 110)
        .accessibilityLabel(Text("year_activity_title"))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
    }

    private func barOpacity(_ m: YearMonthActivity) -> Double {
        guard selectedKey != nil else { return 1 }
        return selectedKey == String(m.month) ? 1 : 0.35
    }

    /// January → December, each bar springing up 50ms after the previous —
    /// the year "plays" left to right. Reduce Motion fills instantly.
    private func growBarsIn() {
        guard reduceMotion else {
            for (index, m) in months.enumerated() {
                withAnimation(.spring(duration: 0.55, bounce: 0.35)
                    .delay(Double(index) * 0.05)) {
                    barProgress[m.month] = 1
                }
            }
            return
        }
        for m in months { barProgress[m.month] = 1 }
    }

    /// "March: 5, April: 2, …" for VoiceOver — only months with activity.
    private var accessibilitySummary: String {
        months.filter { $0.total > 0 }
            .map { "\(symbol($0.month)): \($0.total)" }
            .joined(separator: ", ")
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Self.tint(.tasks), label: "Tasks completed")
            legendItem(color: Self.tint(.photos), label: "Photos captured")
            legendItem(color: Self.tint(.expenses), label: "year_legend_expenses")
        }
    }

    private func legendItem(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(AppFont.scaled(10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Selected-month summary

    private func monthSummary(_ month: YearMonthActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: symbol(month.month).capitalized)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
            if month.total == 0 {
                Text("year_activity_empty")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            } else {
                if month.tasksDone > 0 {
                    summaryLine(tint: Self.tint(.tasks),
                                text: String(format: String(localized: "year_tasks_count_fmt"),
                                             month.tasksDone))
                }
                if month.photos > 0 {
                    summaryLine(tint: Self.tint(.photos),
                                text: String(format: String(localized: "year_photos_fmt"),
                                             month.photos))
                }
                if month.expenseCount > 0 {
                    summaryLine(tint: Self.tint(.expenses),
                                text: month.expenseTotal > 0
                                    ? String(format: String(localized: "year_expenses_fmt"),
                                             month.expenseCount, moneyDisplay(month.expenseTotal))
                                    : String(format: String(localized: "year_expenses_count_fmt"),
                                             month.expenseCount))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private func summaryLine(tint: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(verbatim: text)
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
        }
    }
}

import SwiftUI
import Charts

// MARK: - Category breakdown (top expense categories of the month)
//
// Answers "where did the money go" at a glance: the month's biggest expense
// categories with their share of total spending. Hidden entirely when the
// month has no expenses — an empty chart teaches nothing.

struct CategoryBreakdownSection: View {
    struct Item: Identifiable {
        let category: String
        let amount: Double
        /// This category's fraction of the month's total spending (0…1).
        let share: Double
        var id: String { category }
    }

    let items: [Item]
    let format: (Double) -> String

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("fin_categories_header")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.4))

                VStack(spacing: AppSpacing.base) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            .padding(AppSpacing.lg)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
    }

    private func row(_ item: Item) -> some View {
        let style = catStyle(item.category)
        return HStack(spacing: AppSpacing.md) {
            Image(systemName: style.icon)
                .font(AppFont.caption)
                .foregroundStyle(style.color)
                .frame(width: 32, height: 32)
                .glassRoundedRect(AppRadius.sm)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(LocalizedStringKey(item.category.capitalized))
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(format(item.amount))
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                // Share bar without GeometryReader: scale a full-width fill.
                Capsule()
                    .fill(style.color.opacity(0.15))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(style.color)
                            .scaleEffect(x: max(0.02, item.share), y: 1, anchor: .leading)
                    }
                    .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: format(item.amount)))
    }
}

// MARK: - Six-month trend (income vs. expenses)

struct SixMonthTrendSection: View {
    struct Point: Identifiable {
        let monthStart: Date
        let label: String
        let isIncome: Bool
        let amount: Double
        /// False when the month has no records at all — "no history" is drawn
        /// as a dim tick so it never masquerades as "earned/spent zero".
        let hasData: Bool
        var id: String { "\(monthStart.timeIntervalSinceReferenceDate)-\(isIncome)" }
    }

    let points: [Point]

    /// Axis labels of months without any recorded history (dimmed).
    private var noDataLabels: Set<String> {
        Set(points.lazy.filter { !$0.hasData }.map(\.label))
    }

    var body: some View {
        if points.contains(where: { $0.amount > 0 }) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("fin_trend_header")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.4))

                Chart(points) { point in
                    if point.hasData {
                        BarMark(
                            x: .value("Month", point.label),
                            y: .value("Amount", point.amount),
                            width: .ratio(0.35)
                        )
                        .foregroundStyle(point.isIncome ? Color.brandSuccess : Color.red.opacity(0.85))
                        .position(by: .value("Kind", point.isIncome ? "income" : "expense"))
                        .cornerRadius(3)
                    } else if point.isIncome {
                        // One dim tick per no-history month, drawn at the
                        // baseline: distinct from a real zero-height bar.
                        PointMark(
                            x: .value("Month", point.label),
                            y: .value("Amount", 0.0)
                        )
                        .symbolSize(14)
                        .foregroundStyle(Color.primary.opacity(0.22))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(isNoDataMonth(value) ? 0.18 : 0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel()
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                .frame(height: 150)

                HStack(spacing: AppSpacing.lg) {
                    legendDot(color: Color.brandSuccess, label: "Income")
                    legendDot(color: Color.red.opacity(0.85), label: "Expenses")
                    if !noDataLabels.isEmpty {
                        legendDot(color: Color.primary.opacity(0.25), label: "fin_trend_no_data")
                    }
                }
            }
            .padding(AppSpacing.lg)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
    }

    private func isNoDataMonth(_ value: AxisValue) -> Bool {
        guard let label = value.as(String.self) else { return false }
        return noDataLabels.contains(label)
    }

    private func legendDot(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(0.5))
        }
    }
}

import SwiftUI
import Charts

// MARK: - Top merchants ("Top comercianți")
//
// The month's biggest stores by scanned-receipt spend. Receipts are the only
// source that knows a store name, so the card exists exactly when receipts
// exist — never estimated from record titles.

struct TopMerchantsCard: View {
    struct Merchant: Identifiable {
        let name: String
        let amount: Double
        let visits: Int
        var id: String { name }
    }

    let merchants: [Merchant]
    /// Formats an amount in the preferred currency.
    let format: (Double) -> String

    var body: some View {
        if !merchants.isEmpty {
            let top = merchants.first?.amount ?? 1
            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ana_top_merchants")
                        .font(AppFont.subheadline)

                    ForEach(merchants) { m in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(verbatim: m.name)
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if m.visits > 1 {
                                    Text(verbatim: "×\(m.visits)")
                                        .font(AppFont.scaled(10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                                Spacer()
                                Text(format(m.amount))
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                            }
                            // Share bar without GeometryReader: scale a
                            // full-width fill (the Finances-module pattern).
                            Capsule()
                                .fill(Color.brandPrimaryBlue.opacity(0.15))
                                .frame(height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.brandPrimaryBlue)
                                        .scaleEffect(x: max(0.02, top > 0 ? m.amount / top : 0),
                                                     y: 1, anchor: .leading)
                                }
                                .clipShape(Capsule())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(Text(verbatim: format(m.amount)))
                    }
                }
            }
        }
    }
}

// MARK: - Category drill-down
//
// Tapping a donut slice (or its legend row) opens the real transactions
// behind the number — the month's records and receipts of that category,
// newest first. Nothing summarized here isn't listed below it.

struct CategoryDrilldown: Identifiable {
    let id = UUID()
    /// Localized category display name (sheet title).
    let title: String
    /// "Iulie 2026" style month label.
    let monthTitle: String
    let items: [MonthExpenseItem]
}

struct CategoryDrilldownSheet: View {
    let drilldown: CategoryDrilldown
    /// Formats an amount in the preferred currency.
    let format: (Double) -> String
    @Environment(\.dismiss) private var dismiss

    private var total: Double { drilldown.items.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: AppSpacing.sm) {
                    HStack {
                        Text(verbatim: drilldown.monthTitle)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(format(total))
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, AppSpacing.xxs)
                    .padding(.bottom, AppSpacing.xs)

                    ForEach(drilldown.items) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.xxl)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(Text(verbatim: drilldown.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ item: MonthExpenseItem) -> some View {
        let style = catStyle(item.categoryKey)
        return HStack(spacing: AppSpacing.md) {
            Image(systemName: item.isReceipt ? "doc.text.viewfinder" : style.icon)
                .font(AppFont.caption)
                .foregroundStyle(style.color)
                .frame(width: 32, height: 32)
                .glassRoundedRect(AppRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: AppDate.monthDay.string(from: item.date))
                    if item.isReceipt {
                        Text(verbatim: "·")
                        Text("ana_receipt_badge")
                    }
                }
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(0.4))
            }

            Spacer()

            Text(format(item.amount))
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Year pulse ("An curent" mini sparkline)
//
// A compact row: the displayed month's year, its twelve expense totals as a
// mini bar chart, and the year total. Only rendered once at least two months
// of that year carry data — one bar teaches nothing.

struct YearPulseCard: View {
    struct Month: Identifiable {
        let index: Int          // 1-based calendar month
        let amount: Double
        let isDisplayed: Bool   // the month currently shown by the navigator
        var id: Int { index }
    }

    let year: String
    let months: [Month]
    let total: String

    var body: some View {
        if months.filter({ $0.amount > 0 }).count >= 2 {
            GlassCard(padding: 14) {
                HStack(spacing: AppSpacing.base) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: year)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text("ana_year_total")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(.secondary)
                    }

                    Chart(months) { m in
                        BarMark(
                            x: .value("Month", m.index),
                            y: .value("Expenses", m.amount),
                            width: .ratio(0.55)
                        )
                        .foregroundStyle(m.isDisplayed
                                         ? Color.accentColor
                                         : Color.accentColor.opacity(0.3))
                        .cornerRadius(1.5)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartXScale(domain: 0.5...12.5)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)

                    Text(verbatim: total)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(year): \(total)"))
        }
    }
}

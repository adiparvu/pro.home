import SwiftUI
import Charts

// MARK: - One month of finance data, in the preferred currency
//
// Built in a single pass over the month's records AND scanned receipts
// (FinancesSection.stats) — every card on the Analytics finances tab reads
// from this instead of re-filtering the source lists per property access.
// Receipts are part of the ledger here: their categories ("food",
// "cleaning", …) are what the category donut used to silently drop.

struct MonthFinanceStats {
    var income: Double = 0
    var expenses: Double = 0
    /// Canonical category key (AnalyticsCategoryDisplay) → converted expense total.
    var byCategory: [String: Double] = [:]
    /// Day of month (1-based) → converted expense total.
    var byDay: [Int: Double] = [:]
    /// Store name → receipt spend (receipts only).
    var byMerchant: [String: Double] = [:]
    /// Store name → number of receipts (receipts only).
    var merchantVisits: [String: Int] = [:]
    /// Every expense of the month, records and receipts alike — the category
    /// drill-down list and the outlier insight read these.
    var items: [MonthExpenseItem] = []
    /// The part of `expenses` contributed by scanned receipts.
    var receiptExpenses: Double = 0
}

/// One real expense of the month — a financial record or a scanned receipt.
struct MonthExpenseItem: Identifiable {
    let id: String
    let title: String
    /// Canonical category key (AnalyticsCategoryDisplay.normalize).
    let categoryKey: String
    let date: Date
    /// Converted to the preferred currency.
    let amount: Double
    let isReceipt: Bool
}

// MARK: - Auto insight

struct MonthInsight: Identifiable {
    let icon: String
    let color: Color
    let text: String
    var id: String { text }
}

struct MonthInsightsCard: View {
    let insights: [MonthInsight]

    var body: some View {
        if !insights.isEmpty {
            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ana_insights_header")
                        .font(AppFont.subheadline)

                    ForEach(insights) { insight in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: insight.icon)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(insight.color)
                                .frame(width: 18)
                            Text(insight.text)
                                .font(AppFont.scaled(13))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Daily spending rhythm

struct DailySpendCard: View {
    struct Day: Identifiable {
        let day: Int
        let amount: Double
        var id: Int { day }
    }

    let days: [Day]
    /// The heaviest spending day — drawn in full accent, the rest muted.
    let peakDay: Int?

    var body: some View {
        if days.contains(where: { $0.amount > 0 }) {
            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ana_daily_header")
                        .font(AppFont.subheadline)

                    Chart(days) { day in
                        BarMark(
                            x: .value("Day", day.day),
                            y: .value("Amount", day.amount),
                            width: .ratio(0.55)
                        )
                        .foregroundStyle(day.day == peakDay
                                         ? Color.accentColor
                                         : Color.accentColor.opacity(0.35))
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: [1, 8, 15, 22, 29]) { _ in
                            AxisValueLabel()
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(0.4))
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 70)
                }
            }
        }
    }
}

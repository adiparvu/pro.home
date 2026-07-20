import SwiftUI

// MARK: - Expense forecast
//
// Next month, estimated from the last six FULL months of history — the
// current month is excluded because it is still being written. Currencies
// never mix: each gets its own forecast, and a currency needs at least two
// months of history before we dare to estimate (one month is an anecdote).
// The label always says "estimate" — this is arithmetic, not prophecy.

struct ExpenseForecast {
    struct CurrencyForecast: Identifiable {
        let code: String
        let average: Double
        let low: Double
        let high: Double
        let monthsOfData: Int
        let topCategories: [(category: String, average: Double)]
        var id: String { code }
    }

    /// Per-currency forecasts, biggest spender first.
    static func compute(records: [FinancialRecord], now: Date = Date()) -> [CurrencyForecast] {
        let cal = Calendar.current
        guard let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let windowStart = cal.date(byAdding: .month, value: -6, to: currentMonthStart) else {
            return []
        }

        // Expenses inside the six full months before this one.
        let window = records.filter { r in
            guard r.type == "expense", let d = AppDate.day(from: r.date) else { return false }
            return d >= windowStart && d < currentMonthStart
        }
        guard !window.isEmpty else { return [] }

        return Dictionary(grouping: window, by: \.currency).compactMap { code, rows in
            // Monthly totals — only months that actually have records count,
            // so a gap month doesn't drag the average toward zero.
            let byMonth = Dictionary(grouping: rows) { String($0.date.prefix(7)) }
            let totals = byMonth.values.map { $0.reduce(0) { $0 + $1.amount } }
            guard totals.count >= 2 else { return nil }

            let byCategory = Dictionary(grouping: rows, by: \.category)
                .map { (category: $0.key,
                        average: $0.value.reduce(0) { $0 + $1.amount } / Double(totals.count)) }
                .sorted { $0.average > $1.average }

            return CurrencyForecast(
                code: code,
                average: totals.reduce(0, +) / Double(totals.count),
                low: totals.min() ?? 0,
                high: totals.max() ?? 0,
                monthsOfData: totals.count,
                topCategories: Array(byCategory.prefix(3)))
        }
        .sorted { $0.average > $1.average }
    }
}

// MARK: - Section for the Finances screen

struct ExpenseForecastSection: View {
    let records: [FinancialRecord]

    // Computed once per data change, not per body evaluation — the Finances
    // screen re-renders on every scroll tick (tab-bar visibility), and
    // regrouping a thousand records per frame would be paid in dropped ones.
    @State private var forecasts: [ExpenseForecast.CurrencyForecast] = []

    var body: some View {
        content
            .onAppear { forecasts = ExpenseForecast.compute(records: records) }
            .onChange(of: records.count) { _, _ in
                forecasts = ExpenseForecast.compute(records: records)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !forecasts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.purple)
                    Text("forecast_title")
                        .font(AppFont.footnoteEmphasis)
                    Spacer()
                }
                ForEach(forecasts) { f in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "≈ \(CurrencyService.money(f.average, code: f.code))")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                            Spacer()
                            Text("forecast_months \(f.monthsOfData)")
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                        }
                        // The honest range: the best and worst real months.
                        Text("forecast_range \(CurrencyService.money(f.low, code: f.code)) \(CurrencyService.money(f.high, code: f.code))")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                        ForEach(f.topCategories, id: \.category) { cat in
                            HStack {
                                Text(LocalizedStringKey(cat.category.capitalized))
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                Spacer()
                                Text(CurrencyService.money(cat.average, code: f.code))
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .liquidGlass(cornerRadius: AppRadius.lg)
                }
                Text("forecast_disclaimer")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }
}

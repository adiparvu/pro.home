import SwiftUI

// MARK: - Upcoming recurring payments ("Urmează la plată")
//
// The next few real due dates, computed at read time from the two recurring
// sources the backend actually has:
//  - financial-record templates (`is_recurring` + `next_occurrence`,
//    migration 015) — the daily pg_cron job advances these, we only read them;
//  - active tenant leases (`monthly_rent` + `payment_day`, migration 105).
//
// Honesty rules: nothing is persisted, nothing is estimated. A household with
// no recurring records and no leases never sees this section, and lease dues
// stop at `lease_end`.

/// One upcoming due date, already converted to the preferred currency.
struct UpcomingPaymentItem: Identifiable {
    enum Kind {
        case record(title: String)
        case rent(tenantName: String?)
    }

    let id: String
    let kind: Kind
    let category: String
    let date: Date
    let amount: Double
    let isIncome: Bool
}

struct UpcomingPaymentsSection: View {
    let items: [UpcomingPaymentItem]
    /// Formats an amount in the preferred currency (FinancesView.fmt).
    let format: (Double) -> String

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("fin_upcoming_header")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .textCase(.uppercase)
                    .kerning(0.5)

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

    private func row(_ item: UpcomingPaymentItem) -> some View {
        let style = catStyle(item.category)
        return HStack(spacing: AppSpacing.md) {
            Image(systemName: style.icon)
                .font(AppFont.caption)
                .foregroundStyle(style.color)
                .frame(width: 32, height: 32)
                .glassRoundedRect(AppRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                title(for: item.kind)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                dueLabel(for: item.date)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            Spacer()

            Text(verbatim: "\(item.isIncome ? "+" : "-")\(format(item.amount))")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(item.isIncome ? Color.brandSuccess : .primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func title(for kind: UpcomingPaymentItem.Kind) -> Text {
        switch kind {
        case .record(let title):
            return Text(verbatim: title)
        case .rent(let tenantName):
            if let tenantName {
                return Text("fin_upcoming_rent \(tenantName)")
            }
            return Text("fin_upcoming_rent_generic")
        }
    }

    private func dueLabel(for date: Date) -> Text {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Text("Today") }
        if cal.isDateInTomorrow(date) { return Text("Tomorrow") }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        return Text("fin_upcoming_date \(AppDate.monthDay.string(from: date)) \(days)")
    }
}

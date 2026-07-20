import SwiftUI
import Charts

// MARK: - Forecast Section
//
// Honesty contract for this tab:
//  - The projection IS a moving average — so it says so, in the header
//    caption and a footnote. No "AI" badge: no model runs here.
//  - "Already known" lists only deterministic amounts the backend really
//    holds (recurring record templates, active leases' rent due days, dated
//    documents with a value) — deterministic beats extrapolation.
//  - The trend chart draws every month of real history in the window (the
//    old query was hard-capped to the last 6 months keyed to `now` and mixed
//    currencies), and the 3-month extension is visually distinct and legended
//    as a projection.

struct ForecastSection: View {
    var financialService: FinancialService
    @Environment(ReceiptService.self) private var receiptService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(FamilyService.self) private var familyService
    @Environment(DocumentService.self) private var documentService

    private var cal: Calendar { Calendar.current }
    private var preferred: String { appSettings.preferredCurrency }

    private func money(_ v: Double) -> String {
        CurrencyService.money(v, code: preferred, whole: true)
    }

    private func convert(_ amount: Double, from code: String) -> Double {
        currencyService.convert(amount, from: code, to: preferred)
    }

    // MARK: Monthly history (merged ledger, converted)

    struct MonthPoint: Identifiable {
        let month: Date
        let income: Double
        let expenses: Double
        let isProjection: Bool
        var id: Date { month }
    }

    /// The last 12 calendar months ending with the current one — converted
    /// sums of financial records plus scanned receipts (the same merged
    /// ledger the Finances tab reads). Leading months with no data at all
    /// are dropped, so the chart starts where the history starts.
    private func history() -> [MonthPoint] {
        let currentStart = cal.startOfMonth(Date())
        guard let windowStart = cal.date(byAdding: .month, value: -11, to: currentStart) else { return [] }

        var buckets: [Date: (income: Double, expenses: Double)] = [:]
        for r in financialService.records {
            guard let d = AppDate.day(from: r.date), d >= windowStart else { continue }
            let m = cal.startOfMonth(d)
            guard m <= currentStart else { continue }
            var b = buckets[m] ?? (0, 0)
            let v = convert(r.amount, from: r.currency)
            if r.isIncome { b.income += v } else if r.type == "expense" { b.expenses += v }
            buckets[m] = b
        }
        for r in receiptService.receipts {
            // Receipts carry no currency column — captured in the household's
            // preferred currency (same treatment as the Finances tab).
            guard r.total > 0, let d = AppDate.day(from: r.date), d >= windowStart else { continue }
            let m = cal.startOfMonth(d)
            guard m <= currentStart else { continue }
            var b = buckets[m] ?? (0, 0)
            b.expenses += r.total
            buckets[m] = b
        }

        var points: [MonthPoint] = []
        var cursor = windowStart
        while cursor <= currentStart {
            let b = buckets[cursor] ?? (0, 0)
            points.append(MonthPoint(month: cursor, income: b.income,
                                     expenses: b.expenses, isProjection: false))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard let firstIdx = points.firstIndex(where: { $0.income > 0 || $0.expenses > 0 }) else {
            return []
        }
        return Array(points[firstIdx...])
    }

    // MARK: The stated method

    /// Plain monthly average over the most recent (up to six) FULL months
    /// with data — the current, still-being-written month never counts, and
    /// one month of history is an anecdote, not an average.
    struct AverageMethod {
        let monthsUsed: Int
        let avgIncome: Double
        let avgExpenses: Double
    }

    private func method(from history: [MonthPoint]) -> AverageMethod? {
        let currentStart = cal.startOfMonth(Date())
        let full = history.filter { $0.month < currentStart && ($0.income > 0 || $0.expenses > 0) }
        let used = full.suffix(6)
        guard used.count >= 2 else { return nil }
        return AverageMethod(
            monthsUsed: used.count,
            avgIncome: used.map(\.income).reduce(0, +) / Double(used.count),
            avgExpenses: used.map(\.expenses).reduce(0, +) / Double(used.count))
    }

    // MARK: Already-known upcoming amounts

    private struct KnownItem: Identifiable {
        enum Kind {
            case record(title: String)
            case rent(tenantName: String?)
            case document(name: String)
        }
        let id: String
        let kind: Kind
        let category: String
        let date: Date
        let amount: Double
        let isIncome: Bool
    }

    /// Deterministic dues in the next 90 days from the three dated sources
    /// the backend actually has. Nothing here is estimated.
    private func knownUpcoming(limit: Int = 6) -> [KnownItem] {
        let today = cal.startOfDay(for: Date())
        guard let horizon = cal.date(byAdding: .day, value: 90, to: today) else { return [] }
        var items: [KnownItem] = []

        // Recurring financial-record templates (migration 015) — the pg_cron
        // job advances next_occurrence; we only read it.
        for r in financialService.records where r.isRecurring == true {
            guard let ns = r.nextOccurrence, let due = AppDate.day(from: ns),
                  due >= today, due <= horizon else { continue }
            items.append(KnownItem(
                id: "record-\(r.id.uuidString)",
                kind: .record(title: r.title),
                category: r.category,
                date: due,
                amount: convert(r.amount, from: r.currency),
                isIncome: r.isIncome))
        }

        // Active tenant leases (monthly_rent + payment_day, migration 105).
        for lease in familyService.leases.values {
            guard let rent = lease.monthlyRent, rent > 0,
                  let day = lease.paymentDay, (1...31).contains(day),
                  !lease.hasEnded,
                  let due = Self.nextMonthlyDate(day: day, onOrAfter: today, calendar: cal),
                  due <= horizon else { continue }
            if let endStr = lease.leaseEnd, let end = AppDate.day(from: endStr), due > end { continue }
            if let startStr = lease.leaseStart, let start = AppDate.day(from: startStr), due < start { continue }
            let tenant = familyService.members.first { $0.id == lease.memberId }?.name
            items.append(KnownItem(
                id: "lease-\(lease.id.uuidString)",
                kind: .rent(tenantName: tenant),
                category: "rent",
                date: due,
                amount: convert(rent, from: lease.currency),
                isIncome: true))
        }

        // Dated documents with a captured value (insurance premiums, tax
        // deadlines, …) — renewal date first, expiry as the fallback.
        for doc in documentService.documents {
            guard let value = doc.value, value > 0,
                  let ds = doc.renewAt ?? doc.expiresAt,
                  let due = AppDate.day(from: ds),
                  due >= today, due <= horizon else { continue }
            items.append(KnownItem(
                id: "doc-\(doc.id.uuidString)",
                kind: .document(name: doc.name),
                category: Self.documentCategoryKey(doc.category),
                date: due,
                amount: convert(value, from: doc.currency ?? preferred),
                isIncome: false))
        }

        return Array(items.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// First occurrence of `day`-of-month on/after `date`, clamped to the
    /// month's length (a "31st" rent day falls on Feb 28/29, like Calendar).
    private static func nextMonthlyDate(day: Int, onOrAfter date: Date, calendar cal: Calendar) -> Date? {
        func clamped(in monthStart: Date) -> Date? {
            guard let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count else { return nil }
            var comps = cal.dateComponents([.year, .month], from: monthStart)
            comps.day = min(day, daysInMonth)
            return cal.date(from: comps)
        }
        let thisMonth = cal.startOfMonth(date)
        if let due = clamped(in: thisMonth), due >= date { return due }
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: thisMonth) else { return nil }
        return clamped(in: nextMonth)
    }

    /// Maps a document category to the finance icon vocabulary (catStyle).
    private static func documentCategoryKey(_ category: String) -> String {
        switch category {
        case "insurance": return "insurance"
        case "tax":       return "taxes"
        case "utility":   return "utilities"
        default:          return "other"
        }
    }

    // MARK: Body

    var body: some View {
        let hist = history()
        let avg = method(from: hist)
        let known = knownUpcoming()

        VStack(spacing: 16) {
            if let avg {
                projectionCard(avg)
            } else if !hist.isEmpty {
                needsHistoryCard
            }

            if !known.isEmpty {
                knownCard(known)
            }

            if !hist.isEmpty {
                trendCard(hist: hist, method: avg)
            }

            if financialService.records.isEmpty && receiptService.receipts.isEmpty {
                emptyCard
            }
        }
        .task {
            // Leases feed "already known" rent dues; loaded lazily because
            // most sessions never open this tab.
            if familyService.leases.isEmpty, let pid = PropertyService.activePropertyId {
                await familyService.loadLeases(propertyId: pid)
            }
        }
    }

    // MARK: Projection card

    private func projectionCard(_ m: AverageMethod) -> some View {
        let net = (m.avgIncome - m.avgExpenses) * 12
        return GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("12-month projection")
                            .font(AppFont.subheadline)
                        Text("ana_projection_method \(m.monthsUsed)")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    // The method, named — never an "AI" sparkle over arithmetic.
                    Label("ana_method_badge", systemImage: "chart.bar.xaxis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xxs)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }

                VStack(spacing: 12) {
                    ForecastRow(label: "Projected income",
                                value: money(m.avgIncome * 12),
                                sub: "ana_sub_annual", positive: true)
                    Divider().background(Color.primary.opacity(AppOpacity.subtleFill))
                    ForecastRow(label: "Projected expenses",
                                value: money(m.avgExpenses * 12),
                                sub: "ana_sub_annual", positive: false)
                    Divider().background(Color.primary.opacity(AppOpacity.subtleFill))
                    ForecastRow(label: "Estimated net profit",
                                value: "\(net >= 0 ? "+" : "")" + money(net),
                                sub: "ana_sub_estimated", positive: net >= 0)
                }

                Text("ana_projection_disclaimer")
                    .font(AppFont.scaled(10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var needsHistoryCard: some View {
        GlassCard(padding: 18) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "hourglass")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
                Text("ana_projection_needs_history")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Already-known card

    private func knownCard(_ items: [KnownItem]) -> some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ana_known_header")
                        .font(AppFont.subheadline)
                    Text("ana_known_sub")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(items) { item in
                    knownRow(item)
                }
            }
        }
    }

    private func knownRow(_ item: KnownItem) -> some View {
        let style = catStyle(item.category)
        return HStack(spacing: AppSpacing.md) {
            Image(systemName: style.icon)
                .font(AppFont.caption)
                .foregroundStyle(style.color)
                .frame(width: 32, height: 32)
                .glassRoundedRect(AppRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                knownTitle(for: item.kind)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                dueLabel(for: item.date)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            Spacer()

            Text(verbatim: "\(item.isIncome ? "+" : "-")\(money(item.amount))")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(item.isIncome ? Color.brandSuccess : .primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func knownTitle(for kind: KnownItem.Kind) -> Text {
        switch kind {
        case .record(let title):
            return Text(verbatim: title)
        case .rent(let tenantName):
            if let tenantName {
                return Text("fin_upcoming_rent \(tenantName)")
            }
            return Text("fin_upcoming_rent_generic")
        case .document(let name):
            return Text(verbatim: name)
        }
    }

    private func dueLabel(for date: Date) -> Text {
        if cal.isDateInToday(date) { return Text("Today") }
        if cal.isDateInTomorrow(date) { return Text("Tomorrow") }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        return Text("fin_upcoming_date \(AppDate.monthDay.string(from: date)) \(days)")
    }

    // MARK: Trend chart (history + projected extension)

    private func trendCard(hist: [MonthPoint], method: AverageMethod?) -> some View {
        // Projection bars: the stated method, drawn lighter and legended.
        var data = hist
        if let method {
            var cursor = cal.startOfMonth(Date())
            for _ in 0..<3 {
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
                data.append(MonthPoint(month: next, income: method.avgIncome,
                                       expenses: method.avgExpenses, isProjection: true))
            }
        }

        return GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Expense trend")
                    .font(AppFont.subheadline)

                Chart(data) { item in
                    BarMark(
                        x: .value("Month", item.month, unit: .month),
                        y: .value("Expenses", item.expenses)
                    )
                    .foregroundStyle(item.isProjection
                        ? AnyShapeStyle(Color.blue.opacity(0.22))
                        : AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.8), .blue.opacity(0.4)],
                                                       startPoint: .top, endPoint: .bottom)))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                            .foregroundStyle(Color.primary.opacity(0.05))
                        AxisValueLabel().foregroundStyle(.secondary).font(AppFont.scaled(10))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(.secondary).font(AppFont.scaled(10))
                    }
                }
                .frame(height: 130)

                if method != nil {
                    HStack(spacing: 16) {
                        legendDot(color: .blue.opacity(0.75), label: "Expenses")
                        legendDot(color: .blue.opacity(0.25), label: "ana_trend_projection_legend")
                    }
                }
            }
        }
    }

    private func legendDot(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Empty state

    private var emptyCard: some View {
        GlassCard(padding: 20) {
            VStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(AppFont.scaled(32))
                    .foregroundStyle(Color.primary.opacity(0.18))
                Text("Add financial records to see the forecast")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
    }
}

// MARK: - ForecastRow

struct ForecastRow: View {
    let label: LocalizedStringKey
    let value: String
    let sub: LocalizedStringKey
    let positive: Bool

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(positive ? Color.brandSuccess : .primary)
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

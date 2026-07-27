import SwiftUI
import Charts

// MARK: - Category icon map

private let categoryIcons: [String: (icon: String, color: Color)] = [
    "salary":      ("briefcase.fill",           .blue),
    "rent":        ("house.fill",               .purple),
    "utilities":   ("bolt.fill",                .yellow),
    "groceries":   ("cart.fill",                .green),
    "transport":   ("car.fill",                 .cyan),
    "healthcare":  ("cross.fill",               .red),
    "insurance":   ("shield.fill",              .indigo),
    "maintenance": ("wrench.and.screwdriver",   .orange),
    "mortgage":    ("house.and.flag.fill",      .purple),
    "investment":  ("chart.line.uptrend.xyaxis",.blue),
    "dining":      ("fork.knife",               .orange),
    "shopping":    ("bag.fill",                 .pink),
    "taxes":       ("building.columns.fill",    .brown),
    "supplies":    ("shippingbox.fill",         .mint),
    "other":       ("ellipsis.circle.fill",     Color.primary.opacity(0.6)),
]

func catStyle(_ category: String) -> (icon: String, color: Color) {
    categoryIcons[category.lowercased()] ?? ("ellipsis.circle.fill", Color.primary.opacity(AppOpacity.mediumText))
}

// MARK: - FinancesView sections

extension FinancesView {

    // MARK: Hero

    func heroSection(net: Double, insight: FinanceInsight?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                monthMenu

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        let next = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                        if next <= Date() { displayedMonth = next }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(isCurrentMonth ? Color.primary.opacity(0.15) : Color.primary.opacity(AppOpacity.secondaryText))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)
                .accessibilityLabel("Next month")
            }
            .padding(.top, AppSpacing.sm)

            VStack(spacing: 4) {
                Text(LocalizedStringKey(isCurrentMonth ? "Current month balance" : "Balance"))
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))

                Text(fmtSigned(net))
                    .font(AppFont.scaled(44, weight: .bold, design: .rounded))
                    .foregroundStyle(net >= 0 ? Color.primary : .red)
                    .contentTransition(.numericText(countsDown: net < 0))
                    .animation(.spring(response: 0.4), value: net)

                if let insight {
                    insightText(insight)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .multilineTextAlignment(.center)
                        .padding(.top, AppSpacing.xxs)
                        .transition(.opacity)
                }
            }
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.xxl)
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    /// Month label doubles as a jump menu (last 12 months) — the arrows stay
    /// for single steps, the menu removes the eleven-tap walk to last year.
    private var monthMenu: some View {
        Menu {
            ForEach(jumpMonths, id: \.self) { m in
                Button {
                    withAnimation(.spring(response: 0.3)) { displayedMonth = m }
                } label: {
                    if Calendar.current.isDate(m, equalTo: displayedMonth, toGranularity: .month) {
                        Label(monthMenuLabel(m), systemImage: "checkmark")
                    } else {
                        Text(monthMenuLabel(m))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(monthLabel)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .contentTransition(.identity)
                    .id(displayedMonth)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.scaled(9, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("fin_choose_month")
    }

    private var jumpMonths: [Date] {
        let cal = Calendar.current
        let current = cal.startOfMonth(Date())
        return (0..<12).compactMap { cal.date(byAdding: .month, value: -$0, to: current) }
    }

    private func monthMenuLabel(_ month: Date) -> String {
        AppDate.monthYear.string(from: month).capitalized
    }

    private func insightText(_ insight: FinanceInsight) -> Text {
        switch insight {
        case .comparison(let percent, let less, let previousMonth):
            return less
                ? Text("fin_insight_less_spent \(percent) \(previousMonth)")
                : Text("fin_insight_more_spent \(percent) \(previousMonth)")
        case .topCategory(let category, let amount):
            let name = String(localized: String.LocalizationValue(category.capitalized))
            return Text("fin_insight_top_category \(name) \(fmt(amount))")
        }
    }

    // MARK: KPI Strip

    /// The month's three numbers as pure data content — the tap-to-filter
    /// these tiles used to carry lives in the toolbar's one filter circle
    /// now (one-circle law), so the strip is a dashboard, never chrome.
    func kpiStrip(income: Double, expenses: Double) -> some View {
        HStack(spacing: 0) {
            kpiCell(label: "Income", value: fmt(income), color: Color.brandSuccess,
                    icon: "arrow.down.left")

            Divider().frame(height: 36).background(Color.primary.opacity(0.1))

            kpiCell(label: "Expenses", value: fmt(expenses), color: .red,
                    icon: "arrow.up.right")

            Divider().frame(height: 36).background(Color.primary.opacity(0.1))

            let savingsRate = income > 0 ? max(0, (income - expenses) / income * 100) : 0
            kpiCell(label: "Savings", value: String(format: "%.0f%%", savingsRate),
                    color: savingsRate >= 20 ? Color.brandSuccess : savingsRate >= 10 ? .orange : .red,
                    icon: "percent")
        }
        .padding(.vertical, AppSpacing.md)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .padding(.horizontal, AppSpacing.xl)
    }

    private func kpiCell(label: LocalizedStringKey, value: String, color: Color,
                         icon: String) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(AppFont.scaled(9, weight: .bold))
                    .foregroundStyle(color)
                Text(value)
                    .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: value)
            }
            Text(label)
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: Quick Actions

    var quickActionsRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BudgetView()
                    .environment(budgetService)
                    .environment(financialService)
            } label: {
                actionTile(icon: "chart.pie.fill", label: "Budget", color: .blue,
                           progress: budgetProgress)
            }
            .buttonStyle(.plain)

            NavigationLink { MortgageView() } label: {
                actionTile(icon: "house.and.flag.fill", label: "Mortgage", color: .purple)
            }
            .buttonStyle(.plain)
        }
    }

    /// Current-month budget usage, or nil when no budget is set — the same
    /// math as BudgetView's summary card so the two never disagree.
    private var budgetProgress: Double? {
        let total = budgetService.totalBudget()
        guard total > 0 else { return nil }
        return min(financialService.currentMonthExpenses / total, 1.0)
    }

    private func actionTile(icon: String, label: LocalizedStringKey, color: Color,
                            progress: Double? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .glassRoundedRect(10)
            Text(label)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
            Spacer()
            if let progress {
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(progress, 0.02))
                            .stroke(progress > 0.9 ? Color.red : progress > 0.7 ? Color.orange : color,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                    Text(verbatim: "\(Int((progress * 100).rounded()))%")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: String(format: String(localized: "%.0f%% used"),
                                                          progress * 100)))
            }
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    // MARK: Transaction List

    @ViewBuilder
    func transactionList(_ filtered: [FinancialRecord]) -> some View {
        if filtered.isEmpty {
            emptyState
        } else {
            // Lazy on purpose: this is the app's longest list — eager VStack
            // built every row (with a currency conversion each) on open.
            LazyVStack(spacing: 16) {
                ForEach(grouped(filtered), id: \.date) { group in
                    VStack(spacing: 0) {
                        HStack {
                            Text(groupDateLabel(group.date))
                                .font(AppFont.captionStrong)
                                .foregroundStyle(Color.primary.opacity(0.4))
                            Spacer()
                            let dayTotal = group.records.reduce(0.0) { sum, r in
                                let v = currencyService.convert(r.amount, from: r.currency, to: preferred)
                                return sum + (r.isIncome ? v : -v)
                            }
                            Text(fmtSigned(dayTotal))
                                .font(AppFont.captionStrong)
                                .foregroundStyle(dayTotal >= 0 ? Color.brandSuccess : .red)
                        }
                        .padding(.bottom, AppSpacing.sm)

                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { idx, record in
                                let displayAmt = currencyService.formatted(record.amount, from: record.currency, preferred: preferred)
                                FinancialRecordRow(record: record, displayAmount: displayAmt)
                                    // Long-press menu: rows live in a VStack, where
                                    // swipeActions is a List-only no-op — this is
                                    // the interaction that actually fires. Edit
                                    // opens the shared form seeded with the row
                                    // (audit fix: records were write-once).
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button {
                                            editingRecord = record
                                        } label: { Label("Edit", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await financialService.delete(record) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await financialService.delete(record) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                if idx < group.records.count - 1 {
                                    Divider().padding(.leading, 68).opacity(0.5)
                                }
                            }
                        }
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "banknote",
            title: "No transactions",
            message: "Add your first transaction by tapping +"
        )
    }

    // MARK: Helpers

    private var monthLabel: String {
        isCurrentMonth ? String(localized: "Current month") : monthMenuLabel(displayedMonth)
    }

    private func groupDateLabel(_ dateStr: String) -> String {
        guard let d = AppDate.day(from: dateStr) else { return dateStr }
        if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(d) { return String(localized: "Yesterday") }
        let out = DateFormatter(); out.dateFormat = "d MMMM"; out.locale = .current
        return out.string(from: d)
    }

    /// Every aggregate on this page goes through the app's single money
    /// authority: locale-aware separators and symbol placement
    /// ("2.243 €" in Romanian, "€2,243" in English), rounded, never truncated.
    func fmt(_ value: Double) -> String {
        CurrencyService.money(value, code: preferred, whole: true)
    }

    private func fmtSigned(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + fmt(abs(value))
    }
}

// MARK: - Record Row

struct FinancialRecordRow: View {
    let record: FinancialRecord
    let displayAmount: String

    var body: some View {
        let style = catStyle(record.category)
        HStack(spacing: 14) {
            Image(systemName: style.icon)
                .font(AppFont.scaled(17))
                .foregroundStyle(style.color)
                .frame(width: 44, height: 44)
                .glassRoundedRect(AppRadius.md)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                HStack(spacing: AppSpacing.xs) {
                    Text(LocalizedStringKey(record.category.capitalized))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.4))
                    // Triage nudge: an auto-imported payment nobody categorized
                    // yet. Long-press → Edit assigns it — and teaches the
                    // household's merchant memory for every future payment.
                    if record.category == "other", record.tags.contains("apple_pay") {
                        Text("fin_triage_badge")
                            .font(AppFont.scaled(10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(AppOpacity.tintedFill), in: Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(record.isIncome ? "+" : "-")\(displayAmount)")
                    .font(AppFont.subheadline)
                    .foregroundStyle(record.isIncome ? Color.brandSuccess : .primary)
                Text(record.dateFormatted)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }
}

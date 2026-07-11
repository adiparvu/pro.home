import SwiftUI
import Charts

// MARK: - Expense Dashboard (Revolut-style)

struct ExpenseDashboardView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(SupplyService.self) private var supplyService
    @Environment(AppSettings.self) private var appSettings

    @Binding var activeTab: ExpenseTab
    @Binding var showScanner: Bool
    @Binding var showAddReceipt: Bool
    @Binding var showBudgets: Bool
    @Binding var showReports: Bool

    @State private var selectedMonth: String = ""
    @State private var selectedReceipt: Receipt? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                listsStatsCard
                monthTotalCard
                dailyChartCard
                quickActionsRow
                categoryBreakdownCard
                if !budgetsForMonth.isEmpty { budgetProgressCard }
                if !receiptService.receiptItems.isEmpty { priceHistoryCard }
                recentReceiptsSection
                let recurring = receiptService.recurringItems()
                if !recurring.isEmpty { recurringSection(recurring) }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await receiptService.load(propertyId: id)
            }
        }
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptDetailView(receipt: receipt)
                .environment(receiptService)
                .environment(propertyService)
        }
        .onAppear {
            if selectedMonth.isEmpty { selectedMonth = receiptService.currentMonthKey }
        }
        .onChange(of: receiptService.currentMonthKey) { _, new in
            if selectedMonth.isEmpty { selectedMonth = new }
        }
    }

    // MARK: - Money display
    //
    // Every amount in the module goes through the app's one money
    // authority, in the household's currency — never a bare number.

    private func money(_ amount: Double, whole: Bool = false) -> String {
        CurrencyService.money(amount, code: appSettings.preferredCurrency, whole: whole)
    }

    // MARK: - Lists stats card

    private var listsStatsCard: some View {
        GlassCard(padding: 18) {
            HStack(spacing: 0) {
                statCell(value: "\(supplyService.lists.count)", label: String(localized: "supply_lists_count"), tab: .lists)
                Divider().frame(height: 32).opacity(0.3)
                statCell(value: "\(supplyService.totalPending)", label: String(localized: "supply_to_buy"), tab: .toBuy)
                Divider().frame(height: 32).opacity(0.3)
                statCell(value: "\(supplyService.totalCompleted)", label: String(localized: "supply_completed"), tab: .completed)
            }
        }
    }

    private func statCell(value: String, label: String, tab: ExpenseTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { activeTab = tab }
            HapticFeedback.selection()
        } label: {
            VStack(spacing: 2) {
                Text(value).font(AppFont.scaled(22, weight: .bold)).contentTransition(.numericText())
                Text(label).font(AppFont.scaled(11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month + Total card

    private var monthTotalCard: some View {
        let total = receiptService.totalSpent(in: selectedMonth)
        let prevTotal = receiptService.totalSpent(in: receiptService.previousMonthKey(from: selectedMonth))
        let count = receiptService.receiptsForMonth(selectedMonth).count
        let isCurrent = selectedMonth == receiptService.currentMonthKey

        return VStack(spacing: 18) {
            // Month navigator, sitting on the gradient
            HStack(spacing: 12) {
                monthNavButton("chevron.left", enabled: true) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonth = receiptService.previousMonthKey(from: selectedMonth)
                    }
                    HapticFeedback.selection()
                }
                Spacer()
                Text(receiptService.monthDisplayName(selectedMonth))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Spacer()
                monthNavButton("chevron.right", enabled: !isCurrent) {
                    let next = receiptService.nextMonthKey(from: selectedMonth)
                    if next != selectedMonth {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedMonth = next }
                        HapticFeedback.selection()
                    }
                }
            }

            VStack(spacing: 8) {
                Text(verbatim: money(total))
                    .font(AppFont.scaled(46, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text("\(count) \(String(localized: "expense_receipts"))")
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    if prevTotal > 0 {
                        let delta = total - prevTotal
                        let pct = abs(delta / prevTotal * 100)
                        HStack(spacing: 3) {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                                .font(AppFont.scaled(10, weight: .bold))
                            Text(String(format: "%.0f%%", pct))
                                .font(AppFont.captionStrong)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: Capsule())
                    }
                }

                if count == 0 {
                    // Honest empty state + a real way out: straight into the
                    // existing scanning flow, not a hint about a hidden "+".
                    VStack(spacing: 10) {
                        Text(String(localized: "expense_month_empty"))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        if isCurrent {
                            Button {
                                showScanner = true
                                HapticFeedback.impact(.light)
                            } label: {
                                Label(String(localized: "expense_scan_receipt"),
                                      systemImage: "camera.viewfinder")
                                    .font(AppFont.scaled(13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, 9)
                                    .background(.white.opacity(0.2), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        // A ZStack isn't a ShapeStyle, so the `.background(_:in:)` form can't take
        // it — build the rounded card as a filled shape and clip the sheen to it.
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.34, blue: 0.76),
                                 Color(red: 0.40, green: 0.22, blue: 0.70)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                // Soft highlight sheen in the top-right for depth.
                .overlay(
                    RadialGradient(colors: [.white.opacity(0.18), .clear],
                                   center: .topTrailing, startRadius: 8, endRadius: 220)
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .shadow(color: Color(red: 0.25, green: 0.2, blue: 0.6).opacity(0.28), radius: 18, y: 10)
    }

    private func monthNavButton(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.35))
                .frame(width: 32, height: 32)
                .background(.white.opacity(enabled ? 0.16 : 0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Daily chart

    @ViewBuilder
    private var dailyChartCard: some View {
        let days = receiptService.spendByDay(in: selectedMonth)
        if !days.isEmpty {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "expense_section_daily"))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    Chart(days) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Amount", day.total)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: days.count > 20 ? 7 : 3)) { val in
                            if let date = val.as(Date.self) {
                                AxisValueLabel {
                                    Text(date, format: .dateTime.day())
                                        .font(AppFont.scaled(10))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { val in
                            if let v = val.as(Double.self) {
                                AxisValueLabel {
                                    Text(verbatim: money(v, whole: true))
                                        .font(AppFont.scaled(9))
                                }
                            }
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                        }
                    }
                    .frame(height: 130)
                    .chartPlotStyle { plot in
                        plot.background(Color.clear)
                    }
                }
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            GlassActionButton(icon: "camera.viewfinder", label: "expense_scan") {
                showScanner = true
            }
            .frame(maxWidth: .infinity)
            GlassActionButton(icon: "plus.circle.fill", label: "expense_add") {
                showAddReceipt = true
            }
            .frame(maxWidth: .infinity)
            GlassActionButton(icon: "target", label: "expense_budgets") {
                showBudgets = true
            }
            .frame(maxWidth: .infinity)
            GlassActionButton(icon: "chart.bar.doc.horizontal", label: "expense_reports_short") {
                showReports = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Category breakdown

    @ViewBuilder
    private var categoryBreakdownCard: some View {
        let cats = receiptService.spendByCategory(in: selectedMonth)
        if !cats.isEmpty {
            let total = cats.reduce(0) { $0 + $1.total }
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "expense_section_categories"))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    HStack(alignment: .center, spacing: 16) {
                        // Donut chart
                        Chart(cats) { cat in
                            SectorMark(
                                angle: .value("Amount", cat.total),
                                innerRadius: .ratio(0.6),
                                angularInset: 2
                            )
                            .foregroundStyle(cat.color)
                            .cornerRadius(4)
                        }
                        .frame(width: 90, height: 90)

                        // Legend
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(cats.prefix(5)) { cat in
                                HStack(spacing: 8) {
                                    Circle().fill(cat.color).frame(width: 8, height: 8)
                                    Text(cat.label)
                                        .font(AppFont.scaled(12))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    let pct = total > 0 ? cat.total / total * 100 : 0
                                    Text(String(format: "%.0f%%", pct))
                                        .font(AppFont.label)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if cats.count > 5 {
                                Text(String(localized: "expense_more_categories"))
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Budget progress

    private var budgetsForMonth: [HouseholdBudget] {
        receiptService.budgets.filter { $0.month == selectedMonth }
    }

    private var budgetProgressCard: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "expense_section_budgets"))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    Button { showBudgets = true } label: {
                        Text(String(localized: "expense_edit_budgets"))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(budgetsForMonth) { budget in
                    let spent = receiptService.spent(for: budget.category, in: selectedMonth)
                    let pct = budget.monthlyLimit > 0 ? min(spent / budget.monthlyLimit, 1.0) : 0
                    let isOver = spent > budget.monthlyLimit && budget.monthlyLimit > 0

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: ReceiptCategory.icon(for: budget.category))
                                .font(AppFont.label)
                                .foregroundStyle(ReceiptCategory.color(for: budget.category))
                            Text(ReceiptCategory.label(for: budget.category))
                                .font(AppFont.scaled(13, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(verbatim: "\(money(spent)) / \(money(budget.monthlyLimit))")
                                .font(AppFont.label)
                                .foregroundStyle(isOver ? .red : .secondary)
                        }

                        // Progress bar without GeometryReader: scale a full-width fill.
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 6)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isOver ? Color.red : ReceiptCategory.color(for: budget.category))
                                    .scaleEffect(x: pct, y: 1, anchor: .leading)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Price history entry
    //
    // Shown only when scanned receipt items exist — the page it opens is
    // built entirely from them.

    private var priceHistoryCard: some View {
        NavigationLink {
            PriceHistoryView()
        } label: {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(AppFont.scaled(17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .mediaGlass(in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "price_history_title"))
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text(String(localized: "price_history_subtitle"))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent receipts

    @ViewBuilder
    private var recentReceiptsSection: some View {
        let recent = receiptService.receiptsForMonth(selectedMonth)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "expense_section_recent"))
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                    .padding(.leading, AppSpacing.xxs)

                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        let recentSlice = Array(recent.prefix(5).enumerated())
                        let lastIdx = min(recent.count, 5) - 1
                        ForEach(recentSlice, id: \.element.id) { idx, receipt in
                            receiptRow(receipt, isLast: idx == lastIdx)
                                .onTapGesture {
                                    selectedReceipt = receipt
                                    HapticFeedback.selection()
                                }
                        }
                    }
                }

                if recent.count > 5 {
                    NavigationLink {
                        ReceiptListView()
                    } label: {
                        Text(String(format: String(localized: "expense_see_all"), recent.count))
                            .font(AppFont.scaled(13, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func receiptRow(_ receipt: Receipt, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: receipt.categoryIcon)
                    .font(AppFont.headline)
                    .foregroundStyle(receipt.categoryColor)
                    .frame(width: 40, height: 40)
                    .glassRoundedRect(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.storeName.isEmpty ? String(localized: "expense_unknown_store") : receipt.storeName)
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(receipt.formattedDate)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(verbatim: money(receipt.total))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 66)
            }
        }
    }

    // MARK: - Recurring items

    private func recurringSection(_ items: [RecurringItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "expense_section_recurring"))
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(AppFont.captionEmphasis).foregroundStyle(Color.accentColor)
                                    .frame(width: 36, height: 36)
                                    .glassRoundedRect(AppRadius.sm)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(AppFont.footnote).foregroundStyle(.primary).lineLimit(1)
                                    Text(String(format: String(localized: "expense_recurring_times"), item.count))
                                        .font(AppFont.scaled(11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(verbatim: "~\(money(item.avgPrice))")
                                    .font(AppFont.captionEmphasis)
                                    .foregroundStyle(Color.accentColor)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                            if idx < items.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                }
            }
        }
    }
}

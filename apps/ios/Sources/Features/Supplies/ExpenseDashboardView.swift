import SwiftUI
import Charts

// MARK: - Expense Dashboard (Revolut-style)

struct ExpenseDashboardView: View {
    @EnvironmentObject private var receiptService: ReceiptService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var supplyService: SupplyService

    @Binding var activeTab: ExpenseTab
    @Binding var showScanner: Bool
    @Binding var showAddReceipt: Bool
    @Binding var showBudgets: Bool
    @Binding var showReports: Bool

    @State private var selectedMonth: String = ""
    @State private var selectedReceipt: Receipt? = nil
    @State private var showReceiptDetail = false
    @State private var chartSelection: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                listsStatsCard
                monthTotalCard
                dailyChartCard
                quickActionsRow
                categoryBreakdownCard
                if !budgetsForMonth.isEmpty { budgetProgressCard }
                recentReceiptsSection
                let recurring = receiptService.recurringItems()
                if !recurring.isEmpty { recurringSection(recurring) }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await receiptService.load(propertyId: id)
            }
        }
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptDetailView(receipt: receipt)
                .environmentObject(receiptService)
                .environmentObject(propertyService)
        }
        .onAppear {
            if selectedMonth.isEmpty { selectedMonth = receiptService.currentMonthKey }
        }
        .onChange(of: receiptService.currentMonthKey) { _, new in
            if selectedMonth.isEmpty { selectedMonth = new }
        }
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
                Text(value).font(.system(size: 22, weight: .bold)).contentTransition(.numericText())
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month + Total card

    private var monthTotalCard: some View {
        GlassCard(padding: 20) {
            VStack(spacing: 16) {
                // Month picker
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMonth = receiptService.previousMonthKey(from: selectedMonth)
                        }
                        HapticFeedback.selection()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(receiptService.monthDisplayName(selectedMonth))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Spacer()

                    Button {
                        let next = receiptService.nextMonthKey(from: selectedMonth)
                        if next != selectedMonth {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedMonth = next }
                            HapticFeedback.selection()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedMonth == receiptService.currentMonthKey
                                ? Color.primary.opacity(0.2) : .secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(selectedMonth == receiptService.currentMonthKey ? 0.03 : 0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedMonth == receiptService.currentMonthKey)
                }

                // Big total
                let total = receiptService.totalSpent(in: selectedMonth)
                let prevTotal = receiptService.totalSpent(in: receiptService.previousMonthKey(from: selectedMonth))
                let count = receiptService.receiptsForMonth(selectedMonth).count

                VStack(spacing: 6) {
                    Text(Receipt.format(total))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    HStack(spacing: 10) {
                        Text("\(count) \(String(localized: "expense_receipts"))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        if prevTotal > 0 {
                            let delta = total - prevTotal
                            let pct = abs(delta / prevTotal * 100)
                            HStack(spacing: 3) {
                                Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "%.0f%%", pct))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(delta <= 0
                                ? Color(red: 0.2, green: 0.78, blue: 0.45)
                                : Color.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((delta <= 0 ? Color(red: 0.2, green: 0.78, blue: 0.45) : Color.orange).opacity(0.12),
                                        in: Capsule())
                        }
                    }
                }

                if count == 0 {
                    Text(String(localized: "expense_no_receipts_month"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Daily chart

    private var dailyChartCard: some View {
        let days = receiptService.spendByDay(in: selectedMonth)
        guard !days.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "expense_section_daily"))
                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 10))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { val in
                            if let v = val.as(Double.self) {
                                AxisValueLabel {
                                    Text(Receipt.format(v))
                                        .font(.system(size: 9))
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
        )
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            quickAction(icon: "camera.viewfinder", label: String(localized: "expense_scan")) {
                showScanner = true; HapticFeedback.impact(.light)
            }
            quickAction(icon: "plus.circle.fill", label: String(localized: "expense_add")) {
                showAddReceipt = true; HapticFeedback.impact(.light)
            }
            quickAction(icon: "target", label: String(localized: "expense_budgets")) {
                showBudgets = true; HapticFeedback.impact(.light)
            }
            quickAction(icon: "chart.bar.doc.horizontal", label: String(localized: "expense_reports_short")) {
                showReports = true; HapticFeedback.impact(.light)
            }
        }
    }

    private func quickAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category breakdown

    private var categoryBreakdownCard: some View {
        let cats = receiptService.spendByCategory(in: selectedMonth)
        guard !cats.isEmpty else { return AnyView(EmptyView()) }
        let total = cats.reduce(0) { $0 + $1.total }

        return AnyView(
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "expense_section_categories"))
                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    let pct = total > 0 ? cat.total / total * 100 : 0
                                    Text(String(format: "%.0f%%", pct))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if cats.count > 5 {
                                Text(String(localized: "expense_more_categories"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        )
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    Button { showBudgets = true } label: {
                        Text(String(localized: "expense_edit_budgets"))
                            .font(.system(size: 12))
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
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ReceiptCategory.color(for: budget.category))
                            Text(ReceiptCategory.label(for: budget.category))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(Receipt.format(spent)) / \(Receipt.format(budget.monthlyLimit))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isOver ? .red : .secondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isOver ? Color.red : ReceiptCategory.color(for: budget.category))
                                    .frame(width: geo.size.width * pct, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    // MARK: - Recent receipts

    private var recentReceiptsSection: some View {
        let recent = receiptService.receiptsForMonth(selectedMonth)
        guard !recent.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "expense_section_recent"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                    .padding(.leading, 4)

                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        let recentSlice = Array(recent.prefix(10).enumerated())
                        let lastIdx = min(recent.count, 10) - 1
                        ForEach(recentSlice, id: \.element.id) { idx, receipt in
                            receiptRow(receipt, isLast: idx == lastIdx)
                                .onTapGesture {
                                    selectedReceipt = receipt
                                    HapticFeedback.selection()
                                }
                        }
                    }
                }

                if recent.count > 10 {
                    Button { showReports = true } label: {
                        Text(String(format: String(localized: "expense_see_all"), recent.count))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }

    private func receiptRow(_ receipt: Receipt, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(receipt.categoryColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: receipt.categoryIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(receipt.categoryColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.storeName.isEmpty ? String(localized: "expense_unknown_store") : receipt.storeName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(receipt.formattedDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(receipt.formattedTotal)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12)).frame(width: 36, height: 36)
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text(String(format: String(localized: "expense_recurring_times"), item.count))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("~\(Receipt.format(item.avgPrice))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
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

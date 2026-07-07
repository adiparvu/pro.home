import SwiftUI
import Charts

// MARK: - Main View

struct FinancesView: View {
    @Environment(FinancialService.self) var financialService
    @Environment(BudgetService.self) var budgetService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(AppRouter.self) private var router

    @State private var showAddSheet    = false
    @State private var selectedType: String? = nil
    @State var displayedMonth: Date   = Calendar.current.startOfMonth(Date())

    var preferred: String { appSettings.preferredCurrency }

    // Records for the displayed month
    var monthRecords: [FinancialRecord] {
        let cal = Calendar.current
        let start = displayedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return financialService.records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return d >= start && d < end
        }
    }

    private func total(_ type: String, in records: [FinancialRecord]) -> Double {
        records.filter { $0.type == type }
            .reduce(0) { $0 + currencyService.convert($1.amount, from: $1.currency, to: preferred) }
    }

    // Group records by date string
    func grouped(_ records: [FinancialRecord]) -> [(date: String, records: [FinancialRecord])] {
        var grouped: [String: [FinancialRecord]] = [:]
        for r in records { grouped[r.date, default: []].append(r) }
        return grouped.keys.sorted(by: >).map { (date: $0, records: grouped[$0] ?? []) }
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    /// Top expense categories of the displayed month, with their share of
    /// the month's spending — one pass, converted to the preferred currency.
    func categoryItems(month: [FinancialRecord]) -> [CategoryBreakdownSection.Item] {
        var totals: [String: Double] = [:]
        for r in month where r.type == "expense" {
            totals[r.category.lowercased(), default: 0]
                += currencyService.convert(r.amount, from: r.currency, to: preferred)
        }
        let grand = totals.values.reduce(0, +)
        guard grand > 0 else { return [] }
        return totals.sorted { $0.value > $1.value }.prefix(5).map {
            CategoryBreakdownSection.Item(category: $0.key, amount: $0.value, share: $0.value / grand)
        }
    }

    /// Income vs. expenses for the six months ending at the displayed month,
    /// zeros included so the chart never lies by omission.
    func trendPoints() -> [SixMonthTrendSection.Point] {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .month, value: 1, to: displayedMonth),
              let start = cal.date(byAdding: .month, value: -5, to: displayedMonth) else { return [] }
        var buckets: [Date: (income: Double, expense: Double)] = [:]
        for r in financialService.records {
            guard let d = AppDate.day(from: r.date), d >= start, d < end else { continue }
            let m = cal.startOfMonth(d)
            var b = buckets[m] ?? (0, 0)
            let v = currencyService.convert(r.amount, from: r.currency, to: preferred)
            if r.isIncome { b.income += v } else { b.expense += v }
            buckets[m] = b
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = .current
        return (0..<6).compactMap { cal.date(byAdding: .month, value: $0, to: start) }.flatMap { m in
            let b = buckets[m] ?? (0, 0)
            let label = formatter.string(from: m).capitalized
            return [SixMonthTrendSection.Point(monthStart: m, label: label, isIncome: true, amount: b.income),
                    SixMonthTrendSection.Point(monthStart: m, label: label, isIncome: false, amount: b.expense)]
        }
    }

    var body: some View {
        // One pass per render: the month filter and both totals used to be
        // recomputed on every property access (4× per render, each with a
        // currency conversion per record).
        let month = monthRecords
        let income = total("income", in: month)
        let expenses = total("expense", in: month)
        let filtered = selectedType.map { t in month.filter { $0.type == t } } ?? month

        Group {
        if financialService.isLoading && financialService.records.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection(net: income - expenses)
                        kpiStrip(income: income, expenses: expenses)
                        quickActionsRow
                            .padding(.top, AppSpacing.xl)
                            .padding(.horizontal, AppSpacing.xl)
                        CategoryBreakdownSection(items: categoryItems(month: month),
                                                 format: { fmt($0) })
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        SixMonthTrendSection(points: trendPoints())
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        ExpenseForecastSection(records: financialService.records)
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        transactionList(filtered)
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        Spacer(minLength: 110)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ScrollOffsetKey.self,
                                                   value: geo.frame(in: .named("financesScroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "financesScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { y in
                    tabBarVis.scrollOffset = y
                }
                .refreshable { await financialService.load() }
        }
        }
        .background(appBackground.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            FloatingSpeedDial(
                actions: appSettings.fabVisible(.finances) ? appSettings.fabActions(.finances) : [],
                onSelect: { action in
                    if action == .addExpense {
                        showAddSheet = true
                        HapticFeedback.impact(.medium)
                    } else {
                        router.perform(action)
                    }
                },
                bottomPadding: 16
            )
        }
        .navigationTitle("Finances")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.headline)
                }
                .accessibilityLabel("Add transaction")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFinancialView { await financialService.load() }
        }
        .alert("Error", isPresented: Binding(
            get: { financialService.error != nil },
            set: { if !$0 { financialService.error = nil } }
        )) {
            Button("OK") { financialService.error = nil }
        } message: { Text(LocalizedStringKey(financialService.error ?? "")) }
        .task { await financialService.load() }
    }

    private var filterMenu: some View {
        Menu {
            Button { withAnimation(.spring(response: 0.25)) { selectedType = nil } } label: {
                Label("All", systemImage: "tray.full")
            }
            Button { withAnimation(.spring(response: 0.25)) { selectedType = "income" } } label: {
                Label("Income", systemImage: "arrow.down.left")
            }
            Button { withAnimation(.spring(response: 0.25)) { selectedType = "expense" } } label: {
                Label("Expenses", systemImage: "arrow.up.right")
            }
        } label: {
            Image(systemName: selectedType == nil
                  ? "line.3.horizontal.decrease"
                  : (selectedType == "income" ? "arrow.down.left" : "arrow.up.right"))
                .font(AppFont.headline)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Filter transactions")
    }
}

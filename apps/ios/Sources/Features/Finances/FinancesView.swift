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

    private func total(_ type: String) -> Double {
        monthRecords.filter { $0.type == type }
            .reduce(0) { $0 + currencyService.convert($1.amount, from: $1.currency, to: preferred) }
    }

    var income:   Double { total("income") }
    var expenses: Double { total("expense") }
    var net:      Double { income - expenses }

    var filteredRecords: [FinancialRecord] {
        let base = monthRecords
        guard let type = selectedType else { return base }
        return base.filter { $0.type == type }
    }

    // Group records by date string
    var groupedRecords: [(date: String, records: [FinancialRecord])] {
        var grouped: [String: [FinancialRecord]] = [:]
        for r in filteredRecords { grouped[r.date, default: []].append(r) }
        return grouped.keys.sorted(by: >).map { (date: $0, records: grouped[$0] ?? []) }
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        Group {
        if financialService.isLoading && financialService.records.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                        kpiStrip
                        quickActionsRow
                            .padding(.top, AppSpacing.xl)
                            .padding(.horizontal, AppSpacing.xl)
                        ExpenseForecastSection(records: financialService.records)
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        transactionList
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

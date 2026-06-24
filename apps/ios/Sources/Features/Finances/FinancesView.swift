import SwiftUI
import Charts

// MARK: - Main View

struct FinancesView: View {
    @EnvironmentObject var financialService: FinancialService
    @EnvironmentObject var budgetService: BudgetService
    @EnvironmentObject var currencyService: CurrencyService
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @EnvironmentObject private var router: AppRouter

    @State private var showAddSheet    = false
    @State private var selectedType: String? = nil
    @State var displayedMonth: Date   = Calendar.current.startOfMonth(Date())

    var preferred: String { appSettings.preferredCurrency }

    // Records for the displayed month
    var monthRecords: [FinancialRecord] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let start = displayedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return financialService.records.filter { r in
            guard let d = iso.date(from: r.date) else { return false }
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
                            .padding(.top, 20)
                            .padding(.horizontal, 20)
                        transactionList
                            .padding(.top, 16)
                            .padding(.horizontal, 20)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

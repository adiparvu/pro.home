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
    "other":       ("ellipsis.circle.fill",     Color.primary.opacity(0.6)),
]

private func catStyle(_ category: String) -> (icon: String, color: Color) {
    categoryIcons[category.lowercased()] ?? ("ellipsis.circle.fill", Color.primary.opacity(0.5))
}

// MARK: - Main View

struct FinancesView: View {
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var budgetService: BudgetService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings

    @State private var showAddSheet    = false
    @State private var selectedType: String? = nil
    @State private var displayedMonth: Date   = Calendar.current.startOfMonth(Date())

    private var preferred: String { appSettings.preferredCurrency }

    // Records for the displayed month
    private var monthRecords: [FinancialRecord] {
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

    private var income:   Double { total("income") }
    private var expenses: Double { total("expense") }
    private var net:      Double { income - expenses }

    private var filteredRecords: [FinancialRecord] {
        let base = monthRecords
        guard let type = selectedType else { return base }
        return base.filter { $0.type == type }
    }

    // Group records by date string
    private var groupedRecords: [(date: String, records: [FinancialRecord])] {
        var grouped: [String: [FinancialRecord]] = [:]
        for r in filteredRecords { grouped[r.date, default: []].append(r) }
        return grouped.keys.sorted(by: >).map { (date: $0, records: grouped[$0]!) }
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()

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
                        filterTabs
                            .padding(.top, 16)
                            .padding(.horizontal, 20)
                        transactionList
                            .padding(.top, 8)
                            .padding(.horizontal, 20)
                        Spacer(minLength: 110)
                    }
                }
                .refreshable { await financialService.load() }
            }

            // FAB
            Button {
                showAddSheet = true
                HapticFeedback.impact(.medium)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(colors: [.blue, .indigo],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: .blue.opacity(0.45), radius: 18, y: 6)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 110)
        }
        .navigationTitle("Finanțe")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddFinancialView { await financialService.load() }
        }
        .alert("Error", isPresented: Binding(
            get: { financialService.error != nil },
            set: { if !$0 { financialService.error = nil } }
        )) {
            Button("OK") { financialService.error = nil }
        } message: { Text(financialService.error ?? "") }
        .task { await financialService.load() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 0) {
            // Period navigator
            HStack(spacing: 20) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Text(monthLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .contentTransition(.identity)
                    .id(displayedMonth)

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        let next = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                        if next <= Date() { displayedMonth = next }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isCurrentMonth ? Color.primary.opacity(0.15) : Color.primary.opacity(0.45))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)
            }
            .padding(.top, 8)

            // Net balance
            VStack(spacing: 4) {
                Text(isCurrentMonth ? "Balanță luna curentă" : "Balanță")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.45))

                Text(fmtSigned(net))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(net >= 0 ? Color.primary : .red)
                    .contentTransition(.numericText(countsDown: net < 0))
                    .animation(.spring(response: 0.4), value: net)
            }
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            kpiCell(label: "Venituri", value: fmt(income), color: Color(red: 0.25, green: 0.82, blue: 0.5), icon: "arrow.down.left")
            Divider().frame(height: 36).background(Color.primary.opacity(0.1))
            kpiCell(label: "Cheltuieli", value: fmt(expenses), color: .red, icon: "arrow.up.right")
            Divider().frame(height: 36).background(Color.primary.opacity(0.1))
            let savingsRate = income > 0 ? max(0, (income - expenses) / income * 100) : 0
            kpiCell(label: "Economii", value: String(format: "%.0f%%", savingsRate),
                    color: savingsRate >= 20 ? Color(red: 0.25, green: 0.82, blue: 0.5) : savingsRate >= 10 ? .orange : .red,
                    icon: "percent")
        }
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func kpiCell(label: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: value)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BudgetView()
                    .environmentObject(budgetService)
                    .environmentObject(financialService)
            } label: {
                actionTile(icon: "chart.pie.fill", label: "Buget", color: .blue)
            }
            .buttonStyle(.plain)

            NavigationLink { MortgageView() } label: {
                actionTile(icon: "house.and.flag.fill", label: "Credit", color: .purple)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionTile(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 6) {
            filterTab("Toate", value: nil)
            filterTab("Venituri", value: "income")
            filterTab("Cheltuieli", value: "expense")
        }
        .padding(4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private func filterTab(_ label: String, value: String?) -> some View {
        let active = selectedType == value
        return Button {
            withAnimation(.spring(response: 0.25)) { selectedType = value }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Color.primary.opacity(0.55))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(active ? Color.primary.opacity(0.12) : Color.clear,
                             in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transactions

    @ViewBuilder
    private var transactionList: some View {
        if filteredRecords.isEmpty {
            emptyState
        } else {
            VStack(spacing: 16) {
                ForEach(groupedRecords, id: \.date) { group in
                    VStack(spacing: 0) {
                        HStack {
                            Text(groupDateLabel(group.date))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.4))
                                .textCase(.uppercase)
                                .kerning(0.5)
                            Spacer()
                            let dayTotal = group.records.reduce(0.0) { sum, r in
                                let v = currencyService.convert(r.amount, from: r.currency, to: preferred)
                                return sum + (r.isIncome ? v : -v)
                            }
                            Text(fmtSigned(dayTotal))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(dayTotal >= 0 ? Color(red: 0.25, green: 0.82, blue: 0.5) : .red)
                        }
                        .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { idx, record in
                                let displayAmt = currencyService.formatted(record.amount, from: record.currency, preferred: preferred)
                                FinancialRecordRow(record: record, displayAmount: displayAmt)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await financialService.delete(record) }
                                        } label: { Label("Șterge", systemImage: "trash") }
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 72, height: 72)
                Image(systemName: "banknote")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            Text("Nicio tranzacție")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
            Text("Adaugă prima tranzacție apăsând +")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Helpers

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = isCurrentMonth ? "'Luna curentă'" : "MMMM yyyy"
        f.locale = Locale(identifier: "ro_RO")
        return isCurrentMonth ? "Luna curentă" : f.string(from: displayedMonth).capitalized
    }

    private func groupDateLabel(_ dateStr: String) -> String {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        guard let d = iso.date(from: dateStr) else { return dateStr }
        if Calendar.current.isDateInToday(d) { return "Astăzi" }
        if Calendar.current.isDateInYesterday(d) { return "Ieri" }
        let out = DateFormatter(); out.dateFormat = "d MMMM"; out.locale = Locale(identifier: "ro_RO")
        return out.string(from: d)
    }

    private func fmt(_ value: Double) -> String {
        preferred == "RON"
            ? String(format: "%.0f %@", value, currencyService.symbol(for: preferred))
            : String(format: "%@%.0f", currencyService.symbol(for: preferred), value)
    }

    private func fmtSigned(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : value < 0 ? "" : ""
        return prefix + fmt(abs(value))
    }
}

// MARK: - Record Row (used also from search)

struct FinancialRecordRow: View {
    let record: FinancialRecord
    let displayAmount: String

    var body: some View {
        let style = catStyle(record.category)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: style.icon)
                    .font(.system(size: 17))
                    .foregroundStyle(style.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(record.category.capitalized)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(record.isIncome ? "+" : "-")\(displayAmount)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(record.isIncome ? Color(red: 0.25, green: 0.82, blue: 0.5) : .primary)
                Text(record.dateFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}


import SwiftUI

struct FinancesView: View {
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var budgetService: BudgetService
    @State private var showAddSheet = false
    @State private var selectedType: String? = nil

    var filteredRecords: [FinancialRecord] {
        guard let type = selectedType else { return financialService.records }
        return financialService.records.filter { $0.type == type }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader(title: "Finances")
                    .padding(.bottom, 16)

                if financialService.isLoading && financialService.records.isEmpty {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            summaryCards
                            quickLinks
                            filterPicker
                            recordsList
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 110)
                    }
                    .refreshable { await financialService.load() }
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { showAddSheet = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle()
                            )
                            .shadow(color: .blue.opacity(0.4), radius: 16, y: 6)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 110)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFinancialView { await financialService.load() }
        }
        .task { await financialService.load() }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: 12) {
            FinSummaryCard(
                label: "Income",
                value: "\(financialService.currencySymbol)\(Int(financialService.currentMonthIncome))",
                icon: "arrow.down.circle.fill",
                color: Color(red: 0.3, green: 0.85, blue: 0.5)
            )
            FinSummaryCard(
                label: "Expenses",
                value: "\(financialService.currencySymbol)\(Int(financialService.currentMonthExpenses))",
                icon: "arrow.up.circle.fill",
                color: .red
            )
            FinSummaryCard(
                label: "Net",
                value: "\(financialService.currentMonthNet >= 0 ? "+" : "")\(financialService.currencySymbol)\(Int(financialService.currentMonthNet))",
                icon: "chart.line.uptrend.xyaxis",
                color: financialService.currentMonthNet >= 0 ? .blue : .orange
            )
        }
    }

    // MARK: - Quick links

    private var quickLinks: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BudgetView()
                    .environmentObject(budgetService)
                    .environmentObject(financialService)
            } label: {
                QuickLinkCard(icon: "chart.pie.fill", label: "Budget", color: .blue)
            }
            .buttonStyle(.plain)

            NavigationLink {
                MortgageView()
            } label: {
                QuickLinkCard(icon: "house.and.flag.fill", label: "Mortgage", color: .purple)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Filter

    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(["All", "income", "expense"], id: \.self) { type in
                let isAll = type == "All"
                let isSelected = isAll ? selectedType == nil : selectedType == type
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        selectedType = isAll ? nil : type
                    }
                } label: {
                    HStack(spacing: 5) {
                        if !isAll {
                            Circle()
                                .fill(type == "income" ? Color(red: 0.3, green: 0.85, blue: 0.5) : .red)
                                .frame(width: 6, height: 6)
                        }
                        Text(isAll ? "All" : type.capitalized)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? .white : .white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Records

    @ViewBuilder
    private var recordsList: some View {
        if filteredRecords.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "banknote")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.2))
                Text("No records yet")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 40)
        } else {
            VStack(spacing: 8) {
                ForEach(filteredRecords) { record in
                    FinancialRecordRow(record: record, symbol: financialService.currencySymbol)
                }
            }
        }
    }
}

// MARK: - Summary card

private struct FinSummaryCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Record row

struct FinancialRecordRow: View {
    let record: FinancialRecord
    let symbol: String

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(record.isIncome ? Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.15) : Color.red.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: record.isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(record.isIncome ? Color(red: 0.3, green: 0.85, blue: 0.5) : .red)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text(record.category.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("·")
                            .foregroundStyle(.white.opacity(0.2))
                        Text(record.dateFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                Text("\(record.isIncome ? "+" : "-")\(symbol)\(String(format: "%.0f", record.amount))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(record.isIncome ? Color(red: 0.3, green: 0.85, blue: 0.5) : .red)
            }
        }
    }
}

// MARK: - Quick Link Card

private struct QuickLinkCard: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 10) {
                ColoredIconBadge(icon: icon, color: color, size: 36)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

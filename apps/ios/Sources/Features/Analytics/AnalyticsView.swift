import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @State private var selectedTab: AnalyticsTab = .finances
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(Date())

    enum AnalyticsTab: String, CaseIterable {
        case finances = "Finances"
        case tasks    = "Tasks"
        case forecast = "Forecast"
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader(title: "Analytics")
                    .padding(.bottom, 8)

                HStack(spacing: 0) {
                    ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Color.black : Color.primary.opacity(0.55))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? Color.white : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .finances:
                            FinancesSection(service: financialService, displayedMonth: $displayedMonth)
                        case .tasks:
                            TasksSection(service: taskService)
                        case .forecast:
                            ForecastSection(financialService: financialService)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 110)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("analyticsScroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "analyticsScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { y in
                    let shouldCollapse = y < -30
                    if shouldCollapse != tabBarVis.scrolledDown {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            tabBarVis.scrolledDown = shouldCollapse
                        }
                    }
                }
                .refreshable {
                    await financialService.load()
                    await taskService.load()
                }
            }
        }
    }
}

// MARK: - Finances Section

private struct FinancesSection: View {
    @ObservedObject var service: FinancialService
    @Binding var displayedMonth: Date

    private var cal: Calendar { Calendar.current }
    private var isCurrentMonth: Bool { cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) }

    private var monthRecords: [FinancialRecord] {
        service.records.filter { r in
            let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
            guard let d = iso.date(from: r.date) else { return false }
            return cal.isDate(d, equalTo: displayedMonth, toGranularity: .month)
        }
    }

    private var prevMonthRecords: [FinancialRecord] {
        guard let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) else { return [] }
        return service.records.filter { r in
            let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
            guard let d = iso.date(from: r.date) else { return false }
            return cal.isDate(d, equalTo: prev, toGranularity: .month)
        }
    }

    private var income: Double { monthRecords.filter(\.isIncome).map(\.amount).reduce(0, +) }
    private var expenses: Double { monthRecords.filter { $0.type == "expense" }.map(\.amount).reduce(0, +) }
    private var net: Double { income - expenses }
    private var savingsRate: Double { income > 0 ? (net / income) * 100 : 0 }

    private var prevIncome: Double { prevMonthRecords.filter(\.isIncome).map(\.amount).reduce(0, +) }
    private var prevExpenses: Double { prevMonthRecords.filter { $0.type == "expense" }.map(\.amount).reduce(0, +) }

    private var sym: String { service.currencySymbol }

    private func trend(_ current: Double, _ prev: Double) -> Double? {
        guard prev > 0 else { return nil }
        return ((current - prev) / prev) * 100
    }

    private var categoryData: [CategoryStat] {
        let expenseRecords = monthRecords.filter { $0.type == "expense" }
        let grouped = Dictionary(grouping: expenseRecords, by: \.category)
        return grouped.map { key, val in
            CategoryStat(name: key.isEmpty ? "Altele" : key.capitalized,
                         amount: val.map(\.amount).reduce(0, +))
        }
        .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(spacing: 16) {
            periodNavigator
            kpiRow
            if income > 0 || expenses > 0 {
                savingsCard
                if !categoryData.isEmpty { categoryCard }
            }
            chartCard
        }
    }

    // MARK: Period navigator

    private var periodNavigator: some View {
        HStack(spacing: 0) {
            Button {
                if let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) {
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = prev }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(monthLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if isCurrentMonth {
                    Text("luna curentă")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                if let next = cal.date(byAdding: .month, value: 1, to: displayedMonth) {
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = next }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrentMonth ? Color.primary.opacity(0.2) : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 8)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth).capitalized
    }

    // MARK: KPI row

    private var kpiRow: some View {
        HStack(spacing: 10) {
            TrendKPICard(
                label: "Venituri",
                value: "\(sym)\(Int(income))",
                icon: "arrow.down.circle.fill",
                trendPct: trend(income, prevIncome),
                trendPositive: income >= prevIncome
            )
            TrendKPICard(
                label: "Cheltuieli",
                value: "\(sym)\(Int(expenses))",
                icon: "arrow.up.circle.fill",
                trendPct: trend(expenses, prevExpenses),
                trendPositive: expenses <= prevExpenses
            )
            TrendKPICard(
                label: "Net",
                value: "\(net >= 0 ? "+" : "")\(sym)\(Int(net))",
                icon: "chart.line.uptrend.xyaxis",
                trendPct: nil,
                trendPositive: net >= 0,
                highlightValue: true,
                positiveValue: net >= 0
            )
        }
    }

    // MARK: Savings rate card

    private var savingsCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Rata economisirii", systemImage: "leaf.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.0f%%", max(0, savingsRate)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(savingsRate >= 20 ? Color(red: 0.2, green: 0.8, blue: 0.4) : savingsRate >= 0 ? .orange : .red)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(
                                colors: savingsRate > 0
                                    ? [Color(red: 0.3, green: 0.85, blue: 0.5), .blue]
                                    : [.red.opacity(0.8), .orange],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * min(1, max(0, savingsRate / 100)), height: 8)
                            .animation(.spring(response: 0.6), value: savingsRate)
                    }
                }
                .frame(height: 8)
                Text(savingsInsight)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var savingsInsight: String {
        if savingsRate >= 30 { return "Excelent! Economisești mai mult de 30% din venituri." }
        if savingsRate >= 20 { return "Bine! Economisești \(Int(savingsRate))% din venituri." }
        if savingsRate >= 0  { return "Poți economisi mai mult reducând cheltuielile." }
        return "Cheltuielile depășesc veniturile acestei luni."
    }

    // MARK: Category donut chart

    private var categoryCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cheltuieli pe categorie")
                    .font(.system(size: 15, weight: .semibold))

                HStack(alignment: .top, spacing: 16) {
                    Chart(categoryData.prefix(6)) { cat in
                        SectorMark(
                            angle: .value("Sumă", cat.amount),
                            innerRadius: .ratio(0.60),
                            angularInset: 2
                        )
                        .foregroundStyle(cat.color)
                        .cornerRadius(4)
                    }
                    .frame(width: 110, height: 110)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categoryData.prefix(5)) { cat in
                            HStack(spacing: 6) {
                                Circle().fill(cat.color).frame(width: 8, height: 8)
                                Text(cat.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(sym)\(Int(cat.amount))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Line chart

    private var chartCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Evoluție lunară")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Label("6 luni", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if service.monthlyData.isEmpty {
                    emptyChartPlaceholder
                } else {
                    Chart {
                        ForEach(service.monthlyData, id: \.month) { item in
                            AreaMark(
                                x: .value("Lună", item.month),
                                y: .value("Venituri", item.income)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.18),
                                             Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Lună", item.month),
                                y: .value("Venituri", item.income)
                            )
                            .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                            .symbol(Circle().strokeBorder(lineWidth: 1.5))
                            .symbolSize(24)

                            AreaMark(
                                x: .value("Lună", item.month),
                                y: .value("Cheltuieli", item.expenses)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.12), Color.red.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Lună", item.month),
                                y: .value("Cheltuieli", item.expenses)
                            )
                            .foregroundStyle(.red.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                                .foregroundStyle(Color.primary.opacity(0.05))
                            AxisValueLabel().foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                    .frame(height: 160)
                }

                HStack(spacing: 16) {
                    legendItem(color: Color(red: 0.3, green: 0.85, blue: 0.5), label: "Venituri", solid: true)
                    legendItem(color: .red.opacity(0.75), label: "Cheltuieli", solid: false)
                }
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("Adaugă tranzacții pentru a vedea graficul")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func legendItem(color: Color, label: String, solid: Bool) -> some View {
        HStack(spacing: 6) {
            if solid {
                Circle().fill(color).frame(width: 8, height: 8)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 4, height: 2)
                    }
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Category stat helper

private struct CategoryStat: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double

    var color: Color {
        let palette: [Color] = [
            Color(red: 0.29, green: 0.56, blue: 0.89),
            Color(red: 1.0, green: 0.45, blue: 0.1),
            Color(red: 0.3, green: 0.82, blue: 0.45),
            Color(red: 0.7, green: 0.3, blue: 0.9),
            Color(red: 1.0, green: 0.75, blue: 0.1),
            Color(red: 0.9, green: 0.3, blue: 0.35)
        ]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }
}

// MARK: - TrendKPICard

private struct TrendKPICard: View {
    let label: String
    let value: String
    let icon: String
    let trendPct: Double?
    let trendPositive: Bool
    var highlightValue: Bool = false
    var positiveValue: Bool = true

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)

                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(highlightValue
                        ? (positiveValue ? Color(red: 0.2, green: 0.8, blue: 0.4) : .red)
                        : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())

                if let pct = trendPct {
                    HStack(spacing: 2) {
                        Image(systemName: pct >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        Text(String(format: "%.0f%%", abs(pct)))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(trendPositive
                        ? Color(red: 0.2, green: 0.8, blue: 0.4)
                        : .red)
                } else {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Tasks Section

private struct TasksSection: View {
    @ObservedObject var service: TaskService

    var tasksByPriority: [(priority: String, count: Int, color: Color)] {
        let urgentCount = service.tasks.filter { $0.priority == "urgent" }.count
        let highCount   = service.tasks.filter { $0.priority == "high" }.count
        let mediumCount = service.tasks.filter { $0.priority == "medium" }.count
        let lowCount    = service.tasks.filter { $0.priority == "low" }.count
        let all: [(priority: String, count: Int, color: Color)] = [
            ("urgent", urgentCount, Color.red),
            ("high",   highCount,   Color.orange),
            ("medium", mediumCount, Color.yellow),
            ("low",    lowCount,    Color.blue)
        ]
        return all.filter { $0.count > 0 }
    }

    var completionRate: Double {
        guard !service.tasks.isEmpty else { return 0 }
        return Double(service.tasks.filter(\.isCompleted).count) / Double(service.tasks.count) * 100
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                TrendKPICard(label: "Deschise", value: "\(service.openCount)", icon: "circle", trendPct: nil, trendPositive: true)
                TrendKPICard(label: "Restante", value: "\(service.overdueCount)", icon: "exclamationmark.circle",
                             trendPct: nil, trendPositive: service.overdueCount == 0,
                             highlightValue: service.overdueCount > 0, positiveValue: false)
                TrendKPICard(label: "Finalizate/7z", value: "\(service.completedThisWeek)", icon: "checkmark.circle.fill",
                             trendPct: nil, trendPositive: true, highlightValue: service.completedThisWeek > 0, positiveValue: true)
            }

            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Rata de finalizare")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(String(format: "%.0f%%", completionRate))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(completionRate >= 70 ? Color(red: 0.2, green: 0.8, blue: 0.4) : .orange)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08)).frame(height: 10)
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.blue, Color(red: 0.3, green: 0.85, blue: 0.5)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: geo.size.width * (completionRate / 100), height: 10)
                                .animation(.spring(response: 0.7), value: completionRate)
                        }
                    }
                    .frame(height: 10)
                }
            }

            if !tasksByPriority.isEmpty {
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pe prioritate")
                            .font(.system(size: 15, weight: .semibold))

                        Chart(tasksByPriority, id: \.priority) { item in
                            BarMark(
                                x: .value("Număr", item.count),
                                y: .value("Prioritate", item.priority.capitalized)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [item.color.opacity(0.9), item.color.opacity(0.6)],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(6)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                                    .foregroundStyle(Color.primary.opacity(0.05))
                                AxisValueLabel().foregroundStyle(.secondary).font(.system(size: 10))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel().foregroundStyle(.secondary).font(.system(size: 11))
                            }
                        }
                        .frame(height: 110)
                    }
                }
            }
        }
    }
}

// MARK: - Forecast Section

private struct ForecastSection: View {
    @ObservedObject var financialService: FinancialService

    var projectedIncome: Double {
        let months = financialService.monthlyData
        guard !months.isEmpty else { return 0 }
        return months.map(\.income).reduce(0, +) / Double(months.count) * 12
    }
    var projectedExpenses: Double {
        let months = financialService.monthlyData
        guard !months.isEmpty else { return 0 }
        return months.map(\.expenses).reduce(0, +) / Double(months.count) * 12
    }
    var sym: String { financialService.currencySymbol }
    var netProfit: Double { projectedIncome - projectedExpenses }

    var body: some View {
        VStack(spacing: 16) {
            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Proiecție 12 luni")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Bazat pe ultimele \(financialService.monthlyData.count) luni")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("AI", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    VStack(spacing: 12) {
                        ForecastRow(label: "Venituri proiectate",
                                    value: "\(sym)\(Int(projectedIncome))",
                                    sub: "anual", positive: true)
                        Divider().background(Color.primary.opacity(0.07))
                        ForecastRow(label: "Cheltuieli proiectate",
                                    value: "\(sym)\(Int(projectedExpenses))",
                                    sub: "anual", positive: false)
                        Divider().background(Color.primary.opacity(0.07))
                        ForecastRow(label: "Profit net estimat",
                                    value: "\(netProfit >= 0 ? "+" : "")\(sym)\(Int(netProfit))",
                                    sub: "estimat", positive: netProfit >= 0)
                    }
                }
            }

            if !financialService.monthlyData.isEmpty {
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tendință cheltuieli")
                            .font(.system(size: 15, weight: .semibold))

                        Chart {
                            ForEach(financialService.monthlyData, id: \.month) { item in
                                BarMark(
                                    x: .value("Lună", item.month),
                                    y: .value("Cheltuieli", item.expenses)
                                )
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue.opacity(0.8), .blue.opacity(0.4)],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .cornerRadius(6)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                                    .foregroundStyle(Color.primary.opacity(0.05))
                                AxisValueLabel().foregroundStyle(.secondary).font(.system(size: 10))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel().foregroundStyle(.secondary).font(.system(size: 10))
                            }
                        }
                        .frame(height: 130)
                    }
                }
            }

            if financialService.records.isEmpty {
                GlassCard(padding: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.primary.opacity(0.18))
                        Text("Adaugă înregistrări financiare pentru a vedea prognoza")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct ForecastRow: View {
    let label: String
    let value: String
    let sub: String
    let positive: Bool

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(positive ? Color(red: 0.2, green: 0.8, blue: 0.4) : .primary)
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Calendar extension

extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

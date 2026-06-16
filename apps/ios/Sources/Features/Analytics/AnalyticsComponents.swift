import SwiftUI
import Charts

// MARK: - Finances Section

struct FinancesSection: View {
    @ObservedObject var service: FinancialService
    @Binding var displayedMonth: Date

    @State private var chartRange: ChartRange = .sixMonths
    @State private var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var showCustomSheet = false

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

    // MARK: Range chart data

    private var rangeChartData: [(label: String, income: Double, expenses: Double)] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let now = Date()

        func parseDate(_ r: FinancialRecord) -> Date? { iso.date(from: r.date) }

        func dayBuckets(days: Int) -> [(String, Double, Double)] {
            let lbl = DateFormatter(); lbl.dateFormat = days <= 7 ? "EEE" : "d"
            return (0..<days).reversed().compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: -offset, to: now),
                      let start = cal.dateInterval(of: .day, for: day)?.start,
                      let end = cal.dateInterval(of: .day, for: day)?.end else { return nil }
                let recs = service.records.filter { r in
                    guard let d = parseDate(r) else { return false }
                    return d >= start && d < end
                }
                return (lbl.string(from: day),
                        recs.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount },
                        recs.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount })
            }
        }

        func monthBuckets(from start: Date, to end: Date) -> [(String, Double, Double)] {
            let monthCount = (cal.dateComponents([.month], from: start, to: end).month ?? 0) + 1
            let lbl = DateFormatter(); lbl.dateFormat = monthCount > 8 ? "MMM yy" : "MMM"
            var buckets: [(String, Double, Double)] = []
            var cursor = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            while cursor <= end {
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                let recs = service.records.filter { r in
                    guard let d = parseDate(r) else { return false }
                    return d >= cursor && d < next
                }
                buckets.append((lbl.string(from: cursor),
                                recs.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount },
                                recs.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }))
                cursor = next
            }
            return buckets
        }

        switch chartRange {
        case .day:
            return dayBuckets(days: 1)
        case .week:
            return dayBuckets(days: 7)
        case .month:
            return dayBuckets(days: 30)
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: now) ?? now
            return monthBuckets(from: start, to: now)
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: now) ?? now
            return monthBuckets(from: start, to: now)
        case .year:
            let start = cal.date(byAdding: .year, value: -1, to: now) ?? now
            return monthBuckets(from: start, to: now)
        case .custom:
            return monthBuckets(from: customStart, to: customEnd)
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
                    Text("current month")
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
                label: "Income",
                value: "\(sym)\(Int(income))",
                icon: "arrow.down.circle.fill",
                trendPct: trend(income, prevIncome),
                trendPositive: income >= prevIncome
            )
            TrendKPICard(
                label: "Expenses",
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
                    Label("Savings rate", systemImage: "leaf.fill")
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
        if savingsRate >= 30 { return "Excellent! You're saving more than 30% of your income." }
        if savingsRate >= 20 { return "Good! You're saving \(Int(savingsRate))% of your income." }
        if savingsRate >= 0  { return "You can save more by reducing expenses." }
        return "Expenses exceed income this month."
    }

    // MARK: Category donut chart

    private var categoryCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Expenses by category")
                    .font(.system(size: 15, weight: .semibold))

                HStack(alignment: .top, spacing: 16) {
                    Chart(categoryData.prefix(6)) { cat in
                        SectorMark(
                            angle: .value("Amount", cat.amount),
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

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChartRange.allCases, id: \.self) { r in
                    Button {
                        if r == .custom {
                            showCustomSheet = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) { chartRange = r }
                        }
                    } label: {
                        Text(r.rawValue)
                            .font(.system(size: 12, weight: chartRange == r ? .semibold : .regular))
                            .foregroundStyle(chartRange == r ? .white : Color.primary.opacity(0.6))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(chartRange == r ? Color.accentColor : Color.primary.opacity(0.07),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chartCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly evolution")
                    .font(.system(size: 15, weight: .semibold))

                rangeChips

                let data = rangeChartData
                let hasData = data.contains { $0.income > 0 || $0.expenses > 0 }

                if !hasData {
                    emptyChartPlaceholder
                } else {
                    Chart {
                        ForEach(data, id: \.label) { item in
                            AreaMark(
                                x: .value("Period", item.label),
                                y: .value("Income", item.income)
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
                                x: .value("Period", item.label),
                                y: .value("Income", item.income)
                            )
                            .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                            .symbol(Circle().strokeBorder(lineWidth: 1.5))
                            .symbolSize(24)

                            AreaMark(
                                x: .value("Period", item.label),
                                y: .value("Expenses", item.expenses)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.12), Color.red.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Period", item.label),
                                y: .value("Expenses", item.expenses)
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
                    .animation(.easeInOut(duration: 0.25), value: chartRange)
                }

                HStack(spacing: 16) {
                    legendItem(color: Color(red: 0.3, green: 0.85, blue: 0.5), label: "Income", solid: true)
                    legendItem(color: .red.opacity(0.75), label: "Expenses", solid: false)
                }
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            NavigationStack {
                Form {
                    Section("Range") {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd,
                                   in: customStart..., displayedComponents: .date)
                    }
                }
                .navigationTitle("Custom range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            withAnimation(.easeInOut(duration: 0.18)) { chartRange = .custom }
                            showCustomSheet = false
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("Add transactions to see the chart")
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

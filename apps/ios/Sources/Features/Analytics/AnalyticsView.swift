import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var taskService: TaskService
    @State private var selectedTab: AnalyticsTab = .finances

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
                    .padding(.bottom, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? .black : Color.primary.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedTab == tab ? .white : Color.primary.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .finances: FinancesSection(service: financialService)
                        case .tasks:    TasksSection(service: taskService)
                        case .forecast: ForecastSection(financialService: financialService)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
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

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                KPICard(label: "Income", value: "\(service.currencySymbol)\(Int(service.currentMonthIncome))", icon: "arrow.down.circle.fill")
                KPICard(label: "Expenses", value: "\(service.currencySymbol)\(Int(service.currentMonthExpenses))", icon: "arrow.up.circle.fill")
                let net = service.currentMonthNet
                KPICard(label: "Net", value: "\(net >= 0 ? "+" : "")\(service.currencySymbol)\(Int(net))", icon: "chart.line.uptrend.xyaxis", positive: net >= 0)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Income vs Expenses")
                        .font(.headline)

                    if service.monthlyData.isEmpty {
                        Text("No data yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                    } else {
                        Chart {
                            ForEach(service.monthlyData, id: \.month) { item in
                                LineMark(
                                    x: .value("Month", item.month),
                                    y: .value("Income", item.income)
                                )
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.9))
                                .symbol(Circle().strokeBorder(lineWidth: 2))

                                AreaMark(
                                    x: .value("Month", item.month),
                                    y: .value("Income", item.income)
                                )
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.08))

                                LineMark(
                                    x: .value("Month", item.month),
                                    y: .value("Expenses", item.expenses)
                                )
                                .foregroundStyle(.red.opacity(0.7))
                                .lineStyle(StrokeStyle(dash: [4, 4]))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { val in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.primary.opacity(0.06))
                                AxisValueLabel()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel().foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 180)
                    }

                    HStack(spacing: 16) {
                        legendDot(color: Color(red: 0.3, green: 0.85, blue: 0.5), label: "Income")
                        legendDot(color: .red.opacity(0.7), label: "Expenses", dashed: true)
                    }
                }
            }
        }
    }

    private func legendDot(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color)
                            .frame(width: 4, height: 2)
                    }
                }
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tasks Section

private struct TasksSection: View {
    @ObservedObject var service: TaskService

    var tasksByPriority: [(priority: String, count: Int)] {
        let priorities = ["urgent", "high", "medium", "low"]
        return priorities.compactMap { p in
            let count = service.tasks.filter { $0.priority == p }.count
            return count > 0 ? (p, count) : nil
        }
    }

    var completionRate: Double {
        guard !service.tasks.isEmpty else { return 0 }
        let done = service.tasks.filter { $0.isCompleted }.count
        return Double(done) / Double(service.tasks.count) * 100
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                KPICard(label: "Open", value: "\(service.openCount)", icon: "circle")
                KPICard(label: "Overdue", value: "\(service.overdueCount)", icon: "exclamationmark.circle", positive: service.overdueCount == 0)
                KPICard(label: "Done/7d", value: "\(service.completedThisWeek)", icon: "checkmark.circle.fill", positive: true)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Completion Rate")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", completionRate))
                            .font(.headline)
                            .foregroundStyle(.primary)
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
                        }
                    }
                    .frame(height: 10)
                }
            }

            if !tasksByPriority.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("By Priority")
                            .font(.headline)

                        Chart(tasksByPriority, id: \.priority) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Priority", item.priority.capitalized)
                            )
                            .foregroundStyle(priorityColor(item.priority).opacity(0.7))
                            .cornerRadius(6)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { val in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.primary.opacity(0.06))
                                AxisValueLabel().foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 130)
                    }
                }
            }
        }
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "urgent": return .red
        case "high":   return .orange
        case "medium": return .yellow
        default:       return .blue
        }
    }
}

// MARK: - Forecast Section

private struct ForecastSection: View {
    @ObservedObject var financialService: FinancialService

    var projectedIncome: Double {
        let months = financialService.monthlyData
        guard !months.isEmpty else { return 0 }
        let avg = months.map(\.income).reduce(0, +) / Double(months.count)
        return avg * 12
    }

    var projectedExpenses: Double {
        let months = financialService.monthlyData
        guard !months.isEmpty else { return 0 }
        let avg = months.map(\.expenses).reduce(0, +) / Double(months.count)
        return avg * 12
    }

    var symbol: String { financialService.currencySymbol }

    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("12-Month Projection")
                                .font(.headline)
                            Text("Based on last 6 months")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("AI", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    VStack(spacing: 12) {
                        ForecastRow(
                            label: "Projected Income",
                            value: "\(symbol)\(Int(projectedIncome))",
                            trend: projectedIncome > 0 ? "annualized" : "—",
                            positive: true
                        )
                        ForecastRow(
                            label: "Projected Expenses",
                            value: "\(symbol)\(Int(projectedExpenses))",
                            trend: projectedExpenses > 0 ? "annualized" : "—"
                        )
                        Divider().background(Color.primary.opacity(0.1))
                        ForecastRow(
                            label: "Net Profit",
                            value: "\(symbol)\(Int(projectedIncome - projectedExpenses))",
                            trend: "estimate",
                            positive: projectedIncome > projectedExpenses
                        )
                    }
                }
            }

            if financialService.records.isEmpty {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.primary.opacity(0.2))
                        Text("Add financial records to see your forecast")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

private struct ForecastRow: View {
    let label: String
    let value: String
    let trend: String
    var positive: Bool = false

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(.subheadline.weight(.semibold))
                Text(trend).font(.caption).foregroundStyle(positive ? Color.primary.opacity(0.5) : Color.secondary)
            }
        }
    }
}

private struct KPICard: View {
    let label: String
    let value: String
    let icon: String
    var positive: Bool = false

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(icon: icon, size: 30)
                Text(value)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

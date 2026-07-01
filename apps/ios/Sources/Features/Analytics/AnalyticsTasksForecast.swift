import SwiftUI
import Charts

// MARK: - Tasks Section

struct TasksSection: View {
    var service: TaskService

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
                TrendKPICard(label: "Open", value: "\(service.openCount)", icon: "circle", trendPct: nil, trendPositive: true)
                TrendKPICard(label: "Overdue", value: "\(service.overdueCount)", icon: "exclamationmark.circle",
                             trendPct: nil, trendPositive: service.overdueCount == 0,
                             highlightValue: service.overdueCount > 0, positiveValue: false)
                TrendKPICard(label: "Done/7d", value: "\(service.completedThisWeek)", icon: "checkmark.circle.fill",
                             trendPct: nil, trendPositive: true, highlightValue: service.completedThisWeek > 0, positiveValue: true)
            }

            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Completion rate")
                            .font(AppFont.subheadline)
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
                        Text("By priority")
                            .font(AppFont.subheadline)

                        Chart(tasksByPriority, id: \.priority) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Priority", item.priority.capitalized)
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

struct ForecastSection: View {
    var financialService: FinancialService

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
                            Text("12-month projection")
                                .font(AppFont.subheadline)
                            Text("Based on the last \(financialService.monthlyData.count) months")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("AI", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xxs)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    VStack(spacing: 12) {
                        ForecastRow(label: "Projected income",
                                    value: "\(sym)\(Int(projectedIncome))",
                                    sub: "annual", positive: true)
                        Divider().background(Color.primary.opacity(AppOpacity.subtleFill))
                        ForecastRow(label: "Projected expenses",
                                    value: "\(sym)\(Int(projectedExpenses))",
                                    sub: "annual", positive: false)
                        Divider().background(Color.primary.opacity(AppOpacity.subtleFill))
                        ForecastRow(label: "Estimated net profit",
                                    value: "\(netProfit >= 0 ? "+" : "")\(sym)\(Int(netProfit))",
                                    sub: "estimated", positive: netProfit >= 0)
                    }
                }
            }

            if !financialService.monthlyData.isEmpty {
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Expense trend")
                            .font(AppFont.subheadline)

                        Chart {
                            ForEach(financialService.monthlyData, id: \.month) { item in
                                BarMark(
                                    x: .value("Month", item.month),
                                    y: .value("Expenses", item.expenses)
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
                        Text("Add financial records to see the forecast")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                }
            }
        }
    }
}

// MARK: - ForecastRow

struct ForecastRow: View {
    let label: LocalizedStringKey
    let value: String
    let sub: LocalizedStringKey
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

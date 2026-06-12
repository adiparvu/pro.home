import SwiftUI
import Charts

struct AnalyticsView: View {
    @State private var selectedTab: AnalyticsTab = .occupancy

    enum AnalyticsTab: String, CaseIterable {
        case occupancy = "Occupancy"
        case yield = "Yield"
        case forecast = "Forecast"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader(title: "Analytics")
                    .padding(.bottom, 16)

                // Tab picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? .black : .white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedTab == tab ? .white : .white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .occupancy: OccupancySection()
                        case .yield: YieldSection()
                        case .forecast: ForecastSection()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
    }
}

// MARK: - Occupancy

private struct OccupancySection: View {
    let data: [(month: String, rate: Double)] = [
        ("Jan", 72), ("Feb", 85), ("Mar", 91), ("Apr", 88),
        ("May", 94), ("Jun", 78)
    ]

    var body: some View {
        VStack(spacing: 16) {
            // KPI row
            HStack(spacing: 12) {
                KPICard(label: "Avg Rate", value: "84.7%", icon: "percent")
                KPICard(label: "Peak Month", value: "May", icon: "calendar")
                KPICard(label: "Trend", value: "+3.2%", icon: "arrow.up.right", positive: true)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Occupancy Rate")
                        .font(.headline)

                    Chart(data, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.month),
                            y: .value("Rate", item.rate)
                        )
                        .foregroundStyle(.white.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { val in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.06))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }
}

// MARK: - Yield

private struct YieldSection: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                KPICard(label: "Gross Yield", value: "6.8%", icon: "percent")
                KPICard(label: "Net Yield", value: "4.2%", icon: "banknote")
                KPICard(label: "Annual ROI", value: "€8.4k", icon: "chart.line.uptrend.xyaxis", positive: true)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Monthly Income vs Expenses")
                        .font(.headline)

                    Chart {
                        ForEach(incomeData, id: \.month) { item in
                            LineMark(
                                x: .value("Month", item.month),
                                y: .value("Amount", item.income)
                            )
                            .foregroundStyle(.white.opacity(0.8))
                            .symbol(Circle().strokeBorder(lineWidth: 2))
                        }
                        ForEach(incomeData, id: \.month) { item in
                            LineMark(
                                x: .value("Month", item.month),
                                y: .value("Amount", item.expenses)
                            )
                            .foregroundStyle(.white.opacity(0.3))
                            .lineStyle(StrokeStyle(dash: [4, 4]))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { val in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.06))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    let incomeData: [(month: String, income: Double, expenses: Double)] = [
        ("Jan", 2800, 620), ("Feb", 3100, 890), ("Mar", 3200, 720),
        ("Apr", 2950, 810), ("May", 3400, 680), ("Jun", 3200, 890)
    ]
}

// MARK: - Forecast

private struct ForecastSection: View {
    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("12-Month Forecast")
                                .font(.headline)
                            Text("Based on current trends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("AI", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.08), in: Capsule())
                    }

                    VStack(spacing: 12) {
                        ForecastRow(label: "Projected Income", value: "€39,600", trend: "+8.3%", positive: true)
                        ForecastRow(label: "Projected Expenses", value: "€9,200", trend: "+2.1%")
                        ForecastRow(label: "Net Profit", value: "€30,400", trend: "+10.5%", positive: true)
                        ForecastRow(label: "Avg Occupancy", value: "86%", trend: "+1.9%", positive: true)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Upcoming Events")
                        .font(.headline)
                    ForEach(upcomingEvents, id: \.title) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.subheadline)
                                Text(event.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.impact)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    let upcomingEvents = [
        (title: "Boiler service due", date: "Jun 15", impact: "−€280"),
        (title: "Lease renewal", date: "Jul 1", impact: "+€150/mo"),
        (title: "Insurance renewal", date: "Aug 30", impact: "−€620"),
    ]
}

private struct ForecastRow: View {
    let label: String
    let value: String
    let trend: String
    var positive: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(trend)
                    .font(.caption)
                    .foregroundStyle(positive ? .white.opacity(0.5) : .secondary)
            }
        }
    }
}

// MARK: - Shared

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
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

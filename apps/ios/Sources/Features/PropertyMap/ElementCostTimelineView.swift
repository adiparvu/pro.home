import SwiftUI
import Charts

// Cumulative cost over time for an element, built from its records' cost+date.

struct ElementCostTimeline: View {
    let records: [ElementRecord]
    let currency: String

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let cumulative: Double
    }

    private var points: [Point] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let withCost: [(Date, Double)] = records.compactMap { r in
            guard let c = r.cost, c != 0,
                  let d = f.date(from: String(r.recordDate.prefix(10))) else { return nil }
            return (d, c)
        }.sorted { $0.0 < $1.0 }
        var run = 0.0
        return withCost.map { run += $0.1; return Point(date: $0.0, cumulative: run) }
    }

    var body: some View {
        if points.count >= 2 {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Cumulative cost", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f %@", points.last?.cumulative ?? 0, currency))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brandSuccess)
                    }
                    Chart(points) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("Cost", p.cumulative))
                            .foregroundStyle(.linearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", p.date), y: .value("Cost", p.cumulative))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)
                    }
                    .frame(height: 130)
                }
            }
        }
    }
}

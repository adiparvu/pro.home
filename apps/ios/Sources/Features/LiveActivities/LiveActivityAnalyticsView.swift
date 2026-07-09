import SwiftUI
import Charts

// MARK: - Live Activity Analytics
//
// Every number on this screen is computed from LiveActivityHubStore's REAL
// event log — the same records the timeline shows. No metric is estimated,
// extrapolated or invented: when the log can't answer a question (e.g. no
// started→ended pair exists yet), the tile honestly shows "—".

struct LiveActivityAnalyticsView: View {
    private var store: LiveActivityHubStore { .shared }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.lg) {
                if store.events.isEmpty {
                    EmptyStateView(icon: "chart.bar.xaxis",
                                   title: "la_analytics_empty")
                        .padding(.top, 60)
                } else {
                    summaryCard
                    if !topKinds.isEmpty { topKindsCard }
                    last30Card
                }
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("la_analytics_title")
        .navigationBarTitleDisplayMode(.large)
        .task { store.reloadEvents() }
    }

    // MARK: Summary metrics

    private struct Summary {
        var started = 0
        var completed = 0
        var endedEarly = 0
        var avgDuration: TimeInterval?
    }

    /// Walks the log chronologically, pairing each `started` with the next
    /// `ended`/`completed` of the same kind+title. Only real pairs feed the
    /// average — an unmatched start contributes nothing.
    private var summary: Summary {
        var s = Summary()
        var open: [String: Date] = [:]
        var durations: [TimeInterval] = []
        for event in store.events.sorted(by: { $0.at < $1.at }) {
            let key = event.kind + "|" + event.title
            switch event.phase {
            case "started":
                s.started += 1
                open[key] = event.at
            case "completed", "ended":
                if event.phase == "completed" { s.completed += 1 } else { s.endedEarly += 1 }
                if let began = open.removeValue(forKey: key) {
                    let d = event.at.timeIntervalSince(began)
                    if d >= 0 { durations.append(d) }
                }
            default:
                break
            }
        }
        if !durations.isEmpty {
            s.avgDuration = durations.reduce(0, +) / Double(durations.count)
        }
        return s
    }

    private var summaryCard: some View {
        let s = summary
        return GlassCard {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md),
                                GridItem(.flexible(), spacing: AppSpacing.md)],
                      spacing: AppSpacing.lg) {
                statTile(value: "\(s.started)", label: "la_analytics_total",
                         tint: .brandSkyBlue)
                statTile(value: "\(s.completed)", label: "la_analytics_completed",
                         tint: .brandSuccess)
                statTile(value: "\(s.endedEarly)", label: "la_analytics_canceled",
                         tint: .brandWarning)
                statTile(value: s.avgDuration.map { Self.formatDuration($0) } ?? "—",
                         label: "la_analytics_avg_duration", tint: .brandTeal)
            }
        }
    }

    private func statTile(value: String, label: LocalizedStringKey,
                          tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: value)
                .font(AppFont.title2)
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .monospacedDigit()
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(Color.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: value))
    }

    nonisolated private static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: Top kinds (started count per kind, top 5)

    private var topKinds: [(kind: LiveActivityKind, count: Int)] {
        var counts: [LiveActivityKind: Int] = [:]
        for event in store.events where event.phase == "started" {
            if let kind = LiveActivityKind(rawValue: event.kind) {
                counts[kind, default: 0] += 1
            }
        }
        return Array(counts.map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5))
    }

    private var topKindsCard: some View {
        let data = topKinds
        return GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("la_analytics_top_kinds")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Chart(data, id: \.kind) { entry in
                    BarMark(
                        x: .value("Count", entry.count),
                        y: .value("Kind", entry.kind.rawValue)
                    )
                    .foregroundStyle(entry.kind.color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing, spacing: AppSpacing.xs) {
                        Text(verbatim: "\(entry.count)")
                            .font(AppFont.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let raw = value.as(String.self),
                               let kind = LiveActivityKind(rawValue: raw) {
                                Text(kind.title)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(Color.secondaryTextColor)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(data.count) * 40 + 8)
                .accessibilityLabel(Text("la_analytics_top_kinds"))
            }
        }
    }

    // MARK: Last 30 days (daily started counts)

    private var last30Days: [(day: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -29, to: today) else { return [] }
        var counts: [Date: Int] = [:]
        for event in store.events where event.phase == "started" {
            let day = cal.startOfDay(for: event.at)
            if day >= start && day <= today {
                counts[day, default: 0] += 1
            }
        }
        return (0..<30).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (day: day, count: counts[day] ?? 0)
        }
    }

    private var last30Card: some View {
        let data = last30Days
        let total = data.reduce(0) { $0 + $1.count }
        return GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("la_analytics_last30")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                if total == 0 {
                    // Real events exist, just none in this window — say so
                    // instead of drawing a chart of nothing.
                    Text("la_analytics_no_recent")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl)
                } else {
                    Chart(data, id: \.day) { entry in
                        BarMark(
                            x: .value("Day", entry.day, unit: .day),
                            y: .value("Count", entry.count)
                        )
                        .foregroundStyle(Color.brandSkyBlue.gradient)
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month())
                        }
                    }
                    .frame(height: 160)
                    .accessibilityLabel(Text("la_analytics_last30"))
                }
            }
        }
    }
}

import WidgetKit
import SwiftUI

// MARK: - Notification Center / Smart Stack widget
// Shows property health + urgent alert, designed to surface at relevant moments via TimelineEntryRelevance

struct NotificationCenterWidget: Widget {
    let kind = "PRVIOAlertsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOAlertsProvider()) { entry in
            NotificationCenterWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringKey("PRVIO Alerts"))
        .description(LocalizedStringKey("Property health and urgent alerts."))
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Provider with relevance scoring

struct PRVIOAlertsProvider: TimelineProvider {
    func makeEntry() -> PRVIOAlertsEntry {
        let snap = SharedDataStore.read() ?? PRVIOWidgetSnapshot()
        // Boost relevance when there are urgent items
        let urgency = snap.overdueTaskCount + snap.plantsNeedingWater
        let score = min(Float(urgency) * 2.5, 10.0)
        let relevance = urgency > 0
            ? TimelineEntryRelevance(score: score, duration: 3600)
            : TimelineEntryRelevance(score: 0.5, duration: 900)
        return PRVIOAlertsEntry(date: Date(), snapshot: snap, relevance: relevance)
    }

    func placeholder(in context: Context) -> PRVIOAlertsEntry { makeEntry() }

    func getSnapshot(in context: Context, completion: @escaping (PRVIOAlertsEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PRVIOAlertsEntry>) -> Void) {
        let entry = makeEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct PRVIOAlertsEntry: TimelineEntry {
    let date: Date
    let snapshot: PRVIOWidgetSnapshot
    var relevance: TimelineEntryRelevance?
}

// MARK: - Small View

struct NotificationCenterSmallView: View {
    let entry: PRVIOAlertsEntry

    private var alertCount: Int { entry.snapshot.overdueTaskCount + entry.snapshot.plantsNeedingWater }
    private var healthScore: Int { entry.snapshot.propertyHealthScore ?? 100 }

    private var statusColor: Color {
        if alertCount > 0 { return .red }
        if healthScore < 70 { return .orange }
        return .green
    }

    private var statusIcon: String {
        if alertCount > 0 { return "exclamationmark.triangle.fill" }
        if healthScore < 70 { return "exclamationmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.regularMaterial)

            VStack(spacing: 0) {
                // Health arc header
                ZStack {
                    // Track first, progress on top — the reverse hid the arc
                    // under the gray ring.
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 4)
                        .frame(width: 52, height: 52)

                    Circle()
                        .trim(from: 0, to: CGFloat(healthScore) / 100)
                        .stroke(statusColor.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 52, height: 52)

                    VStack(spacing: 0) {
                        Text("\(healthScore)")
                            .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(AppFont.scaled(8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)

                Text("Health")
                    .font(AppFont.scaled(9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Spacer()

                // Alert summary
                if alertCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(AppFont.scaled(10, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Text(alertCount == 1 ? String(localized: "1 alert") : String(format: String(localized: "%d alerts"), alertCount))
                            .font(AppFont.label)
                            .foregroundStyle(statusColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12), in: Capsule())
                } else if let name = entry.snapshot.propertyName {
                    Text(name)
                        .font(AppFont.scaled(10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Critical task
                if let critical = entry.snapshot.criticalTaskTitle {
                    Text(critical)
                        .font(AppFont.scaled(10))
                        .foregroundStyle(.primary.opacity(0.6))
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                Spacer().frame(height: 10)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://alerts"))
    }
}

// MARK: - Rectangular (Notification Center / Lock Screen)

struct NotificationCenterRectangularView: View {
    let entry: PRVIOAlertsEntry

    private var alertCount: Int { entry.snapshot.overdueTaskCount + entry.snapshot.plantsNeedingWater }
    private var healthScore: Int { entry.snapshot.propertyHealthScore ?? 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                // Only the meaningful alert glyph shows; the all-clear state is
                // text-only (no generic-house icon), per the owner's call. The
                // brand mark can't render here (accent-tinted SF-Symbol only).
                if alertCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFont.scaled(10, weight: .semibold))
                        .widgetAccentable()
                }
                Text("PRVIO")
                    .font(AppFont.scaled(11, weight: .bold))
                Spacer()
                Text(String(format: String(localized: "Health %d%%"), healthScore))
                    .font(AppFont.scaled(10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if alertCount > 0 {
                HStack(spacing: 8) {
                    if entry.snapshot.overdueTaskCount > 0 {
                        Label(String(format: String(localized: "%d overdue"), entry.snapshot.overdueTaskCount), systemImage: "checklist")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(.red)
                    }
                    if entry.snapshot.plantsNeedingWater > 0 {
                        Label(String(format: String(localized: "%d plants"), entry.snapshot.plantsNeedingWater), systemImage: "drop.fill")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("All clear — no urgent alerts")
                    .font(AppFont.scaled(10))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://alerts"))
    }
}

// MARK: - Dispatcher

struct NotificationCenterWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOAlertsEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: NotificationCenterRectangularView(entry: entry)
        default:                    NotificationCenterSmallView(entry: entry)
        }
    }
}

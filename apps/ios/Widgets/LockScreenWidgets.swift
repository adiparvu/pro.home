import WidgetKit
import SwiftUI

// MARK: - Lock Screen Tasks Widget (Circular)

struct LockScreenTasksWidget: Widget {
    let kind = "LockScreenTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenTasksView(entry: entry)
        }
        .configurationDisplayName("Tasks (Lock Screen)")
        .description("Pending tasks count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenTasksView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        ZStack {
            if entry.snapshot.overdueTaskCount > 0 {
                Circle()
                    .fill(Color.red.opacity(0.15))
                VStack(spacing: 1) {
                    Text("\(entry.snapshot.overdueTaskCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else {
                Circle()
                    .fill(Color.green.opacity(0.15))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: - Lock Screen Plants Widget (Circular)

struct LockScreenPlantsWidget: Widget {
    let kind = "LockScreenPlantsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenPlantsView(entry: entry)
        }
        .configurationDisplayName("Plants (Lock Screen)")
        .description("Plants that need watering.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenPlantsView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        ZStack {
            if entry.snapshot.plantsNeedingWater > 0 {
                Circle().fill(Color.orange.opacity(0.15))
                VStack(spacing: 1) {
                    Text("\(entry.snapshot.plantsNeedingWater)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "drop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else {
                Circle().fill(Color.green.opacity(0.15))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22))
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://plants"))
    }
}

// MARK: - Lock Screen Dashboard (Rectangular)

struct LockScreenDashboardWidget: Widget {
    let kind = "LockScreenDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenDashboardView(entry: entry)
        }
        .configurationDisplayName("PRVIO (Lock Screen)")
        .description("Quick PRVIO overview on the lock screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenDashboardView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .widgetAccentable()
                    Text(entry.snapshot.propertyName ?? "PRVIO")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Label("\(entry.snapshot.overdueTaskCount)", systemImage: "checklist")
                        .font(.system(size: 11))
                    Label("\(entry.snapshot.plantsNeedingWater)", systemImage: "leaf.fill")
                        .font(.system(size: 11))
                    Label("\(entry.snapshot.activeDeliveryCount)", systemImage: "shippingbox.fill")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "prvio://"))

        default: // .accessoryInline
            Label {
                Text(inlineText)
            } icon: {
                Image(systemName: "house.fill")
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "prvio://"))
        }
    }

    private var inlineText: String {
        var parts: [String] = []
        if entry.snapshot.overdueTaskCount > 0 {
            parts.append("\(entry.snapshot.overdueTaskCount) tasks")
        }
        if entry.snapshot.plantsNeedingWater > 0 {
            parts.append("\(entry.snapshot.plantsNeedingWater) plants")
        }
        return parts.isEmpty ? "PRVIO ✓" : parts.joined(separator: " · ")
    }
}

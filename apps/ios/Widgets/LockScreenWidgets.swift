import WidgetKit
import SwiftUI

// MARK: - Lock Screen widget suite
//
// Accessory widgets follow the HIG: AccessoryWidgetBackground for circulars,
// .widgetAccentable() on the primary glyph so tinted Lock Screens color the
// right element, and a deep link straight to the matching screen.

// MARK: Tasks (Circular)

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
            AccessoryWidgetBackground()
            if entry.snapshot.overdueTaskCount > 0 {
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.overdueTaskCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("late")
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            } else if entry.snapshot.openTaskCount > 0 {
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.openTaskCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "checklist")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .medium))
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: Plants (Circular)

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
            AccessoryWidgetBackground()
            if entry.snapshot.plantsNeedingWater > 0 {
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.plantsNeedingWater)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "drop.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 24, weight: .medium))
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://plants"))
    }
}

// MARK: Health Score (Circular gauge)

struct LockScreenHealthWidget: Widget {
    let kind = "LockScreenHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenHealthView(entry: entry)
        }
        .configurationDisplayName("Health Score (Lock Screen)")
        .description("Your home's health score at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenHealthView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        let score = entry.snapshot.propertyHealthScore ?? 0
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: Double(score), in: 0...100) {
                Image(systemName: "house.fill")
            } currentValueLabel: {
                Text("\(score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://twin"))
    }
}

// MARK: Deliveries (Circular + Inline)

struct LockScreenDeliveriesWidget: Widget {
    let kind = "LockScreenDeliveriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenDeliveriesView(entry: entry)
        }
        .configurationDisplayName("Deliveries (Lock Screen)")
        .description("Packages on the way.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct LockScreenDeliveriesView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text(entry.snapshot.activeDeliveryCount > 0
                     ? String(format: String(localized: "%d packages on the way"), entry.snapshot.activeDeliveryCount)
                     : String(localized: "No packages expected"))
            } icon: {
                Image(systemName: "shippingbox.fill")
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "prvio://deliveries"))

        default: // .accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                if entry.snapshot.activeDeliveryCount > 0 {
                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.activeDeliveryCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .widgetAccentable()
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                        .widgetAccentable()
                }
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "prvio://deliveries"))
        }
    }
}

// MARK: Messages (Circular)

struct LockScreenMessagesWidget: Widget {
    let kind = "LockScreenMessagesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenMessagesView(entry: entry)
        }
        .configurationDisplayName("Family Chat (Lock Screen)")
        .description("Unread messages in the family chat.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenMessagesView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.snapshot.unreadMessages > 0 {
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.unreadMessages)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://chat"))
    }
}

// MARK: Next Task (Rectangular)

struct LockScreenNextTaskWidget: Widget {
    let kind = "LockScreenNextTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenNextTaskView(entry: entry)
        }
        .configurationDisplayName("Next Task (Lock Screen)")
        .description("What's next on your home's list.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenNextTaskView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // An overdue task takes priority over the next scheduled one.
            if let critical = entry.snapshot.criticalTaskTitle {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .widgetAccentable()
                    Text("Overdue")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(critical)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            } else if let next = entry.snapshot.nextMaintenanceTitle {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                        .widgetAccentable()
                    Text("Next task")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(next)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let due = entry.snapshot.nextMaintenanceDue {
                    Text(due)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .widgetAccentable()
                    Text("All caught up")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("No upcoming tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: Dashboard (Rectangular + Inline)

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
                    if let score = entry.snapshot.propertyHealthScore {
                        Spacer(minLength: 4)
                        Text("\(score)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Label("\(entry.snapshot.overdueTaskCount)", systemImage: "checklist")
                        .font(.system(size: 11))
                    Label("\(entry.snapshot.plantsNeedingWater)", systemImage: "leaf.fill")
                        .font(.system(size: 11))
                    Label("\(entry.snapshot.activeDeliveryCount)", systemImage: "shippingbox.fill")
                        .font(.system(size: 11))
                    if entry.snapshot.unreadMessages > 0 {
                        Label("\(entry.snapshot.unreadMessages)", systemImage: "bubble.left.fill")
                            .font(.system(size: 11))
                    }
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
            parts.append(String(format: String(localized: "%d tasks"), entry.snapshot.overdueTaskCount))
        }
        if entry.snapshot.plantsNeedingWater > 0 {
            parts.append(String(format: String(localized: "%d plants"), entry.snapshot.plantsNeedingWater))
        }
        if entry.snapshot.activeDeliveryCount > 0 {
            parts.append(String(format: String(localized: "%d packages"), entry.snapshot.activeDeliveryCount))
        }
        return parts.isEmpty ? String(localized: "All good at home") : parts.joined(separator: " · ")
    }
}

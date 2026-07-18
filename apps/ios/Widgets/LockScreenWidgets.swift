import WidgetKit
import SwiftUI

// MARK: - Lock Screen widget suite
//
// Accessory widgets follow the HIG: AccessoryWidgetBackground for circulars,
// .widgetAccentable() on the primary glyph so tinted Lock Screens color the
// right element, and a deep link straight to the matching screen.
//
// Rectangular accessories are INTERACTIVE (iOS 17 App Intents in widgets):
// the trailing button runs the same CompleteTaskIntent/WaterPlantIntent the
// home-screen widgets use — pending queue + instant local catalog echo —
// so a task can be checked off or a plant watered without ever unlocking
// past the Lock Screen. A button only renders when the row resolves to a
// real catalog id; no dead controls.

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
                        .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("late")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            } else if entry.snapshot.openTaskCount > 0 {
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.openTaskCount)")
                        .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "checklist")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(26, weight: .medium))
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
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenPlantsView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    private func makeWaterIntent(_ plant: PlantCatalogEntry) -> WaterPlantIntent {
        var i = WaterPlantIntent()
        i.plant = PlantEntity(id: plant.id, name: plant.name, emoji: plant.emoji)
        return i
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            let thirsty = Array(entry.plantCatalog.filter(\.needsWatering).prefix(2))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .widgetAccentable()
                    Text(thirsty.isEmpty ? String(localized: "Plants") : String(localized: "Needs water"))
                        .font(AppFont.scaled(9, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                if thirsty.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(AppFont.captionStrong)
                            .widgetAccentable()
                        Text("All watered")
                            .font(AppFont.captionEmphasis)
                    }
                } else {
                    ForEach(thirsty, id: \.id) { plant in
                        HStack(spacing: 5) {
                            Text(plant.emoji)
                                .font(AppFont.scaled(11))
                            Text(plant.name)
                                .font(AppFont.scaled(12))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Button(intent: makeWaterIntent(plant)) {
                                Image(systemName: "drop.circle")
                                    .font(AppFont.scaled(17, weight: .medium))
                                    .widgetAccentable()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "prvio://plants"))

        default: // .accessoryCircular
            circularBody
        }
    }

    private var circularBody: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.snapshot.plantsNeedingWater > 0 {
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.plantsNeedingWater)")
                        .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "drop.fill")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "leaf.fill")
                    .font(AppFont.scaled(24, weight: .medium))
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
                    .font(AppFont.scaled(18, weight: .bold, design: .rounded))
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
                            .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                            .widgetAccentable()
                        Image(systemName: "shippingbox.fill")
                            .font(AppFont.scaled(9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "shippingbox")
                        .font(AppFont.scaled(22, weight: .medium))
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
        .configurationDisplayName("Chat (Lock Screen)")
        .description("Unread messages in chat.")
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
                        .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(AppFont.scaled(8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(AppFont.scaled(20, weight: .medium))
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

    /// The catalog row behind the shown title. The snapshot carries only the
    /// title; the id lives in the task catalog written by the same beat. When
    /// the two can't be joined (stale catalog, duplicate titles resolved to
    /// completed rows) the widget honestly shows no button rather than a
    /// checkmark that completes the wrong task.
    private var shownTask: TaskCatalogEntry? {
        guard let title = entry.snapshot.criticalTaskTitle
                ?? entry.snapshot.nextMaintenanceTitle else { return nil }
        return entry.taskCatalog.first { !$0.isCompleted && $0.title == title }
    }

    private func makeCompleteIntent(_ task: TaskCatalogEntry) -> CompleteTaskIntent {
        var i = CompleteTaskIntent()
        i.task = TaskEntity(id: task.id, title: task.title, priority: task.priority)
        return i
    }

    var body: some View {
        HStack(spacing: 6) {
            content
            if let task = shownTask {
                Button(intent: makeCompleteIntent(task)) {
                    Image(systemName: "circle")
                        .font(AppFont.scaled(18, weight: .medium))
                        .widgetAccentable()
                }
                .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://tasks"))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            // An overdue task takes priority over the next scheduled one.
            if let critical = entry.snapshot.criticalTaskTitle {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(AppFont.scaled(10, weight: .semibold))
                        .widgetAccentable()
                    Text("Overdue")
                        .font(AppFont.scaled(10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(critical)
                    .font(AppFont.captionEmphasis)
                    .lineLimit(2)
            } else if let next = entry.snapshot.nextMaintenanceTitle {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(AppFont.scaled(10, weight: .semibold))
                        .widgetAccentable()
                    Text("Next task")
                        .font(AppFont.scaled(10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(next)
                    .font(AppFont.captionEmphasis)
                    .lineLimit(1)
                if let due = entry.snapshot.nextMaintenanceDue {
                    Text(due)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFont.captionStrong)
                        .widgetAccentable()
                    Text("All caught up")
                        .font(AppFont.captionEmphasis)
                }
                Text("No upcoming tasks")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Upcoming deadlines (Rectangular)

struct LockScreenUpcomingWidget: Widget {
    let kind = "LockScreenUpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenUpcomingView(entry: entry)
        }
        .configurationDisplayName("Upcoming (Lock Screen)")
        .description("Your next deadlines from the house calendar.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenUpcomingView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        let items = Array(entry.snapshot.upcomingDeadlines.prefix(3))
        VStack(alignment: .leading, spacing: 2) {
            if items.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFont.captionStrong)
                        .widgetAccentable()
                    Text("Nothing upcoming")
                        .font(AppFont.captionEmphasis)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .widgetAccentable()
                    Text("Upcoming")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                ForEach(items, id: \.self) { deadline in
                    HStack(spacing: 5) {
                        Image(systemName: deadline.icon)
                            .font(AppFont.scaled(10, weight: .semibold))
                            .frame(width: 12)
                        Text(deadline.title)
                            .font(AppFont.scaled(12))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(deadline.date, format: .relative(presentation: .named))
                            .font(AppFont.scaled(10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: Shopping (Rectangular, interactive)

struct LockScreenShoppingWidget: Widget {
    let kind = "LockScreenShoppingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            LockScreenShoppingView(entry: entry)
        }
        .configurationDisplayName("Shopping (Lock Screen)")
        .description("Check off items without opening the app.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenShoppingView: View {
    let entry: PRVIOWidgetEntry

    private func makeCheckIntent(_ item: SupplyCatalogEntry) -> CheckSupplyItemIntent {
        var i = CheckSupplyItemIntent()
        i.item = SupplyItemEntity(id: item.id, name: item.name)
        return i
    }

    var body: some View {
        let toBuy = Array(entry.supplyCatalog.filter { !$0.isCompleted }.prefix(2))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "cart.fill")
                    .font(AppFont.scaled(9, weight: .semibold))
                    .widgetAccentable()
                Text("Shopping")
                    .font(AppFont.scaled(9, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            if toBuy.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFont.captionStrong)
                        .widgetAccentable()
                    Text("Nothing to buy")
                        .font(AppFont.captionEmphasis)
                }
            } else {
                ForEach(toBuy, id: \.id) { item in
                    HStack(spacing: 5) {
                        Text(item.name)
                            .font(AppFont.scaled(12))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Button(intent: makeCheckIntent(item)) {
                            Image(systemName: "circle")
                                .font(AppFont.scaled(17, weight: .medium))
                                .widgetAccentable()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://shopping"))
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
                    // Text only — no generic-house glyph (per the owner's call).
                    // The raster brand mark can't render in accessory widgets.
                    Text(entry.snapshot.propertyName ?? "PRVIO")
                        .font(AppFont.label)
                        .lineLimit(1)
                    if let score = entry.snapshot.propertyHealthScore {
                        Spacer(minLength: 4)
                        Text("\(score)")
                            .font(AppFont.scaled(11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Label("\(entry.snapshot.openTaskCount)", systemImage: "checklist")
                        .font(AppFont.scaled(11))
                    Label("\(entry.snapshot.plantsNeedingWater)", systemImage: "leaf.fill")
                        .font(AppFont.scaled(11))
                    Label("\(entry.snapshot.activeDeliveryCount)", systemImage: "shippingbox.fill")
                        .font(AppFont.scaled(11))
                    if entry.snapshot.unreadMessages > 0 {
                        Label("\(entry.snapshot.unreadMessages)", systemImage: "bubble.left.fill")
                            .font(AppFont.scaled(11))
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
        if entry.snapshot.openTaskCount > 0 {
            parts.append(String(format: String(localized: "%d tasks"), entry.snapshot.openTaskCount))
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

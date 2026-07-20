import WidgetKit
import SwiftUI

// MARK: - Dashboard Widget

struct DashboardWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            DashboardWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_overview_name", comment: ""))
        .description(NSLocalizedString("widget_overview_desc", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Shared background

private struct AerialBackground: View {
    var body: some View {
        ZStack {
            // Premium branded gradient base — always renders, so the widget looks
            // intentional even if the aerial image can't load in the extension.
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.20, blue: 0.52),
                         Color(red: 0.28, green: 0.22, blue: 0.60),
                         Color(red: 0.36, green: 0.20, blue: 0.68)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.white.opacity(0.14), .clear],
                           center: .topTrailing, startRadius: 8, endRadius: 320)
            // The property photo on top when available.
            Image("aerial_property")
                .resizable()
                .scaledToFill()
        }
    }
}

// MARK: - Small View

struct DashboardSmallView: View {
    // Tinted Home Screen (iOS 18): the system strips the aerial
    // containerBackground, so the legibility scrim must go with it — a
    // tinted slab over nothing reads as a stain.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PRVIOWidgetEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if renderingMode == .fullColor {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center, endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                if let name = entry.snapshot.propertyName {
                    Text(name)
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .widgetAccentable()
                }
                HStack(spacing: 10) {
                    miniStat(icon: "checklist",
                             value: "\(entry.snapshot.openTaskCount)",
                             color: entry.snapshot.overdueTaskCount > 0 ? .red : .green)
                    miniStat(icon: "leaf.fill",
                             value: "\(entry.snapshot.plantsNeedingWater)",
                             color: entry.snapshot.plantsNeedingWater > 0 ? .orange : .green)
                }
            }
            .padding(12)
        }
        .containerBackground(for: .widget) { AerialBackground() }
        .widgetURL(URL(string: "prvio://"))
    }

    private func miniStat(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(AppFont.scaled(10, weight: .semibold))
                .foregroundStyle(color)
                .widgetAccentable()
            Text(value)
                .font(AppFont.scaled(12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Medium View

struct DashboardMediumView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PRVIOWidgetEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if renderingMode == .fullColor {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                if let name = entry.snapshot.propertyName {
                    Text(name)
                        .font(AppFont.scaled(15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .widgetAccentable()
                }

                HStack(spacing: 0) {
                    statPill(icon: "checklist",
                             value: "\(entry.snapshot.openTaskCount)",
                             label: NSLocalizedString("widget_open", comment: ""),
                             color: entry.snapshot.overdueTaskCount > 0 ? .red : Color(red: 0.3, green: 0.9, blue: 0.5))
                    statPill(icon: "leaf.fill",
                             value: "\(entry.snapshot.plantsNeedingWater)",
                             label: NSLocalizedString("widget_plants_label", comment: ""),
                             color: entry.snapshot.plantsNeedingWater > 0 ? .orange : Color(red: 0.3, green: 0.9, blue: 0.5))
                    statPill(icon: "shippingbox.fill",
                             value: "\(entry.snapshot.activeDeliveryCount)",
                             label: NSLocalizedString("widget_deliveries", comment: ""),
                             color: entry.snapshot.activeDeliveryCount > 0 ? .blue : .white.opacity(0.5))
                    statPill(icon: "exclamationmark.triangle.fill",
                             value: "\(entry.snapshot.overdueTaskCount)",
                             label: NSLocalizedString("widget_overdue", comment: ""),
                             color: entry.snapshot.overdueTaskCount > 0 ? .red : .white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .containerBackground(for: .widget) { AerialBackground() }
        .widgetURL(URL(string: "prvio://"))
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(color)
                .widgetAccentable()
            Text(value)
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.scaled(9, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large View

struct DashboardLargeView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PRVIOWidgetEntry

    var pendingTasks: [TaskCatalogEntry] {
        entry.taskCatalog.filter { !$0.isCompleted && $0.priority == "high" }.prefix(3).map { $0 }
    }

    var needsWater: [PlantCatalogEntry] {
        entry.plantCatalog.filter { $0.needsWatering }.prefix(3).map { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if renderingMode == .fullColor {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.82)],
                    startPoint: .top, endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                // Property name + time
                HStack(alignment: .firstTextBaseline) {
                    if let name = entry.snapshot.propertyName {
                        Text(name)
                            .font(AppFont.scaled(17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                    Spacer()
                    Text(relativeTime)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.white.opacity(0.55))
                }

                // Stats row
                HStack(spacing: 0) {
                    largeStat(icon: "checklist",
                              value: "\(entry.snapshot.openTaskCount)",
                              label: "Tasks",
                              color: entry.snapshot.overdueTaskCount > 0 ? .red : Color(red: 0.3, green: 0.9, blue: 0.5))
                    largeStat(icon: "leaf.fill",
                              value: "\(entry.snapshot.plantsNeedingWater)",
                              label: "Plants",
                              color: entry.snapshot.plantsNeedingWater > 0 ? .orange : Color(red: 0.3, green: 0.9, blue: 0.5))
                    largeStat(icon: "shippingbox.fill",
                              value: "\(entry.snapshot.activeDeliveryCount)",
                              label: "Deliveries",
                              color: entry.snapshot.activeDeliveryCount > 0 ? .blue : .white.opacity(0.5))
                    largeStat(icon: "square.and.pencil",
                              value: "\(entry.snapshot.openTaskCount)",
                              label: "Open",
                              color: .white.opacity(0.6))
                }
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Urgent tasks
                if !pendingTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("URGENT")
                            .font(AppFont.scaled(9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        ForEach(pendingTasks, id: \.id) { task in
                            HStack(spacing: 6) {
                                Circle().fill(Color.red).frame(width: 5, height: 5)
                                Text(task.title)
                                    .font(AppFont.scaled(12))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                // Plants needing water
                if !needsWater.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEEDS WATER")
                            .font(AppFont.scaled(9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        HStack(spacing: 10) {
                            ForEach(needsWater, id: \.id) { plant in
                                HStack(spacing: 4) {
                                    Text(plant.emoji).font(AppFont.scaled(13))
                                    Text(plant.name)
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .containerBackground(for: .widget) { AerialBackground() }
        .widgetURL(URL(string: "prvio://"))
    }

    private func largeStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(color)
                .widgetAccentable()
            Text(value)
                .font(AppFont.title2)
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.scaled(9, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }

    private var relativeTime: String {
        let diff = Date().timeIntervalSince(entry.snapshot.updatedAt)
        if diff < 60 { return String(localized: "now") }
        if diff < 3600 { return "\(Int(diff/60))m" }
        return "\(Int(diff/3600))h"
    }
}

// MARK: - Dispatcher

struct DashboardWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:  DashboardSmallView(entry: entry)
        case .systemMedium: DashboardMediumView(entry: entry)
        case .systemLarge:  DashboardLargeView(entry: entry)
        default:            DashboardMediumView(entry: entry)
        }
    }
}

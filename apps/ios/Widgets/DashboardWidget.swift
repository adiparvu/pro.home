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
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Medium View

struct DashboardMediumView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRVIO")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.blue)
                    if let name = entry.snapshot.propertyName {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(formattedTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                statPill(icon: "checklist", value: "\(entry.snapshot.overdueTaskCount)",
                         label: NSLocalizedString("widget_overdue", comment: ""),
                         color: entry.snapshot.overdueTaskCount > 0 ? .red : .green)
                statPill(icon: "leaf.fill", value: "\(entry.snapshot.plantsNeedingWater)",
                         label: NSLocalizedString("widget_plants_label", comment: ""),
                         color: entry.snapshot.plantsNeedingWater > 0 ? .orange : .green)
                statPill(icon: "shippingbox.fill", value: "\(entry.snapshot.activeDeliveryCount)",
                         label: NSLocalizedString("widget_deliveries", comment: ""),
                         color: entry.snapshot.activeDeliveryCount > 0 ? .blue : .secondary)
                statPill(icon: "square.and.pencil", value: "\(entry.snapshot.openTaskCount)",
                         label: NSLocalizedString("widget_open", comment: ""),
                         color: .secondary)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://"))
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedTime: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: entry.date)
    }
}

// MARK: - Large View

struct DashboardLargeView: View {
    let entry: PRVIOWidgetEntry

    var pendingTasks: [TaskCatalogEntry] {
        entry.taskCatalog.filter { !$0.isCompleted && $0.priority == "high" }.prefix(3).map { $0 }
    }

    var needsWater: [PlantCatalogEntry] {
        entry.plantCatalog.filter { $0.needsWatering }.prefix(2).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRVIO")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.blue)
                    if let name = entry.snapshot.propertyName {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Updated")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(relativeTime)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Stats row
            HStack(spacing: 8) {
                largeStat(icon: "checklist", value: "\(entry.snapshot.overdueTaskCount)",
                          label: "Overdue", color: entry.snapshot.overdueTaskCount > 0 ? .red : .green)
                largeStat(icon: "leaf.fill", value: "\(entry.snapshot.plantsNeedingWater)",
                          label: "Plants", color: entry.snapshot.plantsNeedingWater > 0 ? .orange : .green)
                largeStat(icon: "shippingbox.fill", value: "\(entry.snapshot.activeDeliveryCount)",
                          label: "Deliveries", color: .blue)
            }

            // Urgent tasks
            if !pendingTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("URGENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(pendingTasks, id: \.id) { task in
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text(task.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // Plants needing water
            if !needsWater.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEEDS WATER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(needsWater, id: \.id) { plant in
                            HStack(spacing: 4) {
                                Text(plant.emoji).font(.system(size: 14))
                                Text(plant.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://"))
    }

    private func largeStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var relativeTime: String {
        let diff = Date().timeIntervalSince(entry.snapshot.updatedAt)
        if diff < 60 { return "now" }
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
        case .systemMedium: DashboardMediumView(entry: entry)
        case .systemLarge:  DashboardLargeView(entry: entry)
        default:            DashboardMediumView(entry: entry)
        }
    }
}

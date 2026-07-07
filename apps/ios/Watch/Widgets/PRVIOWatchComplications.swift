import WidgetKit
import SwiftUI

// MARK: - PRVIO watch-face complications
//
// The wrist-glance layer: WidgetKit accessory widgets for the watch face
// and the Smart Stack. They read the payload the phone pushed (cached by
// the watch app in the shared App Group), so the face, the Smart Stack,
// the watch app and the iPhone widgets all tell one story.

@main
struct PRVIOWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PRVIOStatusComplication()
        PRVIOTasksComplication()
        PRVIOWaterComplication()
        PRVIOShoppingComplication()
        PRVIODeliveriesComplication()
    }
}

struct PRVIOStatusComplication: Widget {
    let kind = "PRVIOWatchStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchPayloadProvider()) { entry in
            ComplicationView(payload: entry.payload)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("PRVIO")
        .description(NSLocalizedString("watch_complication_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Domain complications
//
// One complication per domain, so the watch face composes exactly what its
// owner cares about — each deep-links to its own page in the watch app.

struct PRVIOTasksComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchTasks", provider: WatchPayloadProvider()) { entry in
            DomainComplicationView(
                count: entry.payload?.snapshot.openTaskCount ?? 0,
                icon: "checklist",
                label: Text("watch_tasks"),
                urgent: (entry.payload?.snapshot.overdueTaskCount ?? 0) > 0,
                detail: entry.payload?.snapshot.criticalTaskTitle,
                url: URL(string: "prvio://tasks")
            )
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("PRVIO · Tasks")
        .description(NSLocalizedString("watch_comp_tasks_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct PRVIOWaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchWater", provider: WatchPayloadProvider()) { entry in
            DomainComplicationView(
                count: entry.payload?.snapshot.plantsNeedingWater ?? 0,
                icon: "drop.fill",
                label: Text("watch_water"),
                urgent: false,
                detail: entry.payload?.snapshot.plantNames.first,
                url: URL(string: "prvio://plants")
            )
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("PRVIO · Water")
        .description(NSLocalizedString("watch_comp_water_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct PRVIOShoppingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchShopping", provider: WatchPayloadProvider()) { entry in
            DomainComplicationView(
                count: entry.payload?.snapshot.pendingSupplyCount ?? 0,
                icon: "cart.fill",
                label: Text("watch_shopping"),
                urgent: false,
                detail: nil,
                url: URL(string: "prvio://shopping")
            )
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("PRVIO · Shopping")
        .description(NSLocalizedString("watch_comp_shopping_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct PRVIODeliveriesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchDeliveries", provider: WatchPayloadProvider()) { entry in
            DomainComplicationView(
                count: entry.payload?.snapshot.activeDeliveryCount ?? 0,
                icon: "shippingbox.fill",
                label: Text("watch_deliveries"),
                urgent: false,
                detail: nil,
                url: URL(string: "prvio://deliveries")
            )
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("PRVIO · Deliveries")
        .description(NSLocalizedString("watch_comp_deliveries_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Domain complication faces

private struct DomainComplicationView: View {
    let count: Int
    let icon: String
    let label: Text
    let urgent: Bool
    let detail: String?
    let url: URL?

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text(verbatim: "\(count)")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(urgent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                }
            case .accessoryCorner:
                Text(verbatim: "\(count)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(urgent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .widgetCurvesContent()
                    .widgetLabel { label }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                        label
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(verbatim: "\(count)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(urgent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                HStack(spacing: 3) {
                    Image(systemName: icon)
                    Text(verbatim: "\(count)")
                    label
                }
            }
        }
        .widgetURL(url)
    }
}

// MARK: - Provider

struct WatchPayloadEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload?
}

struct WatchPayloadProvider: TimelineProvider {
    private func load() -> WatchPayload? {
        guard let data = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .data(forKey: "prvio.watch.payload") else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    func placeholder(in context: Context) -> WatchPayloadEntry {
        WatchPayloadEntry(date: .now, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPayloadEntry) -> Void) {
        completion(WatchPayloadEntry(date: .now, payload: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPayloadEntry>) -> Void) {
        // The watch app reloads timelines whenever a fresh payload lands, so
        // a slow hourly cadence is only the fallback heartbeat.
        let entry = WatchPayloadEntry(date: .now, payload: load())
        completion(Timeline(entries: [entry],
                            policy: .after(.now.addingTimeInterval(3600))))
    }
}

// MARK: - Faces

private struct ComplicationView: View {
    let payload: WatchPayload?
    @Environment(\.widgetFamily) private var family

    private var open: Int { payload?.snapshot.openTaskCount ?? 0 }
    private var overdue: Int { payload?.snapshot.overdueTaskCount ?? 0 }
    private var water: Int { payload?.snapshot.plantsNeedingWater ?? 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            inline
        }
    }

    // Ring of open tasks with the house at the center.
    private var circular: some View {
        Gauge(value: Double(min(open, 20)), in: 0...20) {
            Image(systemName: "house.fill")
        } currentValueLabel: {
            Text(verbatim: "\(open)")
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(URL(string: "prvio://"))
    }

    private var corner: some View {
        Text(verbatim: "\(open)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .widgetCurvesContent()
            .widgetLabel {
                Text("watch_tasks")
            }
            .widgetURL(URL(string: "prvio://tasks"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(payload?.snapshot.propertyName ?? "PRVIO")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                statPair(icon: "checklist", value: open, urgent: overdue > 0)
                statPair(icon: "drop.fill", value: water, urgent: false)
                statPair(icon: "shippingbox.fill",
                         value: payload?.snapshot.activeDeliveryCount ?? 0, urgent: false)
            }
            if let critical = payload?.snapshot.criticalTaskTitle {
                Text(critical)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "prvio://"))
    }

    private var inline: some View {
        // Inline gets one line on the face: lead with what needs doing.
        Text(verbatim: "PRVIO · \(open)✓ \(water)💧")
            .widgetURL(URL(string: "prvio://tasks"))
    }

    private func statPair(icon: String, value: Int, urgent: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(urgent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Text(verbatim: "\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
    }
}

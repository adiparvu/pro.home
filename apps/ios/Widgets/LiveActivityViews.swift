import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Preference gates
//
// LiveActivityPrefs reads the app-group suite, so the user's choices in
// Settings › Live Activities › Appearance drive the REAL activity rendering,
// not just the in-app preview. Live Activity views are re-evaluated on every
// content update, so a settings change applies from the next update (and
// immediately for newly started activities).
private enum LA {
    static var lockDetails: Bool { LiveActivityPrefs.showOnLockScreen }
    static var island: Bool { LiveActivityPrefs.showDynamicIsland }
    static var progress: Bool { LiveActivityPrefs.showProgress }
    static var eta: Bool { LiveActivityPrefs.showETA }
    static var property: Bool { LiveActivityPrefs.showProperty }
    static var expandedDetail: Bool { island && LiveActivityPrefs.islandStyle == .detailed }
    static var expandedData: Bool { island && LiveActivityPrefs.islandStyle != .minimal }
}

// MARK: - Shared minimal lock-screen row (Lock Screen toggle off)

private struct MinimalLockRow: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Shopping Live Activity Widget

struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            if LA.lockDetails {
                ShoppingLockScreenView(context: context)
            } else {
                MinimalLockRow(icon: "cart.fill", tint: .blue, title: context.attributes.listName)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if LA.expandedData {
                        Label(context.attributes.listName, systemImage: "cart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "cart.fill").foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData {
                        Text("\(context.state.itemsBought)/\(context.state.totalItems)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail {
                        VStack(spacing: 6) {
                            if LA.progress {
                                ProgressView(value: context.state.totalItems > 0
                                             ? Double(context.state.itemsBought) / Double(context.state.totalItems)
                                             : 0)
                                .tint(.blue)
                            }
                            HStack {
                                Text(String(format: String(localized: "%d of %d items"), context.state.itemsBought, context.state.totalItems))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if context.state.itemsBought == context.state.totalItems {
                                    Text("Complete! 🎉")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12, weight: .semibold))
            } compactTrailing: {
                if LA.island {
                    Text("\(context.state.itemsBought)/\(context.state.totalItems)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            } minimal: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct ShoppingLockScreenView: View {
    let context: ActivityViewContext<ShoppingActivityAttributes>

    var progress: Double {
        context.state.totalItems > 0
            ? Double(context.state.itemsBought) / Double(context.state.totalItems)
            : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "cart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.listName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                if LA.progress {
                    ProgressView(value: progress).tint(.blue)
                }
                HStack(spacing: 4) {
                    Text(String(format: String(localized: "%d of %d items"), context.state.itemsBought, context.state.totalItems))
                    if LA.property, !context.attributes.propertyName.isEmpty {
                        Text("· \(context.attributes.propertyName)")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(progress * 100))%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
        }
        .padding(16)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Maintenance Live Activity Widget

struct MaintenanceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MaintenanceActivityAttributes.self) { context in
            if LA.lockDetails {
                MaintenanceLockScreenView(context: context)
            } else {
                MinimalLockRow(icon: context.state.isComplete ? "checkmark.circle.fill" : "wrench.fill",
                               tint: context.state.isComplete ? .green : .orange,
                               title: context.attributes.taskTitle)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if LA.expandedData {
                        Label(context.attributes.taskTitle, systemImage: "wrench.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "wrench.fill").foregroundStyle(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(context.state.isComplete ? .green : .orange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail {
                        VStack(spacing: 4) {
                            if LA.progress {
                                ProgressView(value: context.state.progress).tint(.orange)
                            }
                            Text(context.state.stepDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "wrench.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            } compactTrailing: {
                if LA.island {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            } minimal: {
                Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "wrench.fill")
                    .foregroundStyle(context.state.isComplete ? .green : .orange)
            }
        }
    }
}

struct MaintenanceLockScreenView: View {
    let context: ActivityViewContext<MaintenanceActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "wrench.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(context.state.isComplete ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.taskTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if LA.progress {
                    ProgressView(value: context.state.progress).tint(.orange)
                }
                HStack(spacing: 4) {
                    Text(context.state.stepDescription)
                    if LA.property, let property = context.attributes.propertyName, !property.isEmpty {
                        Text("· \(property)")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Delivery Live Activity Widget

struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryActivityAttributes.self) { context in
            if LA.lockDetails {
                DeliveryLockScreenView(context: context)
            } else {
                MinimalLockRow(icon: "shippingbox.fill", tint: .blue, title: context.attributes.description)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if LA.expandedData {
                        Label(context.attributes.carrier, systemImage: "shippingbox.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "shippingbox.fill").foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData {
                        Text(context.state.statusLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(deliveryColor(context.state.status))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail {
                        HStack {
                            Text(context.attributes.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if LA.eta, let eta = context.state.eta {
                                Text("ETA: \(eta)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
            } compactTrailing: {
                if LA.island {
                    Text(context.state.statusLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(deliveryColor(context.state.status))
                }
            } minimal: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    private func deliveryColor(_ status: String) -> Color {
        switch status {
        case "out_for_delivery": return .orange
        case "delivered":        return .green
        default:                 return .blue
        }
    }
}

struct DeliveryLockScreenView: View {
    let context: ActivityViewContext<DeliveryActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if LA.property, let property = context.attributes.propertyName, !property.isEmpty {
                    Text("\(property) · \(context.attributes.carrier) · \(context.state.statusLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(context.attributes.carrier) · \(context.state.statusLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if LA.eta, let eta = context.state.eta {
                    Text(String(format: String(localized: "Estimated: %@"), eta))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Plant Care Live Activity Widget

struct PlantCareLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlantCareActivityAttributes.self) { context in
            if LA.lockDetails {
                PlantCareLockScreenView(context: context)
            } else {
                MinimalLockRow(icon: "drop.fill", tint: .blue, title: String(localized: "Plant watering"))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if LA.expandedData {
                        Label("Plant watering", systemImage: "drop.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "drop.fill").foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData {
                        Text("\(context.state.wateredCount)/\(context.state.totalCount)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail {
                        VStack(spacing: 4) {
                            if LA.progress {
                                ProgressView(value: context.state.totalCount > 0
                                             ? Double(context.state.wateredCount) / Double(context.state.totalCount)
                                             : 0)
                                .tint(.blue)
                            }
                            if let name = context.state.lastWateredName {
                                Text(String(format: String(localized: "Last watered: %@"), name))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
            } compactTrailing: {
                if LA.island {
                    Text("\(context.state.wateredCount)/\(context.state.totalCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            } minimal: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct PlantCareLockScreenView: View {
    let context: ActivityViewContext<PlantCareActivityAttributes>

    var progress: Double {
        context.state.totalCount > 0
            ? Double(context.state.wateredCount) / Double(context.state.totalCount)
            : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "drop.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Plant watering")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                if LA.progress {
                    ProgressView(value: progress).tint(.blue)
                }
                HStack(spacing: 4) {
                    Text(String(format: String(localized: "%d of %d plants watered"), context.state.wateredCount, context.state.totalCount))
                    if LA.property, !context.attributes.propertyName.isEmpty {
                        Text("· \(context.attributes.propertyName)")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(progress * 100))%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
        }
        .padding(16)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

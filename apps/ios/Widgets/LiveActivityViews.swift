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
// Each helper takes the activity kind so per-activity overrides apply; a nil /
// unknown kind falls back to the global appearance.
private enum LA {
    static func lockDetails(_ k: String) -> Bool { LiveActivityPrefs.showOnLockScreen(for: k) }
    static func island(_ k: String) -> Bool { LiveActivityPrefs.showDynamicIsland(for: k) }
    static func progress(_ k: String) -> Bool { LiveActivityPrefs.showProgress(for: k) }
    static func eta(_ k: String) -> Bool { LiveActivityPrefs.showETA(for: k) }
    static func property(_ k: String) -> Bool { LiveActivityPrefs.showProperty(for: k) }
    static func expandedDetail(_ k: String) -> Bool { island(k) && LiveActivityPrefs.islandStyle(for: k) == .detailed }
    static func expandedData(_ k: String) -> Bool { island(k) && LiveActivityPrefs.islandStyle(for: k) != .minimal }
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
            Group {
                if LA.lockDetails("shopping") {
                    ShoppingLockScreenView(context: context)
                } else {
                    MinimalLockRow(icon: "cart.fill", tint: .blue, title: context.attributes.listName)
                }
            }
            .widgetURL(URL(string: "prvio://shopping"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if LA.expandedData("shopping") {
                            Label(context.attributes.listName, systemImage: "cart.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "cart.fill").foregroundStyle(.blue)
                        }
                    }
                    .widgetURL(URL(string: "prvio://shopping"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData("shopping") {
                        Text("\(context.state.itemsBought)/\(context.state.totalItems)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail("shopping") {
                        VStack(spacing: 6) {
                            if LA.progress("shopping") {
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
                if LA.island("shopping") {
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
                if LA.progress("shopping") {
                    ProgressView(value: progress).tint(.blue)
                }
                HStack(spacing: 4) {
                    Text(String(format: String(localized: "%d of %d items"), context.state.itemsBought, context.state.totalItems))
                    if LA.property("shopping"), !context.attributes.propertyName.isEmpty {
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
            Group {
                if LA.lockDetails("maintenance") {
                    MaintenanceLockScreenView(context: context)
                } else {
                    MinimalLockRow(icon: context.state.isComplete ? "checkmark.circle.fill" : "wrench.fill",
                                   tint: context.state.isComplete ? .green : .orange,
                                   title: context.attributes.taskTitle)
                }
            }
            .widgetURL(URL(string: "prvio://tasks"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if LA.expandedData("maintenance") {
                            Label(context.attributes.taskTitle, systemImage: "wrench.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "wrench.fill").foregroundStyle(.orange)
                        }
                    }
                    .widgetURL(URL(string: "prvio://tasks"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData("maintenance") {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(context.state.isComplete ? .green : .orange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail("maintenance") {
                        VStack(spacing: 4) {
                            if LA.progress("maintenance") {
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
                if LA.island("maintenance") {
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
                if LA.progress("maintenance") {
                    ProgressView(value: context.state.progress).tint(.orange)
                }
                HStack(spacing: 4) {
                    Text(context.state.stepDescription)
                    if LA.property("maintenance"), let property = context.attributes.propertyName, !property.isEmpty {
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

// MARK: - Work Session Live Activity Widget
//
// The system counts the elapsed time from the fixed start date (no content
// updates while it runs), and the Lock Screen buttons run as
// LiveActivityIntents in the app's process — completing really completes.

struct WorkSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkSessionActivityAttributes.self) { context in
            Group {
                if LA.lockDetails("workSession") {
                    WorkSessionLockScreenView(context: context)
                } else {
                    MinimalLockRow(icon: context.state.isComplete ? "checkmark.circle.fill" : "timer",
                                   tint: context.state.isComplete ? .green : .teal,
                                   title: context.attributes.taskTitle)
                }
            }
            .widgetURL(URL(string: "prvio://tasks"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if LA.expandedData("workSession") {
                            Label(context.attributes.taskTitle, systemImage: "timer")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.teal)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "timer").foregroundStyle(.teal)
                        }
                    }
                    .widgetURL(URL(string: "prvio://tasks"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData("workSession") {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.teal)
                            .frame(maxWidth: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail("workSession") {
                        HStack(spacing: 10) {
                            Button(intent: CompleteWorkSessionIntent(taskId: context.attributes.taskId)) {
                                Label("la_session_complete", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            Button(intent: EndWorkSessionIntent()) {
                                Text("la_session_end")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.teal)
                    .font(.system(size: 12))
            } compactTrailing: {
                if LA.island("workSession") {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.teal)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(context.state.isComplete ? .green : .teal)
            }
        }
    }
}

struct WorkSessionLockScreenView: View {
    let context: ActivityViewContext<WorkSessionActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(context.state.isComplete ? .green : .teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if LA.property("workSession"),
                       let property = context.attributes.propertyName, !property.isEmpty {
                        Text(property)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(context.state.isComplete ? .green : .teal)
                    .frame(maxWidth: 90)
                    .multilineTextAlignment(.trailing)
            }
            if !context.state.isComplete {
                HStack(spacing: 10) {
                    Button(intent: CompleteWorkSessionIntent(taskId: context.attributes.taskId)) {
                        Label("la_session_complete", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    Button(intent: EndWorkSessionIntent()) {
                        Text("la_session_end")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
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
            Group {
                if LA.lockDetails("delivery") {
                    DeliveryLockScreenView(context: context)
                } else {
                    MinimalLockRow(icon: "shippingbox.fill", tint: .blue, title: context.attributes.description)
                }
            }
            .widgetURL(URL(string: "prvio://deliveries"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if LA.expandedData("delivery") {
                            Label(context.attributes.carrier, systemImage: "shippingbox.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "shippingbox.fill").foregroundStyle(.blue)
                        }
                    }
                    .widgetURL(URL(string: "prvio://deliveries"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData("delivery") {
                        Text(context.state.statusLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(deliveryColor(context.state.status))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail("delivery") {
                        HStack {
                            Text(context.attributes.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if LA.eta("delivery"), let eta = context.state.eta {
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
                if LA.island("delivery") {
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
                if LA.property("delivery"), let property = context.attributes.propertyName, !property.isEmpty {
                    Text("\(property) · \(context.attributes.carrier) · \(context.state.statusLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(context.attributes.carrier) · \(context.state.statusLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if LA.eta("delivery"), let eta = context.state.eta {
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
            Group {
                if LA.lockDetails("plantCare") {
                    PlantCareLockScreenView(context: context)
                } else {
                    MinimalLockRow(icon: "drop.fill", tint: .blue, title: String(localized: "Plant watering"))
                }
            }
            .widgetURL(URL(string: "prvio://plants"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if LA.expandedData("plantCare") {
                            Label("Plant watering", systemImage: "drop.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "drop.fill").foregroundStyle(.blue)
                        }
                    }
                    .widgetURL(URL(string: "prvio://plants"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData("plantCare") {
                        Text("\(context.state.wateredCount)/\(context.state.totalCount)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail("plantCare") {
                        VStack(spacing: 4) {
                            if LA.progress("plantCare") {
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
                if LA.island("plantCare") {
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
                if LA.progress("plantCare") {
                    ProgressView(value: progress).tint(.blue)
                }
                HStack(spacing: 4) {
                    Text(String(format: String(localized: "%d of %d plants watered"), context.state.wateredCount, context.state.totalCount))
                    if LA.property("plantCare"), !context.attributes.propertyName.isEmpty {
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

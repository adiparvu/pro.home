import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - PRVIO Live Activities
//
// Every activity composes IslandKit (IslandKit.swift): one icon language, one
// metric style, one lock card — themed by the canonical LiveActivityKind.
// Appearance preferences are applied through the LA gates at render time; the
// system re-renders on each content update.

// MARK: - Shopping

struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        // watchOS 11+ mirrors iPhone Live Activities into the Smart Stack by
        // default, using the compact presentations. A custom small layout
        // (supplementalActivityFamilies) is iOS 18-only and Widget.body can't
        // branch on availability - it lands when the deployment target does.
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            ShoppingLockView(context: context)
                .widgetURL(LiveActivityKind.shopping.deepLink)
        } dynamicIsland: { context in
            let bought = context.state.itemsBought
            let total = context.state.totalItems
            let done = total > 0 && bought >= total
            let progress = total > 0 ? Double(bought) / Double(total) : 0
            let countText = Text(verbatim: "\(bought)/\(total)")
            let countLabel = Text(String(format: String(localized: "%d of %d items"), bought, total))

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .shopping, title: Text(context.attributes.listName), isComplete: done)
                        .widgetURL(LiveActivityKind.shopping.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.shopping) {
                        IslandMetric(countText, size: .expanded)
                            .accessibilityLabel(countLabel)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.shopping) {
                        VStack(spacing: AppSpacing.xs) {
                            if LA.progress(.shopping) {
                                IslandProgressBar(value: progress, tint: LiveActivityKind.shopping.color)
                            }
                            HStack {
                                countLabel
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if done {
                                    Text("Complete! 🎉")
                                        .font(AppFont.captionStrong)
                                        .foregroundStyle(Color.brandSuccess)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .shopping, isComplete: done)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.shopping.title))
            } compactTrailing: {
                if LA.island(.shopping) {
                    IslandMetric(countText)
                        .accessibilityLabel(countLabel)
                }
            } minimal: {
                IslandStateIcon(kind: .shopping, isComplete: done)
                    .accessibilityLabel(Text(LiveActivityKind.shopping.title))
            }
        }
    }
}

private struct ShoppingLockView: View {
    let context: ActivityViewContext<ShoppingActivityAttributes>

    private var progress: Double {
        context.state.totalItems > 0
            ? Double(context.state.itemsBought) / Double(context.state.totalItems)
            : 0
    }
    private var isComplete: Bool {
        context.state.totalItems > 0 && context.state.itemsBought >= context.state.totalItems
    }

    var body: some View {
        if LA.lockDetails(.shopping) {
            IslandLockCard(kind: .shopping,
                           title: Text(context.attributes.listName),
                           isComplete: isComplete) {
                if LA.progress(.shopping) {
                    IslandProgressBar(value: progress, tint: LiveActivityKind.shopping.color)
                }
                IslandContextLine(kind: .shopping,
                                  text: Text(String(format: String(localized: "%d of %d items"),
                                                    context.state.itemsBought, context.state.totalItems)),
                                  propertyName: context.attributes.propertyName)
            } trailing: {
                IslandMetric(Text(verbatim: "\(Int(progress * 100))%"),
                             tint: isComplete ? .brandSuccess : LiveActivityKind.shopping.color,
                             size: .hero)
            }
        } else {
            MinimalLockRow(kind: .shopping, title: Text(context.attributes.listName), isComplete: isComplete)
        }
    }
}

// MARK: - Maintenance

struct MaintenanceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: MaintenanceActivityAttributes.self) { context in
            MaintenanceLockView(context: context)
                .widgetURL(LiveActivityKind.maintenance.deepLink)
        } dynamicIsland: { context in
            let done = context.state.isComplete
            let percentText = Text(verbatim: "\(Int(context.state.progress * 100))%")

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .maintenance, title: Text(context.attributes.taskTitle), isComplete: done)
                        .widgetURL(LiveActivityKind.maintenance.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.maintenance) {
                        IslandMetric(percentText,
                                     tint: done ? .brandSuccess : LiveActivityKind.maintenance.color,
                                     size: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.maintenance) {
                        VStack(spacing: AppSpacing.xxs) {
                            if LA.progress(.maintenance) {
                                IslandProgressBar(value: context.state.progress,
                                                  tint: LiveActivityKind.maintenance.color)
                            }
                            Text(context.state.stepDescription)
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .maintenance, isComplete: done)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.maintenance.title))
            } compactTrailing: {
                if LA.island(.maintenance) {
                    IslandMetric(percentText)
                        .accessibilityLabel(Text(context.state.stepDescription))
                }
            } minimal: {
                IslandStateIcon(kind: .maintenance, isComplete: done)
                    .accessibilityLabel(Text(LiveActivityKind.maintenance.title))
            }
        }
    }
}

private struct MaintenanceLockView: View {
    let context: ActivityViewContext<MaintenanceActivityAttributes>

    var body: some View {
        if LA.lockDetails(.maintenance) {
            IslandLockCard(kind: .maintenance,
                           title: Text(context.attributes.taskTitle),
                           isComplete: context.state.isComplete) {
                if LA.progress(.maintenance) {
                    IslandProgressBar(value: context.state.progress,
                                      tint: LiveActivityKind.maintenance.color)
                }
                IslandContextLine(kind: .maintenance,
                                  text: Text(context.state.stepDescription),
                                  propertyName: context.attributes.propertyName)
            } trailing: {
                IslandMetric(Text(verbatim: "\(Int(context.state.progress * 100))%"),
                             tint: context.state.isComplete ? .brandSuccess : LiveActivityKind.maintenance.color,
                             size: .hero)
            }
        } else {
            MinimalLockRow(kind: .maintenance,
                           title: Text(context.attributes.taskTitle),
                           isComplete: context.state.isComplete)
        }
    }
}

// MARK: - Work session
//
// The system counts the elapsed time from the fixed start date (no content
// updates while it runs), and the buttons run as LiveActivityIntents in the
// app's process — completing really completes.

struct WorkSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: WorkSessionActivityAttributes.self) { context in
            WorkSessionLockView(context: context)
                .widgetURL(LiveActivityKind.workSession.deepLink)
        } dynamicIsland: { context in
            let done = context.state.isComplete
            let timer = Text(context.attributes.startedAt, style: .timer)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .workSession, title: Text(context.attributes.taskTitle), isComplete: done)
                        .widgetURL(LiveActivityKind.workSession.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.workSession) {
                        IslandMetric(timer,
                                     tint: done ? .brandSuccess : LiveActivityKind.workSession.color,
                                     size: .expanded)
                            .frame(maxWidth: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.workSession), !done {
                        HStack(spacing: AppSpacing.sm + 2) {
                            Button(intent: CompleteWorkSessionIntent(taskId: context.attributes.taskId)) {
                                Label("la_session_complete", systemImage: "checkmark.circle.fill")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LiveActivityKind.workSession.color)
                            Button(intent: EndWorkSessionIntent()) {
                                Text("la_session_end")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .workSession, isComplete: done)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.workSession.title))
            } compactTrailing: {
                if LA.island(.workSession) {
                    IslandMetric(timer, tint: done ? .brandSuccess : LiveActivityKind.workSession.color)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                IslandStateIcon(kind: .workSession, isComplete: done)
                    .accessibilityLabel(Text(LiveActivityKind.workSession.title))
            }
        }
    }
}

private struct WorkSessionLockView: View {
    let context: ActivityViewContext<WorkSessionActivityAttributes>

    var body: some View {
        if LA.lockDetails(.workSession) {
            VStack(spacing: AppSpacing.sm + 2) {
                HStack(spacing: AppSpacing.base) {
                    IslandIconDisc(kind: .workSession, isComplete: context.state.isComplete)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.taskTitle)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if LA.property(.workSession),
                           let property = context.attributes.propertyName, !property.isEmpty {
                            Text(property)
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    IslandMetric(Text(context.attributes.startedAt, style: .timer),
                                 tint: context.state.isComplete ? .brandSuccess : LiveActivityKind.workSession.color,
                                 size: .hero)
                        .frame(maxWidth: 90)
                        .multilineTextAlignment(.trailing)
                }
                if !context.state.isComplete {
                    HStack(spacing: AppSpacing.sm + 2) {
                        Button(intent: CompleteWorkSessionIntent(taskId: context.attributes.taskId)) {
                            Label("la_session_complete", systemImage: "checkmark.circle.fill")
                                .font(AppFont.captionEmphasis)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LiveActivityKind.workSession.color)
                        Button(intent: EndWorkSessionIntent()) {
                            Text("la_session_end")
                                .font(AppFont.captionEmphasis)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .workSession,
                           title: Text(context.attributes.taskTitle),
                           isComplete: context.state.isComplete)
        }
    }
}

// MARK: - Delivery
//
// A milestone journey (ordered → in transit → out for delivery → delivered).
// The content state can arrive from the app OR from a server push whose
// sender doesn't know the device language, so the status label is resolved
// on-device from the status key, falling back to the pushed label.

private enum DeliveryFace {
    /// On-device label for both the legacy and the live-tracking status
    /// vocabularies; `fallback` covers unknown/future statuses.
    static func label(_ status: String, fallback: String) -> String {
        switch status {
        case "expected", "pending", "info_received": return String(localized: "Expected")
        case "in_transit":                           return String(localized: "In transit")
        case "out_for_delivery":                     return String(localized: "Out for delivery")
        case "available_for_pickup":                 return String(localized: "Ready for pickup")
        case "delivered":                            return String(localized: "Delivered")
        case "missed":                               return String(localized: "Missed")
        case "returned":                             return String(localized: "Returned")
        case "exception", "expired":                 return String(localized: "Delivery issue")
        case "failed_attempt":                       return String(localized: "Failed attempt")
        default:                                     return fallback
        }
    }

    static func milestone(_ state: DeliveryActivityAttributes.ContentState) -> Int {
        if let index = state.milestoneIndex { return max(0, min(3, index)) }
        switch state.status { // payloads from before the milestone field
        case "out_for_delivery", "available_for_pickup": return 2
        case "delivered":                                 return 3
        case "in_transit":                                return 1
        default:                                          return 0
        }
    }

    static func tint(_ state: DeliveryActivityAttributes.ContentState) -> Color {
        if state.isProblem == true { return .brandWarning }
        switch state.status {
        case "out_for_delivery", "available_for_pickup": return .brandWarning
        case "delivered":                                 return .brandSuccess
        default:                                          return LiveActivityKind.delivery.color
        }
    }
}

struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryActivityAttributes.self) { context in
            DeliveryLockView(context: context)
                .widgetURL(LiveActivityKind.delivery.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            let delivered = state.status == "delivered"
            let problem = state.isProblem == true
            let tint = DeliveryFace.tint(state)
            let label = DeliveryFace.label(state.status, fallback: state.statusLabel)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .delivery, title: Text(context.attributes.carrier), isComplete: delivered)
                        .widgetURL(LiveActivityKind.delivery.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.delivery) {
                        Text(label)
                            .font(AppFont.captionStrong)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.delivery) {
                        VStack(spacing: AppSpacing.xs) {
                            if LA.progress(.delivery) {
                                IslandMilestoneBar(stage: DeliveryFace.milestone(state),
                                                   tint: delivered ? .brandSuccess : LiveActivityKind.delivery.color,
                                                   isProblem: problem)
                            }
                            HStack {
                                Text(state.checkpoint ?? context.attributes.description)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if LA.eta(.delivery), let eta = state.eta {
                                    Text("ETA: \(eta)")
                                        .font(AppFont.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .delivery, isComplete: delivered, isProblem: problem)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.delivery.title))
            } compactTrailing: {
                if LA.island(.delivery) {
                    Text(label)
                        .font(AppFont.label)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            } minimal: {
                IslandStateIcon(kind: .delivery, isComplete: delivered, isProblem: problem)
                    .accessibilityLabel(Text(verbatim: label))
            }
        }
    }
}

private struct DeliveryLockView: View {
    let context: ActivityViewContext<DeliveryActivityAttributes>

    var body: some View {
        let state = context.state
        let delivered = state.status == "delivered"
        let label = DeliveryFace.label(state.status, fallback: state.statusLabel)

        if LA.lockDetails(.delivery) {
            IslandLockCard(kind: .delivery,
                           title: Text(context.attributes.description),
                           isComplete: delivered) {
                if LA.progress(.delivery) {
                    IslandMilestoneBar(stage: DeliveryFace.milestone(state),
                                       tint: delivered ? .brandSuccess : LiveActivityKind.delivery.color,
                                       isProblem: state.isProblem == true)
                }
                IslandContextLine(kind: .delivery,
                                  text: Text(verbatim: "\(context.attributes.carrier) · \(label)"),
                                  propertyName: context.attributes.propertyName)
                if let checkpoint = state.checkpoint {
                    Text(checkpoint)
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if LA.eta(.delivery), let eta = state.eta {
                    Text(String(format: String(localized: "Estimated: %@"), eta))
                        .font(AppFont.caption2)
                        .foregroundStyle(DeliveryFace.tint(state))
                }
            } trailing: {
                EmptyView()
            }
        } else {
            MinimalLockRow(kind: .delivery,
                           title: Text(context.attributes.description),
                           isComplete: delivered)
        }
    }
}

// MARK: - Plant care

struct PlantCareLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: PlantCareActivityAttributes.self) { context in
            PlantCareLockView(context: context)
                .widgetURL(LiveActivityKind.plantCare.deepLink)
        } dynamicIsland: { context in
            let watered = context.state.wateredCount
            let total = context.state.totalCount
            let done = total > 0 && watered >= total
            let progress = total > 0 ? Double(watered) / Double(total) : 0
            let countText = Text(verbatim: "\(watered)/\(total)")
            let countLabel = Text(String(format: String(localized: "%d of %d plants watered"), watered, total))

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .plantCare, title: Text("Plant watering"), isComplete: done)
                        .widgetURL(LiveActivityKind.plantCare.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.plantCare) {
                        IslandMetric(countText,
                                     tint: done ? .brandSuccess : LiveActivityKind.plantCare.color,
                                     size: .expanded)
                            .accessibilityLabel(countLabel)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.plantCare) {
                        VStack(spacing: AppSpacing.xxs) {
                            if LA.progress(.plantCare) {
                                IslandProgressBar(value: progress, tint: LiveActivityKind.plantCare.color)
                            }
                            if let name = context.state.lastWateredName {
                                Text(String(format: String(localized: "Last watered: %@"), name))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .plantCare, isComplete: done)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.plantCare.title))
            } compactTrailing: {
                if LA.island(.plantCare) {
                    IslandMetric(countText)
                        .accessibilityLabel(countLabel)
                }
            } minimal: {
                IslandStateIcon(kind: .plantCare, isComplete: done)
                    .accessibilityLabel(Text(LiveActivityKind.plantCare.title))
            }
        }
    }
}

private struct PlantCareLockView: View {
    let context: ActivityViewContext<PlantCareActivityAttributes>

    private var progress: Double {
        context.state.totalCount > 0
            ? Double(context.state.wateredCount) / Double(context.state.totalCount)
            : 0
    }
    private var isComplete: Bool {
        context.state.totalCount > 0 && context.state.wateredCount >= context.state.totalCount
    }

    var body: some View {
        if LA.lockDetails(.plantCare) {
            IslandLockCard(kind: .plantCare,
                           title: Text("Plant watering"),
                           isComplete: isComplete) {
                if LA.progress(.plantCare) {
                    IslandProgressBar(value: progress, tint: LiveActivityKind.plantCare.color)
                }
                IslandContextLine(kind: .plantCare,
                                  text: Text(String(format: String(localized: "%d of %d plants watered"),
                                                    context.state.wateredCount, context.state.totalCount)),
                                  propertyName: context.attributes.propertyName)
            } trailing: {
                IslandMetric(Text(verbatim: "\(Int(progress * 100))%"),
                             tint: isComplete ? .brandSuccess : LiveActivityKind.plantCare.color,
                             size: .hero)
            }
        } else {
            MinimalLockRow(kind: .plantCare, title: Text("Plant watering"), isComplete: isComplete)
        }
    }
}

// MARK: - Emergency incident
//
// User-pinned from the Emergency page during a real incident: the beacon
// pulses in the island, the elapsed time is system-counted from the fixed
// start date, and the only actions are the honest ones — open the page,
// or declare the incident over. The only activity allowed to wear red.

struct EmergencyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: EmergencyActivityAttributes.self) { context in
            EmergencyLockView(context: context)
                .widgetURL(LiveActivityKind.emergency.deepLink)
        } dynamicIsland: { context in
            let timer = Text(context.attributes.startedAt, style: .timer)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .emergency, title: Text("la_emergency_active"))
                        .widgetURL(LiveActivityKind.emergency.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.emergency) {
                        IslandMetric(timer, tint: LiveActivityKind.emergency.color, size: .expanded)
                            .frame(maxWidth: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.emergency) {
                        HStack(spacing: AppSpacing.sm + 2) {
                            if LA.property(.emergency),
                               let property = context.attributes.propertyName, !property.isEmpty {
                                Text(property)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(intent: EndEmergencyIntent()) {
                                Text("la_emergency_end")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.bordered)
                            .tint(LiveActivityKind.emergency.color)
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .emergency, pulses: true)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.emergency.title))
            } compactTrailing: {
                if LA.island(.emergency) {
                    IslandMetric(timer, tint: LiveActivityKind.emergency.color)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                IslandStateIcon(kind: .emergency, pulses: true)
                    .accessibilityLabel(Text(LiveActivityKind.emergency.title))
            }
        }
    }
}

private struct EmergencyLockView: View {
    let context: ActivityViewContext<EmergencyActivityAttributes>

    var body: some View {
        if LA.lockDetails(.emergency) {
            VStack(spacing: AppSpacing.sm + 2) {
                HStack(spacing: AppSpacing.base) {
                    IslandIconDisc(kind: .emergency)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("la_emergency_active")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        if LA.property(.emergency),
                           let property = context.attributes.propertyName, !property.isEmpty {
                            Text(property)
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    IslandMetric(Text(context.attributes.startedAt, style: .timer),
                                 tint: LiveActivityKind.emergency.color, size: .hero)
                        .frame(maxWidth: 90)
                        .multilineTextAlignment(.trailing)
                }
                Button(intent: EndEmergencyIntent()) {
                    Text("la_emergency_end")
                        .font(AppFont.captionEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(LiveActivityKind.emergency.color)
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .emergency, title: Text("la_emergency_active"))
        }
    }
}

// MARK: - IoT sensor alert
//
// Raised by the user's own sensors (threshold crossings, smoke). Critical
// hazards (smoke / gas / water) wear danger red; everything else warning
// orange. "Got it" silences this instance until the sensor clears.

private struct AlertSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let tint: Color
    var pulses = true

    var body: some View {
        Image(systemName: name)
            .foregroundStyle(tint)
            .symbolEffect(.pulse, options: .repeating, isActive: pulses && !reduceMotion)
    }
}

struct IoTAlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: IoTAlertActivityAttributes.self) { context in
            IoTAlertLockView(context: context)
                .widgetURL(LiveActivityKind.iotAlert.deepLink)
        } dynamicIsland: { context in
            let active = context.state.isActive
            let tint: Color = active
                ? (context.attributes.isCritical ? .brandDanger : .brandWarning)
                : .brandSuccess

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: AppSpacing.xs) {
                        AlertSymbol(name: context.attributes.icon, tint: tint, pulses: active)
                            .font(AppFont.captionStrong)
                        if LA.expandedData(.iotAlert) {
                            Text(context.attributes.sensorName)
                                .font(AppFont.captionStrong)
                                .foregroundStyle(tint)
                                .lineLimit(1)
                        }
                    }
                    .widgetURL(LiveActivityKind.iotAlert.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.iotAlert) {
                        IslandMetric(Text(verbatim: context.state.valueDisplay),
                                     tint: tint, size: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.iotAlert) {
                        HStack(spacing: AppSpacing.sm + 2) {
                            if let zone = context.attributes.zone {
                                Text(zone)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if active {
                                Button(intent: AcknowledgeIoTAlertIntent(sensorId: context.attributes.sensorId)) {
                                    Text("la_alert_ack")
                                        .font(AppFont.captionStrong)
                                }
                                .buttonStyle(.bordered)
                                .tint(tint)
                            }
                        }
                    }
                }
            } compactLeading: {
                AlertSymbol(name: context.attributes.icon, tint: tint, pulses: active)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(context.attributes.sensorName))
            } compactTrailing: {
                if LA.island(.iotAlert) {
                    IslandMetric(Text(verbatim: context.state.valueDisplay), tint: tint)
                        .accessibilityLabel(Text(verbatim: "\(context.attributes.sensorName) \(context.state.valueDisplay)"))
                }
            } minimal: {
                AlertSymbol(name: context.attributes.icon, tint: tint, pulses: active)
                    .accessibilityLabel(Text(context.attributes.sensorName))
            }
        }
    }
}

private struct IoTAlertLockView: View {
    let context: ActivityViewContext<IoTAlertActivityAttributes>

    private var tint: Color {
        context.state.isActive
            ? (context.attributes.isCritical ? .brandDanger : .brandWarning)
            : .brandSuccess
    }

    var body: some View {
        if LA.lockDetails(.iotAlert) {
            VStack(spacing: AppSpacing.sm + 2) {
                HStack(spacing: AppSpacing.base) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(AppOpacity.tintedFill))
                            .frame(width: IslandMetrics.iconDisc, height: IslandMetrics.iconDisc)
                        AlertSymbol(name: context.attributes.icon, tint: tint,
                                    pulses: context.state.isActive)
                            .font(AppFont.title3)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.sensorName)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        IslandContextLine(kind: .iotAlert,
                                          text: Text(context.attributes.zone ?? ""),
                                          propertyName: context.attributes.propertyName)
                    }
                    Spacer()
                    IslandMetric(Text(verbatim: context.state.valueDisplay),
                                 tint: tint, size: .hero)
                }
                if context.state.isActive {
                    Button(intent: AcknowledgeIoTAlertIntent(sensorId: context.attributes.sensorId)) {
                        Text("la_alert_ack")
                            .font(AppFont.captionEmphasis)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .iotAlert, title: Text(context.attributes.sensorName))
        }
    }
}

// MARK: - Energy session
//
// Live gauge over the user's own power sensors: consumption vs tagged
// production. Values only ever come from real polls.

private enum EnergyFace {
    static func watts(_ w: Double?) -> String? {
        guard let w else { return nil }
        return w >= 1000 ? String(format: "%.1f kW", w / 1000)
                         : String(format: "%.0f W", w)
    }
}

struct EnergyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: EnergyActivityAttributes.self) { context in
            EnergyLockView(context: context)
                .widgetURL(LiveActivityKind.energy.deepLink)
        } dynamicIsland: { context in
            let headline = EnergyFace.watts(context.state.consumptionW)
                ?? EnergyFace.watts(context.state.productionW) ?? "—"

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .energy, title: Text(LiveActivityKind.energy.title))
                        .widgetURL(LiveActivityKind.energy.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.energy) {
                        IslandMetric(Text(verbatim: headline),
                                     tint: LiveActivityKind.energy.color, size: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.energy) {
                        HStack(spacing: AppSpacing.base) {
                            if let consumption = EnergyFace.watts(context.state.consumptionW) {
                                Label {
                                    Text(verbatim: consumption).font(AppFont.captionStrong)
                                } icon: {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(LiveActivityKind.energy.color)
                                }
                                .font(AppFont.caption)
                                .accessibilityLabel(Text("la_energy_consumption"))
                            }
                            if let production = EnergyFace.watts(context.state.productionW) {
                                Label {
                                    Text(verbatim: production).font(AppFont.captionStrong)
                                } icon: {
                                    Image(systemName: "sun.max.fill")
                                        .foregroundStyle(Color.brandSuccess)
                                }
                                .font(AppFont.caption)
                                .accessibilityLabel(Text("la_energy_production"))
                            }
                            Spacer()
                            Button(intent: EndEnergySessionIntent()) {
                                Text("la_session_end")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } compactLeading: {
                IslandStateIcon(kind: .energy)
                    .font(AppFont.captionStrong)
                    .accessibilityLabel(Text(LiveActivityKind.energy.title))
            } compactTrailing: {
                if LA.island(.energy) {
                    IslandMetric(Text(verbatim: headline), tint: LiveActivityKind.energy.color)
                }
            } minimal: {
                IslandStateIcon(kind: .energy)
                    .accessibilityLabel(Text(LiveActivityKind.energy.title))
            }
        }
    }
}

private struct EnergyLockView: View {
    let context: ActivityViewContext<EnergyActivityAttributes>

    var body: some View {
        if LA.lockDetails(.energy) {
            IslandLockCard(kind: .energy, title: Text(LiveActivityKind.energy.title)) {
                HStack(spacing: AppSpacing.xxs) {
                    if let consumption = EnergyFace.watts(context.state.consumptionW) {
                        Text("la_energy_consumption") + Text(verbatim: " \(consumption)")
                    }
                    if context.state.consumptionW != nil, context.state.productionW != nil {
                        Text(verbatim: "·")
                    }
                    if let production = EnergyFace.watts(context.state.productionW) {
                        Text("la_energy_production") + Text(verbatim: " \(production)")
                    }
                }
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                IslandContextLine(kind: .energy, text: Text(verbatim: ""),
                                  propertyName: context.attributes.propertyName)
            } trailing: {
                IslandMetric(Text(verbatim: EnergyFace.watts(context.state.consumptionW)
                                  ?? EnergyFace.watts(context.state.productionW) ?? "—"),
                             tint: LiveActivityKind.energy.color, size: .hero)
            }
        } else {
            MinimalLockRow(kind: .energy, title: Text(LiveActivityKind.energy.title))
        }
    }
}

// MARK: - Cover operation (garage / gate)
//
// Follows a single user-issued command. "Open"/"Closed" appear only when a
// feedback sensor confirmed them; otherwise the terminal state is the honest
// "command finished" / "no confirmation".

private enum CoverFace {
    static func label(_ stage: String) -> LocalizedStringKey {
        switch stage {
        case "sent":    return "la_cover_sent"
        case "moving":  return "la_cover_moving"
        case "open":    return "la_cover_open"
        case "closed":  return "la_cover_closed"
        case "stopped": return "la_cover_stopped"
        case "done":    return "la_cover_done"
        case "timeout": return "la_cover_timeout"
        default:        return "la_cover_failed"
        }
    }
    static func tint(_ stage: String) -> Color {
        switch stage {
        case "failed", "timeout":                 return .brandWarning
        case "open", "closed", "done", "stopped": return .brandSuccess
        default:                                  return LiveActivityKind.cover.color
        }
    }
    static func icon(_ stage: String) -> String {
        stage == "open" ? "door.garage.open" : LiveActivityKind.cover.icon
    }
    static func isBusy(_ stage: String) -> Bool {
        stage == "sent" || stage == "moving"
    }
}

struct CoverLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: CoverActivityAttributes.self) { context in
            CoverLockView(context: context)
                .widgetURL(LiveActivityKind.cover.deepLink)
        } dynamicIsland: { context in
            let stage = context.state.stage
            let tint = CoverFace.tint(stage)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: CoverFace.icon(stage))
                            .font(AppFont.captionStrong)
                            .foregroundStyle(tint)
                            .contentTransition(.symbolEffect(.replace))
                        if LA.expandedData(.cover) {
                            Text(context.attributes.deviceName)
                                .font(AppFont.captionStrong)
                                .foregroundStyle(tint)
                                .lineLimit(1)
                        }
                    }
                    .widgetURL(LiveActivityKind.cover.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.cover) {
                        Text(CoverFace.label(stage))
                            .font(AppFont.captionStrong)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.cover), CoverFace.isBusy(stage) {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView()
                                .tint(LiveActivityKind.cover.color)
                            Text(CoverFace.label(stage))
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: CoverFace.icon(stage))
                    .font(AppFont.captionStrong)
                    .foregroundStyle(tint)
                    .accessibilityLabel(Text(context.attributes.deviceName))
            } compactTrailing: {
                if LA.island(.cover) {
                    Text(CoverFace.label(stage))
                        .font(AppFont.label)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            } minimal: {
                Image(systemName: CoverFace.icon(stage))
                    .foregroundStyle(tint)
                    .accessibilityLabel(Text(context.attributes.deviceName))
            }
        }
    }
}

private struct CoverLockView: View {
    let context: ActivityViewContext<CoverActivityAttributes>

    var body: some View {
        let stage = context.state.stage
        if LA.lockDetails(.cover) {
            HStack(spacing: AppSpacing.base) {
                ZStack {
                    Circle()
                        .fill(CoverFace.tint(stage).opacity(AppOpacity.tintedFill))
                        .frame(width: IslandMetrics.iconDisc, height: IslandMetrics.iconDisc)
                    Image(systemName: CoverFace.icon(stage))
                        .font(AppFont.title3)
                        .foregroundStyle(CoverFace.tint(stage))
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.deviceName)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(CoverFace.label(stage))
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if CoverFace.isBusy(stage) {
                    ProgressView()
                        .tint(LiveActivityKind.cover.color)
                }
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .cover, title: Text(context.attributes.deviceName))
        }
    }
}

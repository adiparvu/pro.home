import ActivityKit
import Foundation

// Drives real Live Activities from the app's flows: shopping check-offs,
// deliveries, maintenance tasks and plant-watering sessions call the sync
// methods below, and this service starts / updates / ends the system activity
// accordingly — always gated by the user's Live Activity preferences.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()
    private init() {}

    /// Set by the root view once the primary property is known, so activities
    /// can show the property name (the "Property Name" appearance option).
    var propertyName: String = ""

    // Active activity tokens
    private var shoppingActivity: Activity<ShoppingActivityAttributes>?
    private var maintenanceActivity: Activity<MaintenanceActivityAttributes>?
    private var deliveryActivities: [UUID: Activity<DeliveryActivityAttributes>] = [:]
    private var deliveryStartedAt: [UUID: Date] = [:]
    private var plantCareActivity: Activity<PlantCareActivityAttributes>?
    private var plantSessionTotal = 0
    private var workSessionActivity: Activity<WorkSessionActivityAttributes>?

    private var systemEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Freshness contract: past this date the system dims the activity as
    /// stale instead of presenting hours-old data as live. Terminal updates
    /// (ends) keep a nil stale date — a final state doesn't go stale.
    private func stale(hours: Double) -> Date { Date().addingTimeInterval(hours * 3600) }

    private func allowed(_ kind: LiveActivityKind) -> Bool {
        LiveActivityPrefs.isEnabled && LiveActivityPrefs.autoStart(for: kind) && systemEnabled
    }

    // MARK: - Shopping (driven by SupplyService.toggleComplete)

    /// Starts on the first checked item, updates while shopping, ends when done.
    /// `nextItemId`/`nextItemName` are the next still-unbought item in this list,
    /// so the island's "check off" button acts on a real, list-scoped id.
    func syncShopping(listName: String, bought: Int, total: Int,
                      nextItemId: UUID? = nil, nextItemName: String? = nil) {
        guard total > 0 else { return }

        // Adopt an activity that survived an app relaunch.
        if shoppingActivity == nil {
            shoppingActivity = Activity<ShoppingActivityAttributes>.activities.first
        }

        let state = ShoppingActivityAttributes.ContentState(
            itemsBought: bought, totalItems: total, listName: listName,
            nextItemId: nextItemId, nextItemName: nextItemName)

        if let activity = shoppingActivity {
            if bought >= total {
                Task { await activity.end(.init(state: state, staleDate: nil),
                                          dismissalPolicy: .after(Date().addingTimeInterval(5))) }
                shoppingActivity = nil
            } else if activity.attributes.listName != listName {
                // Switched lists — restart for the new one.
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                shoppingActivity = nil
                startShopping(listName: listName, state: state)
            } else {
                Task { await activity.update(.init(state: state, staleDate: stale(hours: 2))) }
            }
        } else if bought > 0, bought < total {
            startShopping(listName: listName, state: state)
        }
    }

    private func startShopping(listName: String, state: ShoppingActivityAttributes.ContentState) {
        guard allowed(.shopping) else { return }
        let attrs = ShoppingActivityAttributes(propertyName: propertyName, listName: listName)
        shoppingActivity = try? Activity.request(
            attributes: attrs, content: .init(state: state, staleDate: stale(hours: 2)), pushType: nil)
    }

    // MARK: - Work session (user-initiated, from a task row or the watch)
    //
    // Gated only by the global Live Activity switch — the auto-start
    // preferences govern activities the app starts by itself, and this one
    // is always an explicit human action. One session at a time: starting a
    // new one ends the old, matching the watch's single-session model.

    func startWorkSession(taskId: UUID, title: String, startedAt: Date = Date()) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }
        endWorkSession(completed: false)
        let attrs = WorkSessionActivityAttributes(taskId: taskId, taskTitle: title,
                                                  startedAt: startedAt,
                                                  propertyName: propertyName)
        workSessionActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: .init(isComplete: false), staleDate: stale(hours: 12)),
            pushType: nil)
    }

    func endWorkSession(completed: Bool) {
        workSessionActivity = nil
        Task {
            for activity in Activity<WorkSessionActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: .init(isComplete: completed), staleDate: nil),
                    dismissalPolicy: completed ? .after(.now + 2) : .immediate)
            }
        }
    }

    // MARK: - Maintenance (driven by TaskService)

    func startMaintenance(taskTitle: String, category: String, step: String? = nil,
                          taskId: UUID? = nil) {
        guard allowed(.maintenance) else { return }
        if maintenanceActivity == nil {
            maintenanceActivity = Activity<MaintenanceActivityAttributes>.activities.first
        }
        guard maintenanceActivity == nil else { return }
        let attrs = MaintenanceActivityAttributes(taskTitle: taskTitle, category: category,
                                                  propertyName: propertyName, taskId: taskId)
        let state = MaintenanceActivityAttributes.ContentState(
            progress: 0, stepDescription: step ?? String(localized: "In progress"), isComplete: false)
        maintenanceActivity = try? Activity.request(
            attributes: attrs, content: .init(state: state, staleDate: stale(hours: 2)), pushType: nil)
    }

    func updateMaintenance(progress: Double, step: String) {
        guard let activity = maintenanceActivity else { return }
        let state = MaintenanceActivityAttributes.ContentState(progress: progress, stepDescription: step, isComplete: false)
        Task { await activity.update(.init(state: state, staleDate: stale(hours: 2))) }
    }

    /// Ends the activity if the completed task is the one being tracked.
    func completeMaintenance(taskTitle: String) {
        if maintenanceActivity == nil {
            maintenanceActivity = Activity<MaintenanceActivityAttributes>.activities.first
        }
        guard let activity = maintenanceActivity, activity.attributes.taskTitle == taskTitle else { return }
        let state = MaintenanceActivityAttributes.ContentState(
            progress: 1.0, stepDescription: String(localized: "Done!"), isComplete: true)
        Task { await activity.end(.init(state: state, staleDate: nil),
                                  dismissalPolicy: .after(Date().addingTimeInterval(4))) }
        maintenanceActivity = nil
    }

    // MARK: - Delivery (driven by DeliveryService add/update + server pushes)

    /// The island shows at most two activities anyway; keeping our own fleet
    /// small means every parcel still reads at a glance.
    private static let maxDeliveryActivities = 3

    /// Reflects a delivery's current state: starts when active, updates status
    /// (alerting on the transitions that matter), ends when delivered /
    /// returned / missed. Live-tracked parcels also register for ActivityKit
    /// pushes so the tracking webhook can update the island while the phone
    /// is locked.
    func syncDelivery(_ delivery: Delivery) {
        // Adopt activities that survived an app relaunch (matched by tracking id).
        if deliveryActivities[delivery.id] == nil {
            deliveryActivities[delivery.id] = Activity<DeliveryActivityAttributes>.activities.first {
                $0.attributes.trackingNumber == (delivery.trackingNumber ?? "")
                    && $0.attributes.description == delivery.description
            }
            if deliveryActivities[delivery.id] != nil, deliveryStartedAt[delivery.id] == nil {
                deliveryStartedAt[delivery.id] = Date()
            }
        }

        let milestone = delivery.activityMilestone
        let state = DeliveryActivityAttributes.ContentState(
            status: delivery.liveStatus ?? delivery.status,
            statusLabel: delivery.statusLabel,
            eta: delivery.expectedDisplay,
            etaDate: delivery.expectedArrivalDate,
            milestoneIndex: milestone.index,
            checkpoint: delivery.latestCheckpointLine,
            isProblem: milestone.problem)

        if let activity = deliveryActivities[delivery.id] {
            if delivery.isActive {
                // Light up the Lock Screen only when something actionable
                // happened — arriving today or a problem, not every hop.
                let becameUrgent = activity.content.state.status != state.status
                    && (state.status == "out_for_delivery" || milestone.problem)
                let alert: AlertConfiguration? = becameUrgent
                    ? AlertConfiguration(title: "\(delivery.description)",
                                         body: "\(delivery.statusLabel)",
                                         sound: .default)
                    : nil
                Task { await activity.update(.init(state: state, staleDate: stale(hours: 6)),
                                             alertConfiguration: alert) }
            } else {
                Task { await activity.end(.init(state: state, staleDate: nil),
                                          dismissalPolicy: .after(Date().addingTimeInterval(6))) }
                cleanupDelivery(id: delivery.id, activityId: activity.id)
            }
        } else if delivery.isActive, allowed(.delivery) {
            makeRoomForDelivery()
            guard deliveryActivities.count < Self.maxDeliveryActivities else { return }
            let attrs = DeliveryActivityAttributes(
                trackingNumber: delivery.trackingNumber ?? "",
                carrier: delivery.carrier ?? String(localized: "Courier"),
                description: delivery.description,
                propertyName: propertyName,
                deliveryId: delivery.id)
            // Live-tracked parcels update from the server while the phone is
            // locked; manually tracked ones only ever update from the app.
            let activity = try? Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: stale(hours: 6)),
                pushType: delivery.isLiveTracked ? .token : nil)
            deliveryActivities[delivery.id] = activity
            deliveryStartedAt[delivery.id] = Date()
            if let activity, let trackerId = delivery.trackerId {
                observeActivityPushToken(activity, trackerId: trackerId)
            }
        }
    }

    func endDelivery(id: UUID) {
        guard let activity = deliveryActivities[id] else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        cleanupDelivery(id: id, activityId: activity.id)
    }

    /// When the fleet is full, the oldest island makes room for the newest
    /// parcel — most-recent activity wins.
    private func makeRoomForDelivery() {
        while deliveryActivities.count >= Self.maxDeliveryActivities {
            guard let oldest = deliveryStartedAt
                .filter({ deliveryActivities[$0.key] != nil })
                .min(by: { $0.value < $1.value })?.key,
                let activity = deliveryActivities[oldest] else { return }
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            cleanupDelivery(id: oldest, activityId: activity.id)
        }
    }

    private func cleanupDelivery(id: UUID, activityId: String) {
        deliveryActivities.removeValue(forKey: id)
        deliveryStartedAt.removeValue(forKey: id)
        Task { await removeActivityToken(activityId: activityId) }
    }

    // MARK: - ActivityKit push tokens (server-updated deliveries)
    //
    // The token rows land in `live_activity_tokens`; the track-webhook edge
    // function reads them by tracker id and sends `apns-push-type:
    // liveactivity` updates, so a parcel moves on the island with the app
    // closed and the phone in a pocket.

    private func observeActivityPushToken(_ activity: Activity<DeliveryActivityAttributes>,
                                          trackerId: String) {
        Task {
            for await token in activity.pushTokenUpdates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                await uploadActivityToken(hex, activityId: activity.id,
                                          kind: "delivery", trackerId: trackerId)
            }
        }
    }

    private func observeIoTAlertPushToken(_ activity: Activity<IoTAlertActivityAttributes>,
                                          sensorId: UUID) {
        Task {
            for await token in activity.pushTokenUpdates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                await uploadActivityToken(hex, activityId: activity.id,
                                          kind: "iot_alert", trackerId: sensorId.uuidString)
            }
        }
    }

    private func uploadActivityToken(_ hex: String, activityId: String,
                                     kind: String, trackerId: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        struct Row: Encodable {
            let user_id: String
            let activity_id: String
            let activity_kind: String
            let tracker_id: String
            let token: String
            let environment: String
        }
        let row = Row(user_id: uid.uuidString, activity_id: activityId,
                      activity_kind: kind, tracker_id: trackerId,
                      token: hex, environment: PushTokenService.environment)
        try? await supabase.from("live_activity_tokens")
            .upsert(row, onConflict: "activity_id").execute()
    }

    private func removeActivityToken(activityId: String) async {
        try? await supabase.from("live_activity_tokens")
            .delete().eq("activity_id", value: activityId).execute()
    }

    // MARK: - Plant care (driven by PlantService.markWatered)

    /// One watering session: starts on the first watered plant, tracks progress
    /// against how many needed water when the session began, ends at zero left.
    func plantWatered(name: String, remainingAfter: Int) {
        if plantCareActivity == nil, remainingAfter >= 0, allowed(.plantCare) {
            plantSessionTotal = remainingAfter + 1
            let attrs = PlantCareActivityAttributes(propertyName: propertyName)
            let state = PlantCareActivityAttributes.ContentState(
                wateredCount: 1, totalCount: plantSessionTotal, lastWateredName: name)
            if plantSessionTotal > 1 {
                plantCareActivity = try? Activity.request(
                    attributes: attrs, content: .init(state: state, staleDate: stale(hours: 2)), pushType: nil)
            }
            return
        }
        guard let activity = plantCareActivity else { return }
        let watered = max(0, plantSessionTotal - remainingAfter)
        let state = PlantCareActivityAttributes.ContentState(
            wateredCount: watered, totalCount: plantSessionTotal, lastWateredName: name)
        if remainingAfter <= 0 {
            Task { await activity.end(.init(state: state, staleDate: nil),
                                      dismissalPolicy: .after(Date().addingTimeInterval(4))) }
            plantCareActivity = nil
            plantSessionTotal = 0
        } else {
            Task { await activity.update(.init(state: state, staleDate: stale(hours: 2))) }
        }
    }

    // MARK: - Emergency incident (user-pinned from the Emergency page)
    //
    // Gated only by the master switch: pinning an incident is always an
    // explicit human action. No stale date — an emergency never becomes
    // yesterday's news on its own; it ends when the person ends it.

    private var emergencyActivity: Activity<EmergencyActivityAttributes>?

    func startEmergency() {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }
        guard Activity<EmergencyActivityAttributes>.activities.isEmpty else { return }
        let attrs = EmergencyActivityAttributes(startedAt: Date(), propertyName: propertyName)
        emergencyActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: .init(isActive: true), staleDate: nil),
            pushType: nil)
    }

    func endEmergency() {
        emergencyActivity = nil
        Task {
            for a in Activity<EmergencyActivityAttributes>.activities {
                await a.end(.init(state: .init(isActive: false), staleDate: nil),
                            dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - IoT alerts (driven by IoTService polling)
    //
    // One island per alerting sensor, capped at the two most severe;
    // acknowledged instances stay silenced (app-group set, shared with the
    // widget's intent) until the sensor itself clears.

    private var iotAlertActivities: [UUID: Activity<IoTAlertActivityAttributes>] = [:]
    private static let maxIoTAlerts = 2
    private static let ackedAlertsKey = "prvio.iot.ackedAlerts"

    func syncIoTAlerts(_ alerting: [IoTSensor]) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }

        var acked = Set(LiveActivityPrefs.store.stringArray(forKey: Self.ackedAlertsKey) ?? [])
        let alertingIds = Set(alerting.map(\.id.uuidString))

        // A cleared sensor loses its acknowledgement, so a future incident
        // alerts again instead of staying muted forever.
        let staleAcks = acked.subtracting(alertingIds)
        if !staleAcks.isEmpty {
            acked.subtract(staleAcks)
            LiveActivityPrefs.store.set(Array(acked), forKey: Self.ackedAlertsKey)
        }

        // Adopt activities that survived a relaunch.
        for activity in Activity<IoTAlertActivityAttributes>.activities
        where iotAlertActivities[activity.attributes.sensorId] == nil {
            iotAlertActivities[activity.attributes.sensorId] = activity
        }

        // End islands whose sensor cleared or was acknowledged.
        for (id, activity) in iotAlertActivities
        where !alertingIds.contains(id.uuidString) || acked.contains(id.uuidString) {
            let display = activity.content.state.valueDisplay
            let activityId = activity.id
            Task {
                await activity.end(
                    .init(state: .init(valueDisplay: display, isActive: false), staleDate: nil),
                    dismissalPolicy: .after(.now + 4))
                await removeActivityToken(activityId: activityId)
            }
            iotAlertActivities.removeValue(forKey: id)
        }

        guard allowed(.iotAlert) else { return }
        let ranked = alerting
            .filter { !acked.contains($0.id.uuidString) }
            .sorted { ($0.isCriticalAlert ? 0 : 1) < ($1.isCriticalAlert ? 0 : 1) }

        for sensor in ranked {
            if let activity = iotAlertActivities[sensor.id] {
                Task { await activity.update(
                    .init(state: .init(valueDisplay: sensor.displayValue, isActive: true),
                          staleDate: stale(hours: 1))) }
            } else if iotAlertActivities.count < Self.maxIoTAlerts {
                let attrs = IoTAlertActivityAttributes(
                    sensorId: sensor.id, sensorName: sensor.name,
                    icon: sensor.type.icon, isCritical: sensor.isCriticalAlert,
                    zone: sensor.linkedZoneName.isEmpty ? nil : sensor.linkedZoneName,
                    startedAt: Date(), propertyName: propertyName)
                // Push-capable: the iot-event webhook keeps this island live
                // while the phone is locked and the app closed.
                let activity = try? Activity.request(
                    attributes: attrs,
                    content: .init(state: .init(valueDisplay: sensor.displayValue, isActive: true),
                                   staleDate: stale(hours: 1)),
                    pushType: .token)
                iotAlertActivities[sensor.id] = activity
                if let activity {
                    observeIoTAlertPushToken(activity, sensorId: sensor.id)
                }
            }
        }
    }

    // MARK: - Energy session (user-pinned from the IoT hub)

    private var energyActivity: Activity<EnergyActivityAttributes>?

    func startEnergySession(consumptionW: Double?, productionW: Double?) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }
        guard Activity<EnergyActivityAttributes>.activities.isEmpty else { return }
        let attrs = EnergyActivityAttributes(startedAt: Date(), propertyName: propertyName)
        energyActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: .init(consumptionW: consumptionW, productionW: productionW),
                           staleDate: stale(hours: 0.25)),
            pushType: nil)
    }

    /// Fed by every real sensor poll; a no-op while no session runs.
    func updateEnergy(consumptionW: Double?, productionW: Double?) {
        if energyActivity == nil {
            energyActivity = Activity<EnergyActivityAttributes>.activities.first
        }
        guard let activity = energyActivity else { return }
        Task { await activity.update(
            .init(state: .init(consumptionW: consumptionW, productionW: productionW),
                  staleDate: stale(hours: 0.25))) }
    }

    func endEnergySession() {
        energyActivity = nil
        Task {
            for a in Activity<EnergyActivityAttributes>.activities {
                await a.end(.init(state: a.content.state, staleDate: nil),
                            dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Cover operation (garage / gate, driven by IoTService.perform)

    private var coverActivity: Activity<CoverActivityAttributes>?

    func startCoverOperation(deviceName: String) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }
        // One operation at a time — a new command replaces the old island.
        Task {
            for a in Activity<CoverActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        let attrs = CoverActivityAttributes(deviceName: deviceName, startedAt: Date())
        coverActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: .init(stage: "sent"), staleDate: stale(hours: 0.25)),
            pushType: nil)
    }

    func updateCover(stage: String) {
        guard let activity = coverActivity else { return }
        Task { await activity.update(.init(state: .init(stage: stage),
                                           staleDate: stale(hours: 0.25))) }
    }

    func endCoverOperation(stage: String) {
        guard let activity = coverActivity else { return }
        coverActivity = nil
        Task { await activity.end(.init(state: .init(stage: stage), staleDate: nil),
                                  dismissalPolicy: .after(.now + 4)) }
    }

    // MARK: - Auto-start (Start When App Opens / Start on a Schedule)

    /// Called when the app becomes active with fresh data. Honors the
    /// "Start When App Opens" and "Start on a Schedule" preferences.
    func evaluateAutoStart(deliveries: [Delivery], tasks: [MaintenanceTask]) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }

        // Resume in-progress deliveries.
        if LiveActivityPrefs.startOnOpen {
            for delivery in deliveries where delivery.isActive {
                syncDelivery(delivery)
            }
        }

        // Start activities for tasks scheduled today.
        if LiveActivityPrefs.startOnSchedule {
            let today = AppDate.dayString(from: Date())
            if let due = tasks.first(where: { !$0.isCompleted && ($0.dueDate?.hasPrefix(today) ?? false) }) {
                startMaintenance(taskTitle: due.title, category: due.category,
                                 step: String(localized: "Scheduled for today"), taskId: due.id)
            }
        }
    }

    // MARK: - Per-kind status & control

    /// Whether an activity of this kind is currently running on the system.
    func isActive(_ kind: LiveActivityKind) -> Bool {
        switch kind {
        case .shopping:    return !Activity<ShoppingActivityAttributes>.activities.isEmpty
        case .delivery:    return !Activity<DeliveryActivityAttributes>.activities.isEmpty
        case .maintenance: return !Activity<MaintenanceActivityAttributes>.activities.isEmpty
        case .plantCare:   return !Activity<PlantCareActivityAttributes>.activities.isEmpty
        case .workSession: return !Activity<WorkSessionActivityAttributes>.activities.isEmpty
        case .emergency:   return !Activity<EmergencyActivityAttributes>.activities.isEmpty
        case .iotAlert:    return !Activity<IoTAlertActivityAttributes>.activities.isEmpty
        case .energy:      return !Activity<EnergyActivityAttributes>.activities.isEmpty
        case .cover:       return !Activity<CoverActivityAttributes>.activities.isEmpty
        }
    }

    /// Immediately ends every running activity of this kind.
    func end(_ kind: LiveActivityKind) {
        Task {
            switch kind {
            case .shopping:
                for a in Activity<ShoppingActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                shoppingActivity = nil
            case .delivery:
                for a in Activity<DeliveryActivityAttributes>.activities {
                    await a.end(nil, dismissalPolicy: .immediate)
                    await removeActivityToken(activityId: a.id)
                }
                deliveryActivities.removeAll()
                deliveryStartedAt.removeAll()
            case .maintenance:
                for a in Activity<MaintenanceActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                maintenanceActivity = nil
            case .plantCare:
                for a in Activity<PlantCareActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                plantCareActivity = nil
            case .workSession:
                for a in Activity<WorkSessionActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                workSessionActivity = nil
            case .emergency:
                for a in Activity<EmergencyActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                emergencyActivity = nil
            case .iotAlert:
                for a in Activity<IoTAlertActivityAttributes>.activities {
                    await a.end(nil, dismissalPolicy: .immediate)
                    await removeActivityToken(activityId: a.id)
                }
                iotAlertActivities.removeAll()
            case .energy:
                for a in Activity<EnergyActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                energyActivity = nil
            case .cover:
                for a in Activity<CoverActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                coverActivity = nil
            }
        }
    }

    // MARK: - Appearance refresh

    /// Re-pushes the current content state to every running activity. Live
    /// Activity views read the appearance preferences at render time, but the
    /// system only re-renders on a content update — so after the user changes an
    /// appearance option we push the same state back to force an immediate
    /// re-render that adopts the new settings, instead of waiting for the next
    /// natural update. Iterating `Activity.activities` covers activities that
    /// survived a relaunch and aren't tracked in memory yet.
    func refreshAppearance() {
        Task {
            for a in Activity<ShoppingActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: nil))
            }
            for a in Activity<MaintenanceActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: nil))
            }
            for a in Activity<DeliveryActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: nil))
            }
            for a in Activity<PlantCareActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 2)))
            }
            for a in Activity<WorkSessionActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 12)))
            }
            for a in Activity<EmergencyActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: nil))
            }
            for a in Activity<IoTAlertActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 1)))
            }
            for a in Activity<EnergyActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 0.25)))
            }
            for a in Activity<CoverActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 0.25)))
            }
        }
    }
}

// MARK: - Delivery → activity state mapping

private extension Delivery {
    /// The 4-segment journey (0 ordered · 1 in transit · 2 out for delivery ·
    /// 3 delivered) plus whether the parcel is in a problem state. Uses the
    /// live-tracking vocabulary when the webhook has filled it, the legacy
    /// status otherwise.
    var activityMilestone: (index: Int, problem: Bool) {
        switch liveStatus ?? "" {
        case "pending", "info_received":                  return (0, false)
        case "in_transit":                                return (1, false)
        case "out_for_delivery", "available_for_pickup":  return (2, false)
        case "delivered":                                 return (3, false)
        case "exception", "expired":                      return (1, true)
        case "failed_attempt":                            return (2, true)
        default:
            switch status {
            case "out_for_delivery": return (2, false)
            case "delivered":        return (3, false)
            case "missed":           return (2, true)
            default:                 return (0, false)
            }
        }
    }

    /// The precise expected-arrival instant, but ONLY when the tracking
    /// aggregator supplied a real timestamp (`estimatedDelivery` is a genuine
    /// ISO8601 instant, parsed through the same door as every server date).
    /// The day-level `expectedDate` is deliberately NOT used here: a ticking
    /// countdown to a calendar day would invent a precision the carrier never
    /// gave. Returns nil once the parcel is no longer active so the island
    /// stops counting toward a moment that has passed.
    var expectedArrivalDate: Date? {
        guard isActive, let s = estimatedDelivery else { return nil }
        return ISODate.date(from: s)
    }

    /// Latest human-readable tracking event: "Sorted at hub · Cluj".
    var latestCheckpointLine: String? {
        guard let c = liveCheckpoints.first else { return nil }
        let message = (c.message?.isEmpty == false ? c.message : c.status) ?? ""
        if let location = c.location, !location.isEmpty {
            return message.isEmpty ? location : "\(message) · \(location)"
        }
        return message.isEmpty ? nil : message
    }
}

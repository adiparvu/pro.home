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
    private var deliveryActivity: Activity<DeliveryActivityAttributes>?
    private var deliveryParcelId: UUID?
    private var deliveryScore: Double = 0
    private var plantCareActivity: Activity<PlantCareActivityAttributes>?
    private var plantSessionTotal = 0
    private var workSessionActivity: Activity<WorkSessionActivityAttributes>?

    // Session heartbeats — the last moment each session showed real life
    // (a check-off, a watering, a sensor poll). `reconcile()` ends sessions
    // whose heartbeat went silent: a Live Activity tracks a live event, and
    // an event nobody is living is over.
    private var shoppingBeat: Date?
    private var plantBeat: Date?
    private var energyBeat: Date?
    private var maintenanceStartedAt: Date?

    // MARK: - Relevance (one scale for the whole app)
    //
    // ActivityKit shows the highest-relevance activity in the Dynamic Island
    // and orders the Lock Screen by the same number, so every kind scores on
    // one scale: safety first, then things in motion, then sessions the user
    // is running, then ambient monitors. Delivery is situational — see
    // `deliveryRelevance(_:)` (40–90 on this same scale).
    enum Relevance {
        static let emergency   = 100.0
        static let iotCritical =  95.0
        static let cover       =  80.0
        static let iotWarning  =  70.0
        static let workSession =  50.0
        static let shopping    =  35.0
        static let plantCare   =  30.0
        static let maintenance =  25.0
        static let energy      =  15.0
    }

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
        shoppingBeat = Date()

        // Adopt an activity that survived an app relaunch.
        if shoppingActivity == nil {
            shoppingActivity = Activity<ShoppingActivityAttributes>.activities.first
        }

        let state = ShoppingActivityAttributes.ContentState(
            itemsBought: bought, totalItems: total, listName: listName,
            nextItemId: nextItemId, nextItemName: nextItemName)

        if let activity = shoppingActivity {
            if bought >= total {
                // Completed: the "done" summary stays readable for a few
                // minutes (HIG: dismissal proportional to the activity).
                Task { await activity.end(.init(state: state, staleDate: nil),
                                          dismissalPolicy: .after(.now + 5 * 60)) }
                LiveActivityHubStore.record(kind: .shopping, phase: "completed", title: listName)
                shoppingActivity = nil
            } else if activity.attributes.listName != listName {
                // Switched lists — restart for the new one.
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                LiveActivityHubStore.record(kind: .shopping, phase: "ended", title: activity.attributes.listName)
                shoppingActivity = nil
                startShopping(listName: listName, state: state)
            } else {
                Task { await activity.update(.init(state: state, staleDate: stale(hours: 0.75),
                                                   relevanceScore: Relevance.shopping)) }
            }
        } else if bought > 0, bought < total {
            startShopping(listName: listName, state: state)
        }
    }

    private func startShopping(listName: String, state: ShoppingActivityAttributes.ContentState) {
        guard allowed(.shopping) else { return }
        let attrs = ShoppingActivityAttributes(propertyName: propertyName, listName: listName)
        shoppingActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: stale(hours: 0.75),
                           relevanceScore: Relevance.shopping),
            pushType: nil)
        if shoppingActivity != nil { LiveActivityHubStore.record(kind: .shopping, phase: "started", title: listName) }
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
            content: .init(state: .init(isComplete: false), staleDate: stale(hours: 8),
                           relevanceScore: Relevance.workSession),
            pushType: nil)
        if workSessionActivity != nil { LiveActivityHubStore.record(kind: .workSession, phase: "started", title: title) }
    }

    func endWorkSession(completed: Bool) {
        if let t = (workSessionActivity ?? Activity<WorkSessionActivityAttributes>.activities.first)?.attributes.taskTitle { LiveActivityHubStore.record(kind: .workSession, phase: completed ? "completed" : "ended", title: t) }
        workSessionActivity = nil
        Task {
            for activity in Activity<WorkSessionActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: .init(isComplete: completed), staleDate: nil),
                    dismissalPolicy: completed ? .after(.now + 10 * 60) : .immediate)
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
            attributes: attrs,
            content: .init(state: state, staleDate: stale(hours: 2),
                           relevanceScore: Relevance.maintenance),
            pushType: nil)
        if maintenanceActivity != nil {
            maintenanceStartedAt = Date()
            LiveActivityHubStore.record(kind: .maintenance, phase: "started", title: taskTitle)
        }
    }

    func updateMaintenance(progress: Double, step: String) {
        guard let activity = maintenanceActivity else { return }
        let state = MaintenanceActivityAttributes.ContentState(progress: progress, stepDescription: step, isComplete: false)
        Task { await activity.update(.init(state: state, staleDate: stale(hours: 2),
                                           relevanceScore: Relevance.maintenance)) }
    }

    /// Ends the activity if the completed task is the one being tracked.
    func completeMaintenance(taskTitle: String) {
        if maintenanceActivity == nil {
            maintenanceActivity = Activity<MaintenanceActivityAttributes>.activities.first
        }
        guard let activity = maintenanceActivity, activity.attributes.taskTitle == taskTitle else { return }
        LiveActivityHubStore.record(kind: .maintenance, phase: "completed", title: taskTitle)
        let state = MaintenanceActivityAttributes.ContentState(
            progress: 1.0, stepDescription: String(localized: "Done!"), isComplete: true)
        Task { await activity.end(.init(state: state, staleDate: nil),
                                  dismissalPolicy: .after(.now + 5 * 60)) }
        maintenanceActivity = nil
        maintenanceStartedAt = nil
    }

    // MARK: - Delivery (one island: the most relevant parcel actually in motion)
    //
    // HIG, verbatim: "prefer a single Live Activity that uses a dynamic
    // layout" over separate activities the person must jump between — so the
    // app keeps exactly ONE delivery island, owned by the parcel that has
    // EARNED it. A Live Activity is a live event, not standing state: a
    // parcel that is merely "expected" for days holds no island. A parcel
    // earns the island when:
    //   · a problem needs the user (failed attempt / exception)   → 90
    //   · it is out for delivery / ready for pickup               → 85
    //   · it is due today                                         → 60
    //   · the courier scanned it in the last three hours          → 40
    // Everything else belongs to the app, the widget and notifications.
    // The score doubles as the ActivityKit relevanceScore, so a problem
    // parcel outranks a routine one in the Dynamic Island.

    /// The island-worthiness of a parcel right now — nil means "no island".
    static func deliveryRelevance(_ d: Delivery) -> Double? {
        guard d.isActive else { return nil }
        let milestone = d.activityMilestone
        if milestone.problem { return 90 }
        if milestone.index == 2 { return 85 }
        if let eta = d.expectedArrivalDate, Calendar.current.isDateInToday(eta) { return 60 }
        if let day = d.expectedDate, let date = AppDate.day(from: day),
           Calendar.current.isDateInToday(date) { return 60 }
        if let last = d.lastEventAt, let at = ISODate.date(from: last),
           Date().timeIntervalSince(at) < 3 * 3600 { return 40 }
        return nil
    }

    /// Single entry point: hand it the whole parcel list after any change.
    /// It updates the island in place, hands it to a more relevant parcel,
    /// ends it when nothing is in motion anymore — and, when the tracked
    /// parcel just arrived, ends with the delivered summary kept readable on
    /// the Lock Screen for half an hour (HIG: "15 to 30 minutes is adequate").
    func syncDeliveries(_ all: [Delivery], mayStart: Bool = true) {
        adoptAndPruneDeliveryOrphans()

        let ranked = all
            .compactMap { d in Self.deliveryRelevance(d).map { (parcel: d, score: $0) } }
            .sorted { $0.score > $1.score }
        let others = max(0, ranked.count - 1)

        if let activity = deliveryActivity {
            let ownerId = deliveryParcelId ?? activity.attributes.deliveryId
            if let top = ranked.first, top.parcel.id == ownerId {
                updateDelivery(activity, parcel: top.parcel, score: top.score, others: others)
                return
            }
            // The owner no longer holds the island (arrived, went quiet, or
            // was outranked).
            releaseDelivery(activity, owner: all.first { $0.id == ownerId })
        }
        if let top = ranked.first, mayStart, allowed(.delivery) {
            startDelivery(top.parcel, score: top.score, others: others)
        }
    }

    /// Whether the island currently narrates this parcel — DeliveryService
    /// skips its duplicate local notification then (HIG: "don't use push
    /// notifications alongside Live Activities for the same updates").
    func hasDeliveryActivity(for id: UUID) -> Bool {
        deliveryActivity != nil && deliveryParcelId == id
    }

    /// The user deleted the parcel: its island goes with it, instantly.
    func endDelivery(id: UUID) {
        guard let activity = deliveryActivity,
              (deliveryParcelId ?? activity.attributes.deliveryId) == id else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        LiveActivityHubStore.record(kind: .delivery, phase: "ended", title: activity.attributes.description)
        cleanupDelivery(activityId: activity.id)
    }

    private func deliveryState(_ d: Delivery, others: Int) -> DeliveryActivityAttributes.ContentState {
        let milestone = d.activityMilestone
        return .init(status: d.liveStatus ?? d.status,
                     statusLabel: d.statusLabel,
                     eta: d.expectedDisplay,
                     etaDate: d.expectedArrivalDate,
                     milestoneIndex: milestone.index,
                     checkpoint: d.latestCheckpointLine,
                     isProblem: milestone.problem,
                     othersActive: others > 0 ? others : nil)
    }

    private func updateDelivery(_ activity: Activity<DeliveryActivityAttributes>,
                                parcel: Delivery, score: Double, others: Int) {
        let state = deliveryState(parcel, others: others)
        // Light up the Lock Screen only when something actionable happened —
        // out for delivery or a problem, never a routine hop.
        let milestone = parcel.activityMilestone
        let becameUrgent = activity.content.state.status != state.status
            && (state.status == "out_for_delivery" || milestone.problem)
        let alert: AlertConfiguration? = becameUrgent
            ? AlertConfiguration(title: "\(parcel.description)",
                                 body: "\(parcel.statusLabel)",
                                 sound: .default)
            : nil
        deliveryScore = score
        Task { await activity.update(.init(state: state, staleDate: stale(hours: 6),
                                           relevanceScore: score),
                                     alertConfiguration: alert) }
    }

    private func startDelivery(_ parcel: Delivery, score: Double, others: Int) {
        let attrs = DeliveryActivityAttributes(
            trackingNumber: parcel.trackingNumber ?? "",
            carrier: parcel.carrier ?? String(localized: "Courier"),
            description: parcel.description,
            propertyName: propertyName,
            deliveryId: parcel.id)
        // Live-tracked parcels update from the server while the phone is
        // locked; manually tracked ones only ever update from the app.
        let activity = try? Activity.request(
            attributes: attrs,
            content: .init(state: deliveryState(parcel, others: others),
                           staleDate: stale(hours: 6), relevanceScore: score),
            pushType: parcel.isLiveTracked ? .token : nil)
        deliveryActivity = activity
        deliveryParcelId = parcel.id
        deliveryScore = score
        if activity != nil { LiveActivityHubStore.record(kind: .delivery, phase: "started", title: parcel.description) }
        if let activity, let trackerId = parcel.trackerId {
            observeActivityPushToken(activity, trackerId: trackerId)
        }
    }

    /// Ends the island for a parcel that no longer holds it: a delivered
    /// parcel leaves its summary on the Lock Screen for 30 minutes; one that
    /// merely went quiet disappears without ceremony.
    private func releaseDelivery(_ activity: Activity<DeliveryActivityAttributes>,
                                 owner: Delivery?) {
        if let owner, (owner.liveStatus ?? owner.status) == "delivered" {
            let state = deliveryState(owner, others: 0)
            Task { await activity.end(.init(state: state, staleDate: nil),
                                      dismissalPolicy: .after(.now + 30 * 60)) }
            LiveActivityHubStore.record(kind: .delivery, phase: "completed", title: activity.attributes.description)
        } else {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            LiveActivityHubStore.record(kind: .delivery, phase: "ended", title: activity.attributes.description)
        }
        cleanupDelivery(activityId: activity.id)
    }

    /// Adopts a survivor from a relaunch and ends any extras left behind by
    /// the old fleet-of-three model — the single-island rule holds even
    /// across app updates.
    private func adoptAndPruneDeliveryOrphans() {
        guard deliveryActivity == nil else { return }
        let orphans = Activity<DeliveryActivityAttributes>.activities
        deliveryActivity = orphans.first
        deliveryParcelId = orphans.first?.attributes.deliveryId
        for extra in orphans.dropFirst() {
            let activityId = extra.id
            Task {
                await extra.end(nil, dismissalPolicy: .immediate)
                await self.removeActivityToken(activityId: activityId)
            }
        }
    }

    private func cleanupDelivery(activityId: String) {
        deliveryActivity = nil
        deliveryParcelId = nil
        deliveryScore = 0
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
        plantBeat = Date()
        if plantCareActivity == nil, remainingAfter >= 0, allowed(.plantCare) {
            plantSessionTotal = remainingAfter + 1
            let attrs = PlantCareActivityAttributes(propertyName: propertyName)
            let state = PlantCareActivityAttributes.ContentState(
                wateredCount: 1, totalCount: plantSessionTotal, lastWateredName: name)
            if plantSessionTotal > 1 {
                plantCareActivity = try? Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: stale(hours: 0.5),
                                   relevanceScore: Relevance.plantCare),
                    pushType: nil)
                if plantCareActivity != nil { LiveActivityHubStore.record(kind: .plantCare, phase: "started", title: String(localized: "Plant watering")) }
            }
            return
        }
        guard let activity = plantCareActivity else { return }
        let watered = max(0, plantSessionTotal - remainingAfter)
        let state = PlantCareActivityAttributes.ContentState(
            wateredCount: watered, totalCount: plantSessionTotal, lastWateredName: name)
        if remainingAfter <= 0 {
            Task { await activity.end(.init(state: state, staleDate: nil),
                                      dismissalPolicy: .after(.now + 5 * 60)) }
            LiveActivityHubStore.record(kind: .plantCare, phase: "completed", title: String(localized: "Plant watering"))
            plantCareActivity = nil
            plantSessionTotal = 0
        } else {
            Task { await activity.update(.init(state: state, staleDate: stale(hours: 0.5),
                                               relevanceScore: Relevance.plantCare)) }
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
            content: .init(state: .init(isActive: true), staleDate: nil,
                           relevanceScore: Relevance.emergency),
            pushType: nil)
        if emergencyActivity != nil { LiveActivityHubStore.record(kind: .emergency, phase: "started", title: String(localized: "la_emergency_active")) }
    }

    func endEmergency() {
        if !Activity<EmergencyActivityAttributes>.activities.isEmpty { LiveActivityHubStore.record(kind: .emergency, phase: "ended", title: String(localized: "la_emergency_active")) }
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
            LiveActivityHubStore.record(kind: .iotAlert, phase: "ended", title: activity.attributes.sensorName)
            let display = activity.content.state.valueDisplay
            let activityId = activity.id
            Task {
                await activity.end(
                    .init(state: .init(valueDisplay: display, isActive: false), staleDate: nil),
                    dismissalPolicy: .after(.now + 5 * 60))
                await removeActivityToken(activityId: activityId)
            }
            iotAlertActivities.removeValue(forKey: id)
        }

        guard allowed(.iotAlert) else { return }
        let ranked = alerting
            .filter { !acked.contains($0.id.uuidString) }
            .sorted { ($0.isCriticalAlert ? 0 : 1) < ($1.isCriticalAlert ? 0 : 1) }

        for sensor in ranked {
            let score = sensor.isCriticalAlert ? Relevance.iotCritical : Relevance.iotWarning
            if let activity = iotAlertActivities[sensor.id] {
                Task { await activity.update(
                    .init(state: .init(valueDisplay: sensor.displayValue, isActive: true),
                          staleDate: stale(hours: 1), relevanceScore: score)) }
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
                                   staleDate: stale(hours: 1), relevanceScore: score),
                    pushType: .token)
                iotAlertActivities[sensor.id] = activity
                if activity != nil { LiveActivityHubStore.record(kind: .iotAlert, phase: "started", title: sensor.name) }
                if let activity {
                    observeIoTAlertPushToken(activity, sensorId: sensor.id)
                    // A critical hazard (smoke / gas / water leak) must light up
                    // the Lock Screen with sound the moment its island is raised,
                    // not appear silently. This fires exactly once per incident —
                    // the island then persists (updates take the branch above
                    // with no alert) until the sensor clears or is acknowledged,
                    // so a critical sensor can't buzz on every poll. Non-critical
                    // threshold crossings stay quiet.
                    if sensor.isCriticalAlert {
                        Task {
                            await activity.update(
                                .init(state: .init(valueDisplay: sensor.displayValue, isActive: true),
                                      staleDate: stale(hours: 1), relevanceScore: score),
                                alertConfiguration: AlertConfiguration(
                                    title: "la_iot_alert_title",
                                    body: "\(sensor.name) · \(sensor.displayValue)",
                                    sound: .default))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Energy session (user-pinned from the IoT hub)

    private var energyActivity: Activity<EnergyActivityAttributes>?

    /// An ambient gauge has no natural end, which the HIG explicitly frowns
    /// on ("tasks and events that have a defined beginning and end") — so the
    /// session defines one: it runs while the data is genuinely live and
    /// `reconcile()` ends it after two hours, or sooner when polling stops.
    func startEnergySession(consumptionW: Double?, productionW: Double?) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }
        guard Activity<EnergyActivityAttributes>.activities.isEmpty else { return }
        let attrs = EnergyActivityAttributes(startedAt: Date(), propertyName: propertyName)
        energyBeat = Date()
        energyActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: .init(consumptionW: consumptionW, productionW: productionW),
                           staleDate: stale(hours: 0.25), relevanceScore: Relevance.energy),
            pushType: nil)
        if energyActivity != nil { LiveActivityHubStore.record(kind: .energy, phase: "started", title: String(localized: "Energy")) }
    }

    /// Fed by every real sensor poll; a no-op while no session runs.
    func updateEnergy(consumptionW: Double?, productionW: Double?) {
        if energyActivity == nil {
            energyActivity = Activity<EnergyActivityAttributes>.activities.first
        }
        guard let activity = energyActivity else { return }
        energyBeat = Date()
        Task { await activity.update(
            .init(state: .init(consumptionW: consumptionW, productionW: productionW),
                  staleDate: stale(hours: 0.25), relevanceScore: Relevance.energy)) }
    }

    func endEnergySession() {
        if !Activity<EnergyActivityAttributes>.activities.isEmpty { LiveActivityHubStore.record(kind: .energy, phase: "ended", title: String(localized: "Energy")) }
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

    func startCoverOperation(deviceName: String, actuatorId: UUID? = nil) {
        guard LiveActivityPrefs.isEnabled, systemEnabled else { return }
        // One operation at a time — a new command replaces the old island.
        Task {
            for a in Activity<CoverActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        let attrs = CoverActivityAttributes(deviceName: deviceName, startedAt: Date(),
                                            actuatorId: actuatorId)
        coverActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: .init(stage: "sent"), staleDate: stale(hours: 0.25),
                           relevanceScore: Relevance.cover),
            pushType: nil)
        if coverActivity != nil { LiveActivityHubStore.record(kind: .cover, phase: "started", title: deviceName) }
    }

    func updateCover(stage: String) {
        guard let activity = coverActivity else { return }
        Task { await activity.update(.init(state: .init(stage: stage),
                                           staleDate: stale(hours: 0.25),
                                           relevanceScore: Relevance.cover)) }
    }

    func endCoverOperation(stage: String) {
        guard let activity = coverActivity else { return }
        LiveActivityHubStore.record(kind: .cover, phase: ["timeout", "failed"].contains(stage) ? "ended" : "completed", title: activity.attributes.deviceName)
        coverActivity = nil
        Task { await activity.end(.init(state: .init(stage: stage), staleDate: nil),
                                  dismissalPolicy: .after(.now + 2 * 60)) }
    }

    // MARK: - Reconcile (every foreground) — the anti-zombie pass
    //
    // HIG: "make sure you don't keep any activities running for longer than
    // needed" — and staleDate only DIMS an activity, it never ends one, so
    // somebody has to actually end what stopped being live. This runs on
    // every foreground with fresh data: it ends expired sessions, retires
    // orphans with no living driver, and re-decides which parcel (if any)
    // deserves the delivery island.
    //
    // Gone deliberately: "Start on a Schedule" — a task merely scheduled for
    // today is a plan, not a live event; plans belong to widgets and
    // notifications. A maintenance island now exists only while someone is
    // actually working (the work session they explicitly start).
    func reconcile(deliveries: [Delivery]) {
        guard systemEnabled else { return }
        guard LiveActivityPrefs.isEnabled else {
            // Master switch off: nothing may stay on the island.
            for kind in LiveActivityKind.allCases { end(kind) }
            return
        }
        sweepExpired()
        syncDeliveries(deliveries, mayStart: LiveActivityPrefs.startOnOpen)
    }

    /// Session lifetimes: past these, the real-world event is over even if
    /// nobody told the app — a shopping run doesn't pause for an hour, and
    /// the system would kill everything at 8h anyway (we end it cleanly
    /// first, with its final honest state).
    private enum Lifetime {
        static let shoppingIdle: TimeInterval    = 45 * 60
        static let plantIdle: TimeInterval       = 30 * 60
        static let energyIdle: TimeInterval      = 30 * 60
        static let energySession: TimeInterval   = 2 * 3600
        static let maintenance: TimeInterval     = 4 * 3600
        static let coverOrphan: TimeInterval     = 15 * 60
        static let systemCap: TimeInterval       = 8 * 3600
    }

    private func sweepExpired() {
        let now = Date()

        // Shopping / plant sessions: no heartbeat (or a relaunch severed the
        // driver) → the session is over; end quietly, no summary theater.
        if !Activity<ShoppingActivityAttributes>.activities.isEmpty,
           shoppingBeat.map({ now.timeIntervalSince($0) > Lifetime.shoppingIdle }) ?? true {
            end(.shopping)
            shoppingBeat = nil
        }
        if !Activity<PlantCareActivityAttributes>.activities.isEmpty,
           plantBeat.map({ now.timeIntervalSince($0) > Lifetime.plantIdle }) ?? true {
            end(.plantCare)
            plantBeat = nil
            plantSessionTotal = 0
        }

        // Maintenance: with schedule auto-start retired, an orphan has no
        // driver at all; a driven one still caps at four hours.
        if !Activity<MaintenanceActivityAttributes>.activities.isEmpty,
           maintenanceStartedAt.map({ now.timeIntervalSince($0) > Lifetime.maintenance }) ?? true {
            end(.maintenance)
            maintenanceStartedAt = nil
        }

        // Work session: the 8-hour system limit, honored cleanly by us
        // instead of abruptly by the system.
        if let session = workSessionActivity ?? Activity<WorkSessionActivityAttributes>.activities.first,
           now.timeIntervalSince(session.attributes.startedAt) > Lifetime.systemCap {
            endWorkSession(completed: false)
        }

        // Energy: session cap, or polling went silent — a gauge showing
        // dead numbers as "live" is a lie.
        if let energy = energyActivity ?? Activity<EnergyActivityAttributes>.activities.first {
            let capped = now.timeIntervalSince(energy.attributes.startedAt) > Lifetime.energySession
            let silent = energyBeat.map { now.timeIntervalSince($0) > Lifetime.energyIdle } ?? true
            if capped || silent {
                endEnergySession()
                energyBeat = nil
            }
        }

        // Cover: the IoT flow ends it in seconds; this is pure orphan safety.
        for activity in Activity<CoverActivityAttributes>.activities
        where now.timeIntervalSince(activity.attributes.startedAt) > Lifetime.coverOrphan {
            end(.cover)
        }

        // IoT alerts: sensor state governs them, but nothing alerts for 8
        // hours straight — past the system cap they end cleanly.
        for activity in Activity<IoTAlertActivityAttributes>.activities
        where now.timeIntervalSince(activity.attributes.startedAt) > Lifetime.systemCap {
            end(.iotAlert)
            break
        }

        // Emergency: never swept — it ends when the person says it's over.
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
                for a in Activity<ShoppingActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .shopping, phase: "ended", title: a.attributes.listName)
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                shoppingActivity = nil
            case .delivery:
                for a in Activity<DeliveryActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .delivery, phase: "ended", title: a.attributes.description)
                    await a.end(nil, dismissalPolicy: .immediate)
                    await removeActivityToken(activityId: a.id)
                }
                deliveryActivity = nil
                deliveryParcelId = nil
                deliveryScore = 0
            case .maintenance:
                for a in Activity<MaintenanceActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .maintenance, phase: "ended", title: a.attributes.taskTitle)
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                maintenanceActivity = nil
            case .plantCare:
                for a in Activity<PlantCareActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .plantCare, phase: "ended", title: String(localized: "Plant watering"))
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                plantCareActivity = nil
            case .workSession:
                for a in Activity<WorkSessionActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .workSession, phase: "ended", title: a.attributes.taskTitle)
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                workSessionActivity = nil
            case .emergency:
                for a in Activity<EmergencyActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .emergency, phase: "ended", title: String(localized: "la_emergency_active"))
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                emergencyActivity = nil
            case .iotAlert:
                for a in Activity<IoTAlertActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .iotAlert, phase: "ended", title: a.attributes.sensorName)
                    await a.end(nil, dismissalPolicy: .immediate)
                    await removeActivityToken(activityId: a.id)
                }
                iotAlertActivities.removeAll()
            case .energy:
                for a in Activity<EnergyActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .energy, phase: "ended", title: String(localized: "Energy"))
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                energyActivity = nil
            case .cover:
                for a in Activity<CoverActivityAttributes>.activities {
                    LiveActivityHubStore.record(kind: .cover, phase: "ended", title: a.attributes.deviceName)
                    await a.end(nil, dismissalPolicy: .immediate)
                }
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
        let deliveryScore = self.deliveryScore
        Task {
            for a in Activity<ShoppingActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 0.75),
                                     relevanceScore: Relevance.shopping))
            }
            for a in Activity<MaintenanceActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 2),
                                     relevanceScore: Relevance.maintenance))
            }
            for a in Activity<DeliveryActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 6),
                                     relevanceScore: deliveryScore))
            }
            for a in Activity<PlantCareActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 0.5),
                                     relevanceScore: Relevance.plantCare))
            }
            for a in Activity<WorkSessionActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 8),
                                     relevanceScore: Relevance.workSession))
            }
            for a in Activity<EmergencyActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: nil,
                                     relevanceScore: Relevance.emergency))
            }
            for a in Activity<IoTAlertActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 1),
                                     relevanceScore: a.attributes.isCritical
                                        ? Relevance.iotCritical : Relevance.iotWarning))
            }
            for a in Activity<EnergyActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 0.25),
                                     relevanceScore: Relevance.energy))
            }
            for a in Activity<CoverActivityAttributes>.activities {
                await a.update(.init(state: a.content.state, staleDate: stale(hours: 0.25),
                                     relevanceScore: Relevance.cover))
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

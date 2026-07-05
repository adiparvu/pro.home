import ActivityKit
import Foundation

// Drives real Live Activities from the app's flows: shopping check-offs,
// deliveries, maintenance tasks and plant-watering sessions call the sync
// methods below, and this service starts / updates / ends the system activity
// accordingly — always gated by the user's Live Activity preferences.
@MainActor
final class LiveActivityService: ObservableObject {
    static let shared = LiveActivityService()
    private init() {}

    /// Set by the root view once the primary property is known, so activities
    /// can show the property name (the "Property Name" appearance option).
    var propertyName: String = ""

    // Active activity tokens
    private var shoppingActivity: Activity<ShoppingActivityAttributes>?
    private var maintenanceActivity: Activity<MaintenanceActivityAttributes>?
    private var deliveryActivities: [UUID: Activity<DeliveryActivityAttributes>] = [:]
    private var plantCareActivity: Activity<PlantCareActivityAttributes>?
    private var plantSessionTotal = 0

    private var systemEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private func allowed(_ kind: LiveActivityKind) -> Bool {
        LiveActivityPrefs.isEnabled && LiveActivityPrefs.autoStart(for: kind) && systemEnabled
    }

    // MARK: - Shopping (driven by SupplyService.toggleComplete)

    /// Starts on the first checked item, updates while shopping, ends when done.
    func syncShopping(listName: String, bought: Int, total: Int) {
        guard total > 0 else { return }

        // Adopt an activity that survived an app relaunch.
        if shoppingActivity == nil {
            shoppingActivity = Activity<ShoppingActivityAttributes>.activities.first
        }

        let state = ShoppingActivityAttributes.ContentState(itemsBought: bought, totalItems: total, listName: listName)

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
                Task { await activity.update(.init(state: state, staleDate: nil)) }
            }
        } else if bought > 0, bought < total {
            startShopping(listName: listName, state: state)
        }
    }

    private func startShopping(listName: String, state: ShoppingActivityAttributes.ContentState) {
        guard allowed(.shopping) else { return }
        let attrs = ShoppingActivityAttributes(propertyName: propertyName, listName: listName)
        shoppingActivity = try? Activity.request(
            attributes: attrs, content: .init(state: state, staleDate: nil), pushType: nil)
    }

    // MARK: - Maintenance (driven by TaskService)

    func startMaintenance(taskTitle: String, category: String, step: String? = nil) {
        guard allowed(.maintenance) else { return }
        if maintenanceActivity == nil {
            maintenanceActivity = Activity<MaintenanceActivityAttributes>.activities.first
        }
        guard maintenanceActivity == nil else { return }
        let attrs = MaintenanceActivityAttributes(taskTitle: taskTitle, category: category,
                                                  propertyName: propertyName)
        let state = MaintenanceActivityAttributes.ContentState(
            progress: 0, stepDescription: step ?? String(localized: "In progress"), isComplete: false)
        maintenanceActivity = try? Activity.request(
            attributes: attrs, content: .init(state: state, staleDate: nil), pushType: nil)
    }

    func updateMaintenance(progress: Double, step: String) {
        guard let activity = maintenanceActivity else { return }
        let state = MaintenanceActivityAttributes.ContentState(progress: progress, stepDescription: step, isComplete: false)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
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

    // MARK: - Delivery (driven by DeliveryService add/update)

    /// Reflects a delivery's current state: starts when active, updates status,
    /// ends when delivered / returned / missed.
    func syncDelivery(_ delivery: Delivery) {
        // Adopt activities that survived an app relaunch (matched by tracking id).
        if deliveryActivities[delivery.id] == nil {
            deliveryActivities[delivery.id] = Activity<DeliveryActivityAttributes>.activities.first {
                $0.attributes.trackingNumber == (delivery.trackingNumber ?? "")
                    && $0.attributes.description == delivery.description
            }
        }

        let state = DeliveryActivityAttributes.ContentState(
            status: delivery.status, statusLabel: delivery.statusLabel,
            eta: delivery.expectedDisplay)

        if let activity = deliveryActivities[delivery.id] {
            if delivery.isActive {
                Task { await activity.update(.init(state: state, staleDate: nil)) }
            } else {
                Task { await activity.end(.init(state: state, staleDate: nil),
                                          dismissalPolicy: .after(Date().addingTimeInterval(6))) }
                deliveryActivities.removeValue(forKey: delivery.id)
            }
        } else if delivery.isActive, allowed(.delivery) {
            let attrs = DeliveryActivityAttributes(
                trackingNumber: delivery.trackingNumber ?? "",
                carrier: delivery.carrier ?? String(localized: "Courier"),
                description: delivery.description,
                propertyName: propertyName)
            deliveryActivities[delivery.id] = try? Activity.request(
                attributes: attrs, content: .init(state: state, staleDate: nil), pushType: nil)
        }
    }

    func endDelivery(id: UUID) {
        guard let activity = deliveryActivities[id] else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        deliveryActivities.removeValue(forKey: id)
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
                    attributes: attrs, content: .init(state: state, staleDate: nil), pushType: nil)
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
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        }
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
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let today = fmt.string(from: Date())
            if let due = tasks.first(where: { !$0.isCompleted && ($0.dueDate?.hasPrefix(today) ?? false) }) {
                startMaintenance(taskTitle: due.title, category: due.category,
                                 step: String(localized: "Scheduled for today"))
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
                for a in Activity<DeliveryActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                deliveryActivities.removeAll()
            case .maintenance:
                for a in Activity<MaintenanceActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                maintenanceActivity = nil
            case .plantCare:
                for a in Activity<PlantCareActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                plantCareActivity = nil
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
                await a.update(.init(state: a.content.state, staleDate: nil))
            }
        }
    }
}

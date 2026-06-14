import ActivityKit
import Foundation

@MainActor
final class LiveActivityService: ObservableObject {
    static let shared = LiveActivityService()
    private init() {}

    // Active activity tokens
    private var shoppingActivity: Activity<ShoppingActivityAttributes>?
    private var maintenanceActivity: Activity<MaintenanceActivityAttributes>?
    private var deliveryActivities: [UUID: Activity<DeliveryActivityAttributes>] = [:]
    private var plantCareActivity: Activity<PlantCareActivityAttributes>?

    // MARK: - Shopping

    func startShoppingActivity(listName: String, totalItems: Int, propertyName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = ShoppingActivityAttributes(propertyName: propertyName, listName: listName)
        let state = ShoppingActivityAttributes.ContentState(itemsBought: 0, totalItems: totalItems, listName: listName)
        shoppingActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func updateShopping(bought: Int, total: Int, listName: String) {
        guard let activity = shoppingActivity else { return }
        let state = ShoppingActivityAttributes.ContentState(itemsBought: bought, totalItems: total, listName: listName)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func endShoppingActivity(bought: Int, total: Int, listName: String) {
        guard let activity = shoppingActivity else { return }
        let state = ShoppingActivityAttributes.ContentState(itemsBought: bought, totalItems: total, listName: listName)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(5)))
        }
        shoppingActivity = nil
    }

    // MARK: - Maintenance

    func startMaintenanceActivity(taskTitle: String, category: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = MaintenanceActivityAttributes(taskTitle: taskTitle, category: category)
        let state = MaintenanceActivityAttributes.ContentState(progress: 0, stepDescription: "Început", isComplete: false)
        maintenanceActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func updateMaintenance(progress: Double, step: String) {
        guard let activity = maintenanceActivity else { return }
        let state = MaintenanceActivityAttributes.ContentState(progress: progress, stepDescription: step, isComplete: false)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func completeMaintenanceActivity() {
        guard let activity = maintenanceActivity else { return }
        let state = MaintenanceActivityAttributes.ContentState(progress: 1.0, stepDescription: "Finalizat!", isComplete: true)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4)))
        }
        maintenanceActivity = nil
    }

    // MARK: - Delivery

    func startDeliveryActivity(deliveryId: UUID, trackingNumber: String, carrier: String, description: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard deliveryActivities[deliveryId] == nil else { return }
        let attrs = DeliveryActivityAttributes(trackingNumber: trackingNumber, carrier: carrier, description: description)
        let state = DeliveryActivityAttributes.ContentState(status: "in_transit", statusLabel: "În tranzit", eta: nil)
        deliveryActivities[deliveryId] = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func updateDelivery(deliveryId: UUID, status: String, statusLabel: String, eta: String? = nil) {
        guard let activity = deliveryActivities[deliveryId] else { return }
        let state = DeliveryActivityAttributes.ContentState(status: status, statusLabel: statusLabel, eta: eta)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func endDeliveryActivity(deliveryId: UUID) {
        guard let activity = deliveryActivities[deliveryId] else { return }
        let state = DeliveryActivityAttributes.ContentState(status: "delivered", statusLabel: "Livrat", eta: nil)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(6)))
        }
        deliveryActivities.removeValue(forKey: deliveryId)
    }

    // MARK: - Plant Care

    func startPlantCareActivity(totalCount: Int, propertyName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, totalCount > 0 else { return }
        let attrs = PlantCareActivityAttributes(propertyName: propertyName)
        let state = PlantCareActivityAttributes.ContentState(wateredCount: 0, totalCount: totalCount, lastWateredName: nil)
        plantCareActivity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func updatePlantCare(watered: Int, total: Int, lastWateredName: String?) {
        guard let activity = plantCareActivity else { return }
        let state = PlantCareActivityAttributes.ContentState(wateredCount: watered, totalCount: total, lastWateredName: lastWateredName)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
        if watered >= total {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4)))
            }
            plantCareActivity = nil
        }
    }
}

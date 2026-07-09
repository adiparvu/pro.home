import ActivityKit
import AppIntents
import Foundation
import WidgetKit

// MARK: - Live Activity action intents (Dynamic Island / Lock Screen buttons)
//
// These are the interactive buttons on PRVIO's Live Activities. Every one is a
// `LiveActivityIntent` (+ `AppIntent`), so it is compiled into BOTH the app and
// the widget targets (the widget must SEE the type to render `Button(intent:)`)
// and executes in the app's process.
//
// HONESTY CONTRACT — each button performs a REAL mutation through the exact
// mechanism the existing widget buttons and App Intents already use:
//   1. Enqueue the action onto the App Group queue (SharedDataStore) so the app
//      reconciles it with Supabase on its next foreground beat — the same
//      channel `CompleteTaskIntent`, `WaterPlantIntent`, `CheckSupplyItemIntent`
//      and `CompleteWorkSessionIntent` ride.
//   2. Apply the instant local mutation to the shared catalog/snapshot so the
//      home-screen widgets tick immediately.
//   3. Update / end the running Activity so the island reflects the new state
//      right now (ActivityKit works from this process regardless of app state).
//   4. Post `prvio.processPending` so a foregrounded app drains at once; a
//      backgrounded app drains on its next activation.
//
// They speak ONLY App Group + ActivityKit — never app-target services — so both
// targets compile. (`prvio.processPending` is referenced by its string literal,
// not the `Notification.Name` extension, which lives in the app target only.)

private let processPendingNotification = Notification.Name("prvio.processPending")

// MARK: - Plant care → "Watered"
//
// Waters the next plant that still needs water, read from the shared plant
// catalog (the same source the widgets render). Reuses the established
// mark-watered path (`appendPendingWatering` + `applyLocalWatering`), which the
// app drains into `PlantService.markWatered`.

struct WaterNextPlantIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Water next plant"

    init() {}

    func perform() async throws -> some IntentResult {
        guard let next = SharedDataStore.readPlantCatalog().first(where: { $0.needsWatering }) else {
            return .result()
        }
        HapticFeedback.success()
        SharedDataStore.appendPendingWatering(next.id)
        SharedDataStore.applyLocalWatering(next.id)

        for activity in Activity<PlantCareActivityAttributes>.activities {
            let state = activity.content.state
            let watered = min(state.wateredCount + 1, state.totalCount)
            let newState = PlantCareActivityAttributes.ContentState(
                wateredCount: watered, totalCount: state.totalCount, lastWateredName: next.name)
            if watered >= state.totalCount {
                await activity.end(.init(state: newState, staleDate: nil),
                                   dismissalPolicy: .after(.now + 3))
            } else {
                await activity.update(.init(state: newState, staleDate: nil))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: processPendingNotification, object: nil)
        return .result()
    }
}

// MARK: - Shopping → check off the next item
//
// Acts on the specific, list-scoped item id the app published into the
// ContentState (`nextItemId`). Reuses `appendPendingSupplyCheck` +
// `applyLocalSupplyCheck`; the app drains it into `SupplyService.toggleComplete`
// and republishes the following item, so the button never touches the wrong
// list or double-counts.

struct CheckNextShoppingItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Check off next item"

    @Parameter(title: "Item ID")
    var itemId: String

    init() {}
    init(itemId: UUID) { self.itemId = itemId.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemId) else { return .result() }
        HapticFeedback.impact(.light)
        SharedDataStore.appendPendingSupplyCheck(id)
        SharedDataStore.applyLocalSupplyCheck(id)

        for activity in Activity<ShoppingActivityAttributes>.activities
        where activity.content.state.nextItemId == id {
            let s = activity.content.state
            let bought = min(s.itemsBought + 1, s.totalItems)
            // Clear the pointer: the app republishes the next item on reconcile.
            let newState = ShoppingActivityAttributes.ContentState(
                itemsBought: bought, totalItems: s.totalItems, listName: s.listName,
                nextItemId: nil, nextItemName: nil)
            if bought >= s.totalItems {
                await activity.end(.init(state: newState, staleDate: nil),
                                   dismissalPolicy: .after(.now + 4))
            } else {
                await activity.update(.init(state: newState, staleDate: nil))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: processPendingNotification, object: nil)
        return .result()
    }
}

// MARK: - Delivery → "Mark received"
//
// Marks the specific delivery (matched by the id carried in the attributes)
// delivered. Enqueues onto a dedicated App Group queue the app drains into
// `DeliveryService.markDelivered`; the island flips to Delivered and ends.

struct MarkDeliveryReceivedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark delivery received"

    @Parameter(title: "Delivery ID")
    var deliveryId: String

    init() {}
    init(deliveryId: UUID) { self.deliveryId = deliveryId.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: deliveryId) else { return .result() }
        HapticFeedback.success()
        SharedDataStore.appendPendingDeliveryReceived(id)

        for activity in Activity<DeliveryActivityAttributes>.activities
        where activity.attributes.deliveryId == id {
            let previous = activity.content.state
            let newState = DeliveryActivityAttributes.ContentState(
                status: "delivered",
                statusLabel: String(localized: "Delivered"),
                eta: previous.eta,
                milestoneIndex: 3,
                checkpoint: previous.checkpoint,
                isProblem: false)
            await activity.end(.init(state: newState, staleDate: nil),
                               dismissalPolicy: .after(.now + 4))
        }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: processPendingNotification, object: nil)
        return .result()
    }
}

// MARK: - Maintenance / Task → "Done"
//
// Completes the real task carried in the attributes. Reuses the completion
// queue (`appendPendingCompletion` + `applyLocalTaskCompletion`) the app drains
// into `TaskService.toggleComplete` — identical to `CompleteTaskIntent` and
// `CompleteWorkSessionIntent`.

struct CompleteMaintenanceTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete maintenance task"

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}
    init(taskId: UUID) { self.taskId = taskId.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }
        HapticFeedback.success()
        SharedDataStore.appendPendingCompletion(id)
        SharedDataStore.applyLocalTaskCompletion(id)

        for activity in Activity<MaintenanceActivityAttributes>.activities
        where activity.attributes.taskId == id {
            let newState = MaintenanceActivityAttributes.ContentState(
                progress: 1.0, stepDescription: String(localized: "Done!"), isComplete: true)
            await activity.end(.init(state: newState, staleDate: nil),
                               dismissalPolicy: .after(.now + 2))
        }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: processPendingNotification, object: nil)
        return .result()
    }
}

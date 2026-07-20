import AppIntents
import Foundation

// MARK: - Siri Suggestions donations
//
// Siri Suggestions (Lock Screen, Spotlight, the Siri watch face) learn from
// DONATED actions, not from an app's mere existence. Every real in-app
// action here donates its parameterized AppIntent — the same intents the
// widgets and Shortcuts already execute — so the system can learn the
// household's rhythm ("waters the plants Saturday morning", "checks the
// list at the store") and offer PRVIO at exactly those moments.
//
// Contract:
// - Donations mirror REAL actions only, on their positive direction
//   (completing, watering, checking off) — un-doing an action donates
//   nothing, so suggestions never learn the undo.
// - Fire-and-forget at utility priority: a donation can never slow down or
//   fail the action it mirrors.
// - Acting on a suggestion runs the intent's normal perform() — the same
//   pending-queue mutation the widget buttons use, honest end to end.
enum SiriDonations {
    static func taskCompleted(id: UUID, title: String, priority: String) {
        var intent = CompleteTaskIntent()
        intent.task = TaskEntity(id: id, title: title, priority: priority)
        donate(intent)
    }

    static func plantWatered(id: UUID, name: String, emoji: String) {
        var intent = WaterPlantIntent()
        intent.plant = PlantEntity(id: id, name: name, emoji: emoji)
        donate(intent)
    }

    static func supplyChecked(id: UUID, name: String) {
        var intent = CheckSupplyItemIntent()
        intent.item = SupplyItemEntity(id: id, name: name)
        donate(intent)
    }

    private static func donate(_ intent: some AppIntent) {
        Task.detached(priority: .utility) {
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }
}

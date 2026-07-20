import AppIntents
import Foundation
import WatchKit
import WidgetKit

// MARK: - Siri on the wrist
//
// "Hey Siri, complete my task" / "udă plantele" — hands-free while both
// hands hold the ladder. The intents act on the cached payload (instant,
// offline-capable) and queue the real action through WatchActionRelay, the
// same guaranteed-delivery path the interactive complications use; the
// phone reconciles on the next connectivity beat.

private enum WatchShortcutStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    static func payload() -> WatchPayload? {
        guard let data = defaults.data(forKey: "prvio.watch.payload") else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    static func write(_ payload: WatchPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: "prvio.watch.payload")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct CompleteNextTaskSiriIntent: AppIntent {
    static var title: LocalizedStringResource = "watch_siri_complete_title"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var payload = WatchShortcutStore.payload(),
              let i = payload.tasks.firstIndex(where: { !$0.isCompleted }) else {
            return .result(dialog: IntentDialog("watch_siri_no_tasks"))
        }
        let title = payload.tasks[i].title
        payload.tasks[i].isCompleted = true
        payload.tasks[i].isOverdue = false
        payload.snapshot.openTaskCount = payload.tasks.filter { !$0.isCompleted }.count
        payload.snapshot.overdueTaskCount = payload.tasks.filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
        WatchShortcutStore.write(payload)
        WatchActionRelay.append(action: "completeTask", id: payload.tasks[i].id.uuidString)
        WKInterfaceDevice.current().play(.success)
        return .result(dialog: IntentDialog("watch_siri_completed \(title)"))
    }
}

struct WaterAllPlantsSiriIntent: AppIntent {
    static var title: LocalizedStringResource = "watch_siri_water_title"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var payload = WatchShortcutStore.payload() else {
            return .result(dialog: IntentDialog("watch_siri_no_plants"))
        }
        let thirsty = payload.plants.indices.filter { payload.plants[$0].needsWatering }
        guard !thirsty.isEmpty else {
            return .result(dialog: IntentDialog("watch_siri_no_plants"))
        }
        for i in thirsty {
            payload.plants[i].needsWatering = false
            WatchActionRelay.append(action: "waterPlant", id: payload.plants[i].id.uuidString)
        }
        payload.snapshot.plantsNeedingWater = 0
        payload.snapshot.plantNames = []
        WatchShortcutStore.write(payload)
        WKInterfaceDevice.current().play(.directionUp)
        return .result(dialog: IntentDialog("watch_siri_watered \(thirsty.count)"))
    }
}

struct PRVIOWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteNextTaskSiriIntent(),
            phrases: [
                "Complete my task in \(.applicationName)",
                "Finalizează sarcina în \(.applicationName)",
            ],
            shortTitle: "watch_siri_complete_short",
            systemImageName: "checkmark.circle.fill")
        AppShortcut(
            intent: WaterAllPlantsSiriIntent(),
            phrases: [
                "Water the plants in \(.applicationName)",
                "Udă plantele în \(.applicationName)",
            ],
            shortTitle: "watch_siri_water_short",
            systemImageName: "drop.fill")
    }
}

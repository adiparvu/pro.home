import AppIntents
import Foundation

// MARK: - Water Plant

struct WaterPlantIntent: AppIntent {
    static var title: LocalizedStringResource = "Water plant"
    static var description = IntentDescription("Mark a plant as watered without opening the app")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Plant", description: "The plant to water")
    var plant: PlantEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedDataStore.appendPendingWatering(plant.id)
        return .result(dialog: "\(plant.emoji) \(plant.name) has been watered!")
    }
}

// MARK: - Show Plants

struct ShowPlantsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Plants"
    static var description = IntentDescription("Open the Plants section in PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.showPlants")
        return .result()
    }
}

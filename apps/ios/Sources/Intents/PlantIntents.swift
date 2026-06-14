import AppIntents
import Foundation

// MARK: - Water Plant

struct WaterPlantIntent: AppIntent {
    static var title: LocalizedStringResource = "Udă planta"
    static var description = IntentDescription("Marchează o plantă ca udată fără a deschide aplicația")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Plantă", description: "Planta de udat")
    var plant: PlantEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedDataStore.appendPendingWatering(plant.id)
        return .result(dialog: "\(plant.emoji) \(plant.name) a fost udată!")
    }
}

// MARK: - Show Plants

struct ShowPlantsIntent: AppIntent {
    static var title: LocalizedStringResource = "Deschide Plante"
    static var description = IntentDescription("Deschide secțiunea Plante în PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.showPlants")
        return .result()
    }
}

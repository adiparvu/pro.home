import AppIntents
import Foundation

struct OpenShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Deschide cumpărăturile"
    static var description = IntentDescription("Deschide lista de cumpărături în PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.showShopping")
        return .result()
    }
}

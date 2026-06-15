import AppIntents
import Foundation

struct OpenShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Open shopping list"
    static var description = IntentDescription("Open the shopping list in PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.showShopping")
        return .result()
    }
}

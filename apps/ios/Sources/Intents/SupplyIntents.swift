import AppIntents
import Foundation
import WidgetKit

struct OpenShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Open shopping list"
    static var description = IntentDescription("Open the shopping list in PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.setIntentFlag("prvio.intent.showShopping")
        return .result()
    }
}

// MARK: - Check off a shopping item (widget button / Siri)

struct CheckSupplyItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Check off item"
    static var description = IntentDescription("Mark a shopping item as bought")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", description: "The item to check off")
    var item: SupplyItemEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedDataStore.appendPendingSupplyCheck(item.id)
        // Instant widget feedback; Supabase reconciles on next app foreground.
        SharedDataStore.applyLocalSupplyCheck(item.id)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\"\(item.name)\" checked off.")
    }
}

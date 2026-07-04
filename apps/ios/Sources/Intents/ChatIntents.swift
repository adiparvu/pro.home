import AppIntents
import Foundation

struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Family chat"
    static var description = IntentDescription("Open the chat in PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.setIntentFlag("prvio.intent.showChat")
        return .result()
    }
}

import AppIntents
import Foundation

struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Family chat"
    static var description = IntentDescription("Open family chat in PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.showChat")
        return .result()
    }
}

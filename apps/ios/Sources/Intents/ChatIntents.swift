import AppIntents
import Foundation

struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Chat familie"
    static var description = IntentDescription("Deschide chat-ul familiei în PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.showChat")
        return .result()
    }
}

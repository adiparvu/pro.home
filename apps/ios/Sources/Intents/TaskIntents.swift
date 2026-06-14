import AppIntents
import Foundation

// MARK: - Create Task

struct CreateTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Sarcină nouă"
    static var description = IntentDescription("Deschide PRVIO pentru a crea o sarcină nouă")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.openNewTask")
        return .result()
    }
}

// MARK: - Complete Task

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Finalizează sarcina"
    static var description = IntentDescription("Marchează o sarcină ca finalizată")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Sarcină", description: "Sarcina de finalizat")
    var task: TaskEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedDataStore.appendPendingCompletion(task.id)
        return .result(dialog: "Sarcina \"\(task.title)\" a fost finalizată.")
    }
}

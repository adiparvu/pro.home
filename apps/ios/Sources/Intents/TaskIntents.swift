import AppIntents
import Foundation

// MARK: - Create Task

struct CreateTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "New task"
    static var description = IntentDescription("Opens PRVIO to create a new task")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.openNewTask")
        return .result()
    }
}

// MARK: - Complete Task

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete task"
    static var description = IntentDescription("Mark a task as completed")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task", description: "The task to complete")
    var task: TaskEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedDataStore.appendPendingCompletion(task.id)
        return .result(dialog: "Task \"\(task.title)\" has been completed.")
    }
}

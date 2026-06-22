import Foundation

@MainActor
final class TaskService: ObservableObject {
    @Published var tasks: [MaintenanceTask] = []
    @Published var isLoading = false
    @Published var error: String?

    var openCount: Int {
        tasks.filter { $0.status == "pending" || $0.status == "in_progress" }.count
    }
    var overdueCount: Int {
        tasks.filter { $0.isOverdue || $0.status == "overdue" }.count
    }
    var completedThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return tasks.filter { t in
            guard t.isCompleted else { return false }
            if let d = f.date(from: t.updatedAt) { return d >= weekAgo }
            return false
        }.count
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await supabase
                .from("maintenance_tasks")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTask(_ payload: NewTaskPayload) async throws {
        let new: MaintenanceTask = try await supabase
            .from("maintenance_tasks")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        tasks.insert(new, at: 0)
    }

    func tasks(forElement elementId: UUID) -> [MaintenanceTask] {
        tasks.filter { $0.elementId == elementId }
    }

    /// Link (or unlink, with nil) a task to an object.
    func setElement(_ elementId: UUID?, for task: MaintenanceTask) async {
        struct ElementLink: Encodable {
            let element_id: String?
            let updated_at: String
        }
        do {
            try await supabase
                .from("maintenance_tasks")
                .update(ElementLink(element_id: elementId?.uuidString,
                                    updated_at: ISO8601DateFormatter().string(from: Date())))
                .eq("id", value: task.id.uuidString)
                .execute()
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx].elementId = elementId
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleComplete(_ task: MaintenanceTask) async {
        let newStatus = task.isCompleted ? "pending" : "completed"
        let update = TaskStatusUpdate(
            status: newStatus,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("maintenance_tasks")
                .update(update)
                .eq("id", value: task.id.uuidString)
                .execute()
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx].status = newStatus
                tasks[idx].updatedAt = update.updatedAt
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTask(
        _ task: MaintenanceTask,
        title: String, description: String?,
        dueDate: String?, priority: String, category: String,
        assigneeIds: [String], assigneeNames: [String]
    ) async throws {
        struct TaskFieldUpdate: Encodable {
            let title: String
            let description: String?
            let dueDate: String?
            let priority: String
            let category: String
            let assigneeIds: [String]
            let assigneeNames: [String]
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case title, description, priority, category
                case dueDate       = "due_date"
                case assigneeIds   = "assignee_ids"
                case assigneeNames = "assignee_names"
                case updatedAt     = "updated_at"
            }
        }
        let update = TaskFieldUpdate(
            title: title, description: description,
            dueDate: dueDate, priority: priority, category: category,
            assigneeIds: assigneeIds, assigneeNames: assigneeNames,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await supabase
            .from("maintenance_tasks")
            .update(update)
            .eq("id", value: task.id.uuidString)
            .execute()
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].title = title
            tasks[idx].description = description
            tasks[idx].dueDate = dueDate
            tasks[idx].priority = priority
            tasks[idx].category = category
            tasks[idx].assigneeIds = assigneeIds
            tasks[idx].assigneeNames = assigneeNames
            tasks[idx].updatedAt = update.updatedAt
        }
    }

    func delete(_ task: MaintenanceTask) async {
        do {
            try await supabase
                .from("maintenance_tasks")
                .delete()
                .eq("id", value: task.id.uuidString)
                .execute()
            tasks.removeAll { $0.id == task.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

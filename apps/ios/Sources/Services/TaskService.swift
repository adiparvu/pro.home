import Foundation

@MainActor
final class TaskService: ObservableObject {
    @Published var tasks: [MaintenanceTask] = []
    @Published var isLoading = false

    var openCount: Int {
        tasks.filter { $0.status == "pending" || $0.status == "in_progress" }.count
    }
    var overdueCount: Int {
        tasks.filter { $0.isOverdue || $0.status == "overdue" }.count
    }
    var completedThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
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
            print("[TaskService] load error: \(error)")
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
            print("[TaskService] toggleComplete error: \(error)")
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
            print("[TaskService] delete error: \(error)")
        }
    }
}

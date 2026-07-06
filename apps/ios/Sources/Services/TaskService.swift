import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class TaskService {
    var tasks: [MaintenanceTask] = []
    var isLoading = false
    var error: String?

    private var realtimeChannel: RealtimeChannelV2?
    private var subscribedPropertyId: UUID?
    private var postgresSubs: [RealtimeSubscription] = []
    private var realtimeReload: Task<Void, Never>?

    var openCount: Int {
        tasks.filter { $0.status == "pending" || $0.status == "in_progress" }.count
    }
    var overdueCount: Int {
        tasks.filter { $0.isOverdue || $0.status == "overdue" }.count
    }
    var completedThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return tasks.filter { t in
            guard t.isCompleted else { return false }
            // Tolerant of every server shape (Z / +00:00 / microseconds) —
            // trigger-touched rows previously failed to parse and vanished
            // from this count.
            if let d = AppDate.timestamp(from: t.updatedAt) { return d >= weekAgo }
            return false
        }.count
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if tasks.isEmpty, let cached = ServiceCache.load([MaintenanceTask].self, entity: "tasks", propertyId: pid) {
            tasks = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await PropertyRepo.fetch(table: "maintenance_tasks", propertyId: pid, limit: 500)
            ServiceCache.save(tasks, entity: "tasks", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
        if let pid { await subscribeRealtime(propertyId: pid) }
    }

    // MARK: - Live family sync
    //
    // Any insert/update/delete on this home's tasks re-pulls the list, so a
    // task completed on one phone appears on every other family member's
    // phone in seconds — no pull-to-refresh. Events are coalesced so a burst
    // of changes costs one reload.

    private func subscribeRealtime(propertyId: UUID) async {
        guard subscribedPropertyId != propertyId else { return }
        if let ch = realtimeChannel {
            await supabase.realtimeV2.removeChannel(ch)
            realtimeChannel = nil
            postgresSubs.removeAll()
        }
        let channel = supabase.realtimeV2.channel("maintenance_tasks:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "maintenance_tasks",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRealtimeReload() }
        })
        try? await channel.subscribeWithError()
        realtimeChannel = channel
        subscribedPropertyId = propertyId
    }

    private func scheduleRealtimeReload() {
        realtimeReload?.cancel()
        realtimeReload = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.load()
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
            // Completing a tracked task finishes its Live Activity.
            if newStatus == "completed" {
                LiveActivityService.shared.completeMaintenance(taskTitle: task.title)
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

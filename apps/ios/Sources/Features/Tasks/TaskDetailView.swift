import SwiftUI

// MARK: - Task detail page
//
// The dedicated read-only home of a task — pushed when a row or the hero is
// tapped, and the target of task deep links. Leads with the shared
// TaskGradientCard, then the real actions (complete ⇄ reopen, start session —
// the same WorkSessionStore flow that drives the Live Activity), then the
// facts: status, due date, time worked, cost, description, assignees, notes,
// tags, created/updated. Editing lives behind the toolbar's Edit button
// (and the list's context menu) — never a tap.
//
// The view resolves its task live from TaskService by id, so realtime
// updates from other family members repaint it in place, and a deletion
// elsewhere pops the page instead of stranding a stale copy.

struct TaskDetailView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss

    let taskId: UUID

    @State private var showEdit = false

    private var task: MaintenanceTask? {
        taskService.tasks.first { $0.id == taskId }
    }

    var body: some View {
        Group {
            if let task {
                detail(task)
            } else {
                // Transient state while the deletion-pop below lands.
                Color.clear
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("task_editor_details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
                    .disabled(task == nil)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let task {
                AddTaskView(editing: task)
                    .environment(taskService)
                    .environment(propertyService)
                    .environment(familyService)
            }
        }
        .onChange(of: taskService.tasks) {
            if task == nil { dismiss() }
        }
    }

    // MARK: - Layout

    private func detail(_ task: MaintenanceTask) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                TaskGradientCard(task: task, minHeight: 240)

                actions(task)

                if let desc = task.description?.trimmingCharacters(in: .whitespaces), !desc.isEmpty {
                    infoCard("Description") {
                        Text(verbatim: desc)
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                factsCard(task)

                if !task.assigneeNames.isEmpty {
                    infoCard("task_detail_assignees") {
                        HStack(spacing: AppSpacing.md) {
                            TaskAssigneeAvatars(task: task, size: 30)
                                .environment(familyService)
                            Text(verbatim: task.assigneeNames.joined(separator: ", "))
                                .font(AppFont.footnote)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                            Spacer(minLength: 0)
                        }
                    }
                }

                if let notes = task.notes?.trimmingCharacters(in: .whitespaces), !notes.isEmpty {
                    infoCard("Notes") {
                        Text(verbatim: notes)
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !task.tags.isEmpty {
                    infoCard("Tags") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(task.tags, id: \.self) { tag in
                                    Text(verbatim: tag)
                                        .font(AppFont.captionStrong)
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                        .padding(.horizontal, AppSpacing.md)
                                        .padding(.vertical, 5)
                                        .background(Color.subtleFill, in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 40)
        }
        .animation(.taskSpring, value: task.status)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ task: MaintenanceTask) -> some View {
        VStack(spacing: AppSpacing.sm) {
            if WorkSessionStore.shared.isTiming(task.id) {
                // The pinned banner lives on the list screen; here the
                // compact clock keeps the running session visible.
                HStack {
                    SessionRowTimer()
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.xs)
            } else if !task.isCompleted {
                GlassWideButton(icon: "play.fill", label: "session_start") {
                    WorkSessionStore.shared.start(taskId: task.id, title: task.title)
                }
            }

            GlassWideButton(
                icon: task.isCompleted ? "arrow.uturn.backward" : "checkmark.circle",
                label: LocalizedStringKey(task.isCompleted ? "Reopen" : "Mark as Done")
            ) {
                HapticFeedback.success()
                Task { await taskService.toggleComplete(task) }
            }
        }
    }

    // MARK: - Facts

    private func factsCard(_ task: MaintenanceTask) -> some View {
        GlassCard(padding: AppSpacing.lg, cornerRadius: AppRadius.xl) {
            VStack(spacing: AppSpacing.md) {
                StatRow(label: "Status", value: task.statusDisplay,
                        valueColor: statusColor(task))

                StatRow(label: "task_detail_due", value: dueText(task),
                        valueColor: task.isOverdue ? .brandDanger : .primary)

                if workedTotal(task) > 0 {
                    StatRow(label: "session_worked_total",
                            value: workedTotal(task).workedTotalDisplay)
                }

                if let cost = task.estimatedCost {
                    StatRow(label: "task_detail_cost",
                            value: task.costCurrency.map { "\(cost.formatted()) \($0)" } ?? cost.formatted())
                }

                if let created = AppDate.timestamp(from: task.createdAt) {
                    StatRow(label: "task_detail_created",
                            value: AppDate.medium.string(from: created))
                }

                if let updated = AppDate.timestamp(from: task.updatedAt) {
                    StatRow(label: "Updated",
                            value: AppDate.medium.string(from: updated))
                }
            }
        }
    }

    private func dueText(_ task: MaintenanceTask) -> String {
        guard task.dueDate != nil else { return String(localized: "No date") }
        if let relative = TaskTriage.relativeDueLabel(for: task),
           relative != task.dueDateDisplay {
            return "\(task.dueDateDisplay) · \(relative)"
        }
        return task.dueDateDisplay
    }

    private func statusColor(_ task: MaintenanceTask) -> Color {
        switch task.status {
        case "completed":  return .brandSuccess
        case "overdue":    return .brandDanger
        case "cancelled":  return Color.secondaryTextColor
        default:           return task.isOverdue ? .brandDanger : .brandPurple
        }
    }

    private func workedTotal(_ task: MaintenanceTask) -> TimeInterval {
        max(WorkSessionStore.shared.workedSeconds(for: task.id), TimeInterval(task.workedSeconds))
    }

    // MARK: - Card scaffold

    private func infoCard<Content: View>(_ label: LocalizedStringKey,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            content()
                .padding(AppSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: AppRadius.xl)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

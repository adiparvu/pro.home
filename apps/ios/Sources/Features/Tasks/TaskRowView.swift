import SwiftUI

// MARK: - Task row
//
// The Liquid-Glass task card of the list: leading status dot, title +
// description, category / priority pills, assignee avatars, and a right-aligned
// due-date column with a chevron. Tapping opens the editor; the context menu
// carries the real actions (complete, start session, delete) so behaviour is
// preserved even though the visual checkbox is gone.

struct TaskRowView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    let task: MaintenanceTask
    /// Whether this task is due today / overdue — drives the vivid vs. muted
    /// leading dot, matching the screenshot's "active today" emphasis.
    var isActive: Bool = false

    @State private var showEdit = false

    private var dotColor: Color {
        if task.isCompleted { return .brandSuccess }
        return isActive ? task.priorityStyle.color : Color.primary.opacity(0.22)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: task.isCompleted ? 16 : 9, height: task.isCompleted ? 16 : 9)
                if task.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(AppFont.headline)
                            .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.4) : Color.primary)
                            .strikethrough(task.isCompleted, color: Color.primary.opacity(0.3))
                            .lineLimit(2)
                        if let desc = task.description, !desc.isEmpty {
                            Text(desc)
                                .font(AppFont.footnote)
                                .foregroundStyle(Color.secondaryTextColor)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if task.dueDate != nil {
                        HStack(spacing: 6) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(dueDateShort)
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(task.isOverdue ? Color.brandDanger : Color.primary)
                                Text(relativeDay)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            }
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(12, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.25))
                        }
                    } else {
                        Image(systemName: "chevron.right")
                            .font(AppFont.scaled(12, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.25))
                            .padding(.top, 2)
                    }
                }

                HStack(spacing: 8) {
                    CategoryPill(style: task.categoryStyle)
                    PriorityPill(style: task.priorityStyle)

                    Spacer(minLength: 8)

                    if WorkSessionStore.shared.isTiming(task.id) {
                        SessionRowTimer()
                    }
                    TaskAssigneeAvatars(task: task)
                        .environment(familyService)
                }
            }
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(task.isOverdue ? Color.brandDanger.opacity(0.20) : Color.primary.opacity(AppOpacity.hairline),
                              lineWidth: 0.5)
        )
        .shadow(color: Color.primary.opacity(0.05), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .onTapGesture {
            HapticFeedback.impact(.light)
            showEdit = true
        }
        .contextMenu {
            Button {
                HapticFeedback.impact(.light)
                showEdit = true
            } label: { Label("Edit", systemImage: "pencil") }

            Button {
                HapticFeedback.success()
                Task { await taskService.toggleComplete(task) }
            } label: {
                Label(LocalizedStringKey(task.isCompleted ? "Reopen" : "Mark as Done"),
                      systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
            }

            if !task.isCompleted {
                Button {
                    WorkSessionStore.shared.start(taskId: task.id, title: task.title)
                } label: { Label("session_start", systemImage: "timer") }
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await taskService.delete(task) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .sheet(isPresented: $showEdit) {
            AddTaskView(editing: task)
                .environment(taskService)
                .environment(propertyService)
                .environment(familyService)
        }
    }

    // MARK: - Date helpers

    private var dueDateShort: String {
        guard let ds = task.dueDate, let d = MaintenanceTask.parseDate(ds) else { return "" }
        return AppDate.monthDay.string(from: d).uppercased()
    }

    private var relativeDay: String {
        guard let ds = task.dueDate, let d = MaintenanceTask.parseDate(ds) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d)    { return String(localized: "task_relative_today") }
        if cal.isDateInTomorrow(d) { return String(localized: "task_relative_tomorrow") }
        if cal.isDateInYesterday(d){ return String(localized: "task_relative_yesterday") }
        // Within the next 6 days → weekday name; otherwise the full date.
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                         to: cal.startOfDay(for: d)).day, (0...6).contains(days) {
            return TaskRowView.weekday.string(from: d).capitalized
        }
        return AppDate.monthDayYear.string(from: d)
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()
}

// MARK: - Assignee avatars

/// A compact overlapping stack of the task's assignees. Account-holding family
/// members render their live avatar; everyone else gets a coloured initial.
struct TaskAssigneeAvatars: View {
    @Environment(FamilyService.self) private var familyService
    let task: MaintenanceTask
    var size: CGFloat = 30

    private var overlap: CGFloat { size * 0.36 }

    var body: some View {
        let names = task.assigneeNames
        if !names.isEmpty {
            let shown = Array(names.prefix(3))
            let extra = names.count - shown.count
            HStack(spacing: -overlap) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                    avatar(for: name)
                        .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                }
                if extra > 0 {
                    Text("+\(extra)")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background(Color.gray.opacity(0.8), in: Circle())
                        .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                }
            }
        }
    }

    @ViewBuilder
    private func avatar(for name: String) -> some View {
        if let member = familyService.members.first(where: { $0.name == name }) {
            MemberAvatar(member: member, size: size)
        } else {
            ZStack {
                Circle().fill(Color.brandPrimaryBlue.opacity(0.22))
                Text(String(name.prefix(1)).uppercased())
                    .font(AppFont.scaled(12, weight: .bold))
                    .foregroundStyle(Color.brandPrimaryBlue)
            }
            .frame(width: size, height: size)
        }
    }
}

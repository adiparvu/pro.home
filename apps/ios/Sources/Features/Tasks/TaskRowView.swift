import SwiftUI

// MARK: - Task row
//
// One-hand first: a large leading check circle whose ring carries the
// priority color (the old priority pill is gone), the title, and a single
// metadata line — small category glyph, relative due date, tiny assignee
// avatars. Completing animates a drawn strikethrough before the row settles
// into "Finalizate azi".
//
// Swipes are a lightweight drag gesture rather than `List` swipeActions —
// the screen keeps its `ScrollView` + `LazyVStack` (pinned glass section
// headers, scroll-offset-driven tab bar, free-form hero/progress cards),
// which `List` can't host without fighting UITableView styling. The gesture
// locks to the horizontal axis on its first movement so vertical scrolling
// never stutters. Swipe right = complete, swipe left = snooze to tomorrow;
// both are mirrored as VoiceOver custom actions and context-menu items.

struct TaskRowView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: MaintenanceTask

    @State private var showEdit = false
    /// Local "the strike is drawing" window between the tap and the service
    /// write, so the completion feels instant while staying truthful.
    @State private var completing = false

    // Swipe state
    @State private var dragOffset: CGFloat = 0
    /// nil = direction undecided; true = horizontal (ours); false = vertical (scroll's).
    @State private var dragHorizontal: Bool?
    @State private var crossedThreshold = false

    private let swipeThreshold: CGFloat = 88
    private let swipeTravelCap: CGFloat = 120

    var body: some View {
        card
            .offset(x: dragOffset)
            .background { swipeBackdrop }
            .gesture(swipeGesture, including: task.isCompleted ? .subviews : .all)
            .contextMenu { menuItems }
            .sheet(isPresented: $showEdit) {
                AddTaskView(editing: task)
                    .environment(taskService)
                    .environment(propertyService)
                    .environment(familyService)
            }
    }

    // MARK: - Card

    private var struck: Bool { task.isCompleted || completing }

    private var card: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            TaskCheckCircle(isOn: struck, ringColor: task.priorityStyle.color) {
                task.isCompleted ? reopen() : complete()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(AppFont.headline)
                    .foregroundStyle(struck ? Color.primary.opacity(AppOpacity.disabled) : Color.primary)
                    .strikethrough(task.isCompleted, color: Color.primary.opacity(0.3))
                    .lineLimit(2)
                    .overlay(alignment: .leading) {
                        // The animated strike: draws left→right on completion,
                        // then hands over to the native strikethrough once the
                        // row's state actually flips.
                        if !task.isCompleted {
                            Rectangle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(height: 1.5)
                                .scaleEffect(x: completing ? 1 : 0.001, anchor: .leading)
                                .allowsHitTesting(false)
                        }
                    }
                TaskMetaLine(task: task, muted: struck)
                    .environment(familyService)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(task.isOverdue ? Color.brandDanger.opacity(0.20) : Color.primary.opacity(AppOpacity.hairline),
                              lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .onTapGesture {
            HapticFeedback.impact(.light)
            showEdit = true
        }
        .accessibilityActions { accessibilityMenu }
    }

    // MARK: - Swipe

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 22)
            .onChanged { value in
                if dragHorizontal == nil {
                    dragHorizontal = abs(value.translation.width) > abs(value.translation.height)
                }
                guard dragHorizontal == true else { return }
                dragOffset = rubberBanded(value.translation.width)
                let crossed = abs(value.translation.width) >= swipeThreshold
                if crossed != crossedThreshold {
                    crossedThreshold = crossed
                    if crossed { HapticFeedback.selection() }
                }
            }
            .onEnded { value in
                let wasHorizontal = dragHorizontal == true
                dragHorizontal = nil
                crossedThreshold = false
                guard wasHorizontal else { return }
                let w = value.translation.width
                withAnimation(reduceMotion ? .smooth(duration: 0.15) : .taskSpring) { dragOffset = 0 }
                if w >= swipeThreshold { complete() }
                else if w <= -swipeThreshold { snooze() }
            }
    }

    /// Free travel up to the cap, heavily damped past it — the row resists
    /// like a system swipe instead of flying off screen.
    private func rubberBanded(_ w: CGFloat) -> CGFloat {
        let magnitude = abs(w)
        guard magnitude > swipeTravelCap else { return w }
        let over = magnitude - swipeTravelCap
        return (w < 0 ? -1 : 1) * (swipeTravelCap + over * 0.18)
    }

    /// The tinted action hints revealed behind the card while swiping.
    @ViewBuilder
    private var swipeBackdrop: some View {
        if dragOffset != 0 {
            let completeSide = dragOffset > 0
            let tint: Color = completeSide ? .brandSuccess : .brandIndigo
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(alignment: completeSide ? .leading : .trailing) {
                    HStack(spacing: 6) {
                        Image(systemName: completeSide ? "checkmark.circle.fill" : "moon.zzz.fill")
                            .font(AppFont.scaled(17, weight: .semibold))
                        Text(LocalizedStringKey(completeSide ? "task_stat_completed" : "task_relative_tomorrow"))
                            .font(AppFont.footnoteEmphasis)
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, AppSpacing.xl)
                    .scaleEffect(crossedThreshold ? 1.08 : 1)
                    .animation(.snappy, value: crossedThreshold)
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions

    private func complete() {
        guard !task.isCompleted, !completing else { return }
        HapticFeedback.success()
        withAnimation(reduceMotion ? .smooth(duration: 0.2) : .taskSpring) { completing = true }
        // Let the strike draw before the row migrates to Finalizate.
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 550))
            await taskService.toggleComplete(task)
            completing = false
        }
    }

    private func reopen() {
        guard task.isCompleted else { return }
        HapticFeedback.impact(.light)
        Task { await taskService.toggleComplete(task) }
    }

    private func snooze() {
        guard !task.isCompleted else { return }
        HapticFeedback.impact(.medium)
        let newDue = TaskTriage.snoozedDueDate(for: task)
        Task {
            do {
                try await taskService.updateTask(
                    task,
                    title: task.title,
                    description: task.description,
                    dueDate: newDue,
                    priority: task.priority,
                    category: task.category,
                    assigneeIds: task.assigneeIds,
                    assigneeNames: task.assigneeNames
                )
            } catch {
                taskService.error = error.localizedDescription
            }
        }
    }

    // MARK: - Context menu (unchanged behaviour + snooze)

    @ViewBuilder
    private var menuItems: some View {
        Button {
            HapticFeedback.impact(.light)
            showEdit = true
        } label: { Label("Edit", systemImage: "pencil") }

        Button {
            task.isCompleted ? reopen() : complete()
        } label: {
            Label(LocalizedStringKey(task.isCompleted ? "Reopen" : "Mark as Done"),
                  systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
        }

        if !task.isCompleted {
            Button {
                snooze()
            } label: { Label("task_snooze_tomorrow", systemImage: "moon.zzz") }

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

    /// The swipe actions, restated for VoiceOver users who can't drag.
    @ViewBuilder
    private var accessibilityMenu: some View {
        if task.isCompleted {
            Button("Reopen") { reopen() }
        } else {
            Button("Mark as Done") { complete() }
            Button("task_snooze_tomorrow") { snooze() }
            Button("session_start") { WorkSessionStore.shared.start(taskId: task.id, title: task.title) }
        }
        Button("Edit") { showEdit = true }
    }
}

// MARK: - Check circle
//
// The big tappable completion control shared by the rows and the hero card:
// a priority-colored ring that fills green with a sprung checkmark. The
// visual is generous already; the hit target is padded to ≥44pt regardless.

struct TaskCheckCircle: View {
    let isOn: Bool
    let ringColor: Color
    var size: CGFloat = 30
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? Color.clear : ringColor.opacity(0.85), lineWidth: 2)
                Circle()
                    .fill(Color.brandSuccess)
                    .scaleEffect(isOn ? 1 : 0.001)
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isOn ? 1 : 0.001)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: size, height: size)
            .animation(reduceMotion ? .smooth(duration: 0.15) : .taskSpring, value: isOn)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(isOn ? "Reopen" : "Mark as Done")))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Metadata line
//
// The row's single metadata line — category glyph, relative due date
// (red when overdue), the live session clock when this task is being timed,
// and up to three tiny assignee avatars.

struct TaskMetaLine: View {
    @Environment(FamilyService.self) private var familyService
    let task: MaintenanceTask
    var muted: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: task.categoryStyle.icon)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .accessibilityHidden(true)

            if let due = TaskTriage.relativeDueLabel(for: task) {
                Text(verbatim: due)
                    .font(AppFont.caption)
                    .foregroundStyle(task.isOverdue && !muted ? Color.brandDanger : Color.secondaryTextColor)
            } else {
                Text("task_card_no_due")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
            }

            if WorkSessionStore.shared.isTiming(task.id) {
                SessionRowTimer()
            }

            Spacer(minLength: 8)

            TaskAssigneeAvatars(task: task, size: 20)
                .environment(familyService)
        }
        .opacity(muted ? 0.65 : 1)
        .lineLimit(1)
    }
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
                    Text(verbatim: "+\(extra)")
                        .font(AppFont.scaled(size * 0.38, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background(Color.gray.opacity(0.8), in: Circle())
                        .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: names.joined(separator: ", ")))
        }
    }

    @ViewBuilder
    private func avatar(for name: String) -> some View {
        if let member = familyService.members.first(where: { $0.name == name }) {
            MemberAvatar(member: member, size: size)
        } else {
            ZStack {
                Circle().fill(Color.brandPrimaryBlue.opacity(0.22))
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(AppFont.scaled(size * 0.4, weight: .bold))
                    .foregroundStyle(Color.brandPrimaryBlue)
            }
            .frame(width: size, height: size)
        }
    }
}

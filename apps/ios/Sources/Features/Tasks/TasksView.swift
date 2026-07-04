import SwiftUI

struct TasksView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(DocumentService.self) private var documentService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(AppRouter.self) private var router
    @Environment(FamilyService.self) private var familyService
    @State private var filter: TaskFilter = .all
    @State private var showAdd = false
    @State private var historyPeriod: HistoryPeriod = .month
    /// Task opened by a deep link (notification tap, Spotlight, prvio://tasks/<id>).
    @State private var deepLinkedTask: MaintenanceTask?

    enum TaskFilter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case overdue = "Overdue"
        case done = "Done"

        var icon: String {
            switch self {
            case .all:     return "square.grid.2x2.fill"
            case .open:    return "circle"
            case .overdue: return "exclamationmark.circle.fill"
            case .done:    return "checkmark.circle.fill"
            }
        }
    }

    enum HistoryPeriod: String, CaseIterable {
        case today   = "Today"
        case week    = "7 days"
        case month   = "30 days"
        case quarter = "3 months"
        case year    = "1 year"
        case all     = "All time"

        func apply(to tasks: [MaintenanceTask]) -> [MaintenanceTask] {
            guard self != .all else { return tasks }
            let cutoff = cutoffDate
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return tasks.filter {
                guard let d = f1.date(from: $0.updatedAt) ?? f2.date(from: $0.updatedAt) else { return false }
                return d >= cutoff
            }
        }

        private var cutoffDate: Date {
            let cal = Calendar.current
            switch self {
            case .today:   return cal.startOfDay(for: Date())
            case .week:    return cal.date(byAdding: .day,   value: -7,  to: Date()) ?? Date()
            case .month:   return cal.date(byAdding: .day,   value: -30, to: Date()) ?? Date()
            case .quarter: return cal.date(byAdding: .month, value: -3,  to: Date()) ?? Date()
            case .year:    return cal.date(byAdding: .year,  value: -1,  to: Date()) ?? Date()
            case .all:     return Date.distantPast
            }
        }
    }

    private var filtered: [MaintenanceTask] {
        switch filter {
        case .all:
            return taskService.tasks
        case .open:
            return taskService.tasks.filter { !$0.isCompleted && $0.status != "cancelled" }
        case .overdue:
            return taskService.tasks.filter { $0.isOverdue || $0.status == "overdue" }
        case .done:
            return historyPeriod.apply(to: taskService.tasks.filter { $0.isCompleted })
        }
    }

    var body: some View {
        Group {
            if taskService.isLoading && taskService.tasks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().scaleEffect(1.2)
                    Spacer()
                }
            } else if filtered.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
        .floatingSpeedDial(.tasks)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    CalendarView()
                        .environment(taskService)
                        .environment(documentService)
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.primary.opacity(0.85))
                }
                .accessibilityLabel("Calendar")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(TaskFilter.allCases, id: \.self) { f in
                            Button {
                                withAnimation(.spring(response: 0.25)) { filter = f }
                            } label: {
                                Label(
                                    "\(f.rawValue)  (\(countFor(f)))",
                                    systemImage: filter == f ? "checkmark" : f.icon
                                )
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease" : filter.icon)
                            .font(AppFont.subheadline)
                            .frame(width: 38, height: 32)
                    }
                    .accessibilityLabel("Filter tasks")
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 18)
                    Button {
                        showAdd = true
                        HapticFeedback.impact(.medium)
                    } label: {
                        Image(systemName: "plus")
                            .font(AppFont.subheadline)
                            .frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add task")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTaskView()
                .environment(taskService)
                .environment(propertyService)
        }
        // Deep link: open the specific task the notification / Spotlight / URL
        // pointed at. Resolve on both the id arriving and the task list loading,
        // so it works whether the tab was already open or cold-launched.
        .sheet(item: $deepLinkedTask) { task in
            AddTaskView(editing: task)
                .environment(taskService)
                .environment(propertyService)
                .environment(familyService)
        }
        .onChange(of: router.deepLinkTaskId) { resolveTaskDeepLink() }
        .task(id: taskService.tasks.count) { resolveTaskDeepLink() }
        .alert("Error", isPresented: Binding(
            get: { taskService.error != nil },
            set: { if !$0 { taskService.error = nil } }
        )) {
            Button("OK") { taskService.error = nil }
        } message: {
            Text(taskService.error ?? "")
        }
        .refreshable { await taskService.load() }
        .userActivity("com.prvio.task") { activity in
            activity.title = String(localized: "Tasks — PRVIO")
            activity.userInfo = ["tab": "tasks"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
    }

    private func resolveTaskDeepLink() {
        guard let id = router.deepLinkTaskId,
              let task = taskService.tasks.first(where: { $0.id == id }) else { return }
        deepLinkedTask = task
        router.deepLinkTaskId = nil
    }

    private func countFor(_ f: TaskFilter) -> Int {
        switch f {
        case .all:     return taskService.tasks.count
        case .open:    return taskService.openCount
        case .overdue: return taskService.overdueCount
        case .done:    return taskService.tasks.filter { $0.isCompleted }.count
        }
    }

    // MARK: - Task list

    private var taskList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if filter == .done {
                    historyPeriodBar
                        .padding(.top, AppSpacing.xxs)
                }
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { task in
                        TaskRowView(task: task)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    HapticFeedback.warning()
                                    Task { await taskService.delete(task) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    HapticFeedback.success()
                                    Task { await taskService.toggleComplete(task) }
                                } label: {
                                    Label(LocalizedStringKey(task.isCompleted ? "Reopen" : "Done"),
                                          systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(Color.brandSuccess)
                            }
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xxs)
                .padding(.bottom, 110)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("tasksScroll")).minY)
                }
            )
        }
        .coordinateSpace(name: "tasksScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            tabBarVis.scrollOffset = y
        }
    }

    private var historyPeriodBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryPeriod.allCases, id: \.self) { period in
                    Button {
                        withAnimation(.spring(response: 0.28)) { historyPeriod = period }
                        HapticFeedback.selection()
                    } label: {
                        Text(LocalizedStringKey(period.rawValue))
                            .font(.system(size: 12, weight: historyPeriod == period ? .semibold : .regular))
                            .foregroundStyle(historyPeriod == period ? Color.black : Color.primary.opacity(AppOpacity.emphasis))
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .background(
                                historyPeriod == period ? Color.white : Color.primary.opacity(AppOpacity.subtleFill),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.xs)
        }
    }

    // MARK: - Empty state

    private var emptyTitle: LocalizedStringKey {
        filter == .all ? "No tasks yet" : LocalizedStringKey("No \(filter.rawValue.lowercased()) tasks")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.18))
            Text(emptyTitle)
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.55))
            if filter == .all {
                Button("Add your first task") { showAdd = true }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: LocalizedStringKey
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(AppFont.label)
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : Color.primary.opacity(0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? .black.opacity(0.12) : Color.primary.opacity(0.1), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.black : Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? Color.white : Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    let task: MaintenanceTask

    @State private var showEdit = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                HapticFeedback.success()
                Task { await taskService.toggleComplete(task) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        task.isCompleted
                            ? Color(red: 0.25, green: 0.85, blue: 0.52)
                            : Color.primary.opacity(0.28)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(AppFont.body)
                    .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.38) : Color.primary)
                    .strikethrough(task.isCompleted, color: Color.primary.opacity(0.3))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(LocalizedStringKey(task.category.capitalized))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.38))
                    if task.dueDate != nil {
                        Text("·")
                            .foregroundStyle(Color.primary.opacity(0.22))
                        Text(LocalizedStringKey(task.dueDateDisplay))
                            .font(.system(size: 11))
                            .foregroundStyle(task.isOverdue ? .red.opacity(0.8) : Color.primary.opacity(0.38))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Circle()
                    .fill(task.priorityColor)
                    .frame(width: 7, height: 7)
                if task.isOverdue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.base)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(
                    task.isOverdue ? .red.opacity(0.22) : Color.primary.opacity(AppOpacity.hairline),
                    lineWidth: 0.5
                )
        )
        // Tapping the row (anywhere but the checkbox) opens the task's details.
        // The checkbox Button consumes its own taps, so completion still works.
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.impact(.light)
            showEdit = true
        }
        .contextMenu {
            Button {
                HapticFeedback.impact(.light)
                showEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                HapticFeedback.success()
                Task { await taskService.toggleComplete(task) }
            } label: {
                Label(LocalizedStringKey(task.isCompleted ? "Reopen" : "Mark as Done"),
                      systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await taskService.delete(task) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEdit) {
            AddTaskView(editing: task)
                .environment(taskService)
                .environment(propertyService)
                .environment(familyService)
        }
    }
}

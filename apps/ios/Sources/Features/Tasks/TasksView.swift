import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @State private var filter: TaskFilter = .all
    @State private var showAdd = false
    @State private var historyPeriod: HistoryPeriod = .month

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
                        .environmentObject(taskService)
                        .environmentObject(documentService)
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.primary.opacity(0.85))
                }
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
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 18)
                    Button {
                        showAdd = true
                        HapticFeedback.impact(.medium)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTaskView()
                .environmentObject(taskService)
                .environmentObject(propertyService)
        }
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
            activity.title = "Tasks — PRVIO"
            activity.userInfo = ["tab": "tasks"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
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
                        .padding(.top, 4)
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
                                    Label(task.isCompleted ? "Reopen" : "Done",
                                          systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(Color(red: 0.2, green: 0.78, blue: 0.45))
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
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
                        Text(period.rawValue)
                            .font(.system(size: 12, weight: historyPeriod == period ? .semibold : .regular))
                            .foregroundStyle(historyPeriod == period ? Color.black : Color.primary.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                historyPeriod == period ? Color.white : Color.primary.opacity(0.07),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.18))
            Text(filter == .all ? "No tasks yet" : "No \(filter.rawValue.lowercased()) tasks")
                .font(.system(size: 18, weight: .semibold))
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
    let label: String
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : Color.primary.opacity(0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? .black.opacity(0.12) : Color.primary.opacity(0.1), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.black : Color.primary.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
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

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.38) : Color.primary)
                    .strikethrough(task.isCompleted, color: Color.primary.opacity(0.3))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(task.category.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.38))
                    if task.dueDate != nil {
                        Text("·")
                            .foregroundStyle(Color.primary.opacity(0.22))
                        Text(task.dueDateDisplay)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    task.isOverdue ? .red.opacity(0.22) : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
        )
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
                Label(task.isCompleted ? "Reopen" : "Mark as Done",
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
                .environmentObject(taskService)
                .environmentObject(propertyService)
                .environmentObject(familyService)
        }
    }
}

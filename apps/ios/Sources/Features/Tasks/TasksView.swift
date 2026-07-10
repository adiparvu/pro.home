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
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var collapsed: Set<TaskSectionKind> = []
    @FocusState private var searchFocused: Bool
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

        // ISO8601DateFormatter construction is among Foundation's costliest
        // allocations, and this filter runs twice per render — the
        // formatters must be built once, not per evaluation.
        private static let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private static let isoPlain: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        func apply(to tasks: [MaintenanceTask]) -> [MaintenanceTask] {
            guard self != .all else { return tasks }
            let cutoff = cutoffDate
            return tasks.filter {
                guard let d = Self.isoFractional.date(from: $0.updatedAt)
                    ?? Self.isoPlain.date(from: $0.updatedAt) else { return false }
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
        let base: [MaintenanceTask]
        switch filter {
        case .all:
            base = taskService.tasks
        case .open:
            base = taskService.tasks.filter { !$0.isCompleted && $0.status != "cancelled" }
        case .overdue:
            base = taskService.tasks.filter { $0.isOverdue || $0.status == "overdue" }
        case .done:
            base = historyPeriod.apply(to: taskService.tasks.filter { $0.isCompleted })
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.matchesSearch(searchText)
                || ($0.description ?? "").matchesSearch(searchText)
                || $0.category.matchesSearch(searchText)
                || $0.assigneeNames.contains { $0.matchesSearch(searchText) }
        }
    }

    var body: some View {
        Group {
            if taskService.isLoading && taskService.tasks.isEmpty {
                VStack {
                    header
                    Spacer()
                    ProgressView().scaleEffect(1.2)
                    Spacer()
                }
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        // The running work session stays pinned above the list, always visible
        // however far you scroll — with its live clock, Pause and Finish.
        .safeAreaInset(edge: .top, spacing: 0) { SessionBanner() }
        .animation(.snappy, value: WorkSessionStore.shared.active)
        .navigationDestination(isPresented: $showCalendar) {
            CalendarView()
                .environment(taskService)
                .environment(documentService)
        }
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(isPresented: $showAdd) {
            AddTaskView()
                .environment(taskService)
                .environment(propertyService)
                .environment(familyService)
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

    @State private var showCalendar = false

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                Section {
                    header
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.sm)
                    if showSearch { searchBar }
                    statCards
                        .padding(.horizontal, AppSpacing.xl)
                }

                if filter == .done {
                    Section {
                        historyPeriodBar
                        if filtered.isEmpty {
                            inlineEmpty
                        } else {
                            ForEach(filtered) { task in
                                TaskRowView(task: task, isActive: false)
                                    .environment(taskService)
                                    .environment(propertyService)
                                    .environment(familyService)
                                    .padding(.horizontal, AppSpacing.xl)
                            }
                        }
                    }
                } else if filtered.isEmpty {
                    Section { inlineEmpty }
                } else {
                    ForEach(sections, id: \.kind) { section in
                        Section {
                            if !collapsed.contains(section.kind) {
                                ForEach(section.tasks) { task in
                                    TaskRowView(task: task, isActive: section.kind == .today)
                                        .environment(taskService)
                                        .environment(propertyService)
                                        .environment(familyService)
                                        .padding(.horizontal, AppSpacing.xl)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
            }
            .padding(.bottom, 120)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                           value: geo.frame(in: .named("tasksScroll")).minY)
                }
            )
        }
        .coordinateSpace(name: "tasksScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            tabBarVis.scrollOffset = y
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("task_screen_title")
                    .font(AppFont.title)
                    .foregroundStyle(.primary)
                Text("task_subtitle")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            Spacer()
            HStack(spacing: 10) {
                headerButton("magnifyingglass", label: "Search") {
                    withAnimation(.taskSpring) { showSearch.toggle() }
                    searchFocused = showSearch
                    if !showSearch { searchText = "" }
                }
                Menu {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Button {
                            withAnimation(.taskSpring) { filter = f }
                        } label: {
                            Label("\(f.rawValue)  (\(countFor(f)))",
                                  systemImage: filter == f ? "checkmark" : f.icon)
                        }
                    }
                } label: {
                    headerButtonLabel("slider.horizontal.3")
                }
                .accessibilityLabel("Filter tasks")

                Menu {
                    Button { showCalendar = true } label: { Label("Calendar", systemImage: "calendar") }
                    Button { Task { await taskService.load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                } label: {
                    headerButtonLabel("ellipsis")
                }
                .accessibilityLabel("More")
            }
            .padding(.top, 6)
        }
    }

    private func headerButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            headerButtonLabel(icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func headerButtonLabel(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(AppFont.scaled(17, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.8))
            .frame(width: 44, height: 44)
            .glassCircle()
            .shadow(color: Color.primary.opacity(0.05), radius: 8, y: 3)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.footnote)
                .foregroundStyle(Color.secondaryTextColor)
            TextField(text: $searchText) {
                Text("Search…")
            }
            .focused($searchFocused)
            .font(AppFont.body)
            .tint(.accentColor)
            .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .liquidGlass(cornerRadius: AppRadius.md)
        .padding(.horizontal, AppSpacing.xl)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Stat cards

    private var statCards: some View {
        HStack(spacing: 10) {
            TaskStatCard(icon: "checklist", tint: .brandSuccess,
                         value: taskService.tasks.count, label: "task_stat_all",
                         isSelected: filter == .all) { select(.all) }
            TaskStatCard(icon: "circle.dotted", tint: .brandPurple,
                         value: taskService.openCount, label: "task_stat_in_progress",
                         isSelected: filter == .open) { select(.open) }
            TaskStatCard(icon: "clock.fill", tint: .brandWarning,
                         value: taskService.overdueCount, label: "task_stat_overdue",
                         isSelected: filter == .overdue) { select(.overdue) }
            TaskStatCard(icon: "checkmark.seal.fill", tint: .brandTeal,
                         value: taskService.tasks.filter { $0.isCompleted }.count, label: "task_stat_completed",
                         isSelected: filter == .done) { select(.done) }
        }
    }

    private func select(_ f: TaskFilter) {
        HapticFeedback.selection()
        withAnimation(.taskSpring) { filter = (filter == f && f != .all) ? .all : f }
    }

    // MARK: - Section header

    private func sectionHeader(_ section: TaskSection) -> some View {
        Button {
            HapticFeedback.impact(.light)
            withAnimation(.taskSpring) {
                if collapsed.contains(section.kind) { collapsed.remove(section.kind) }
                else { collapsed.insert(section.kind) }
            }
        } label: {
            HStack {
                Text(section.kind.title)
                    .font(AppFont.title3)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Text("task_see_all")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.secondaryTextColor)
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                        .rotationEffect(.degrees(collapsed.contains(section.kind) ? 90 : 0))
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
            .background(appBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouping

    private struct TaskSection { let kind: TaskSectionKind; let tasks: [MaintenanceTask] }

    private var sections: [TaskSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: today) else { return [] }

        var todayTasks: [MaintenanceTask] = []
        var weekTasks: [MaintenanceTask] = []
        var laterTasks: [MaintenanceTask] = []

        for task in filtered {
            guard let ds = task.dueDate, let due = MaintenanceTask.parseDate(ds) else {
                laterTasks.append(task); continue
            }
            let day = cal.startOfDay(for: due)
            if day <= today { todayTasks.append(task) }        // today or overdue
            else if day < weekEnd { weekTasks.append(task) }
            else { laterTasks.append(task) }
        }

        return [
            TaskSection(kind: .today, tasks: todayTasks),
            TaskSection(kind: .week,  tasks: weekTasks),
            TaskSection(kind: .later, tasks: laterTasks)
        ].filter { !$0.tasks.isEmpty }
    }

    // MARK: - History bar (completed filter)

    private var historyPeriodBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryPeriod.allCases, id: \.self) { period in
                    GlassFilterChip(label: String(localized: String.LocalizationValue(period.rawValue)),
                                    isSelected: historyPeriod == period) {
                        withAnimation(.taskSpring) { historyPeriod = period }
                        HapticFeedback.selection()
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.xs)
        }
    }

    // MARK: - Empty state

    private var inlineEmpty: some View {
        EmptyStateView(
            icon: "checklist",
            title: filter == .all ? "No tasks yet" : LocalizedStringKey("No \(filter.rawValue.lowercased()) tasks"),
            actionLabel: filter == .all ? "Add your first task" : nil,
            action: filter == .all ? { showAdd = true } : nil
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Floating add button

    private var addButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            showAdd = true
        } label: {
            Image(systemName: "plus")
                .font(AppFont.scaled(22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(colors: [Color.brandPurple, Color.brandPurple.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: Color.brandPurple.opacity(0.5), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, AppSpacing.xl)
        .padding(.bottom, 22)
        .accessibilityLabel("Add task")
    }

    // MARK: - Helpers

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
}

// MARK: - Section kind

enum TaskSectionKind: Hashable {
    case today, week, later

    var title: LocalizedStringKey {
        switch self {
        case .today: return "task_section_today"
        case .week:  return "task_section_week"
        case .later: return "task_section_later"
        }
    }
}

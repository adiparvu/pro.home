import SwiftUI

// MARK: - Tasks screen
//
// Not a pretty list — an assistant that tells you what's next. The page
// leads with the "Acum" hero (the single most actionable task, ranked by
// TaskTriage), a slim progress line ("X din Y azi" + the three filter
// chips), then the temporal sections (Astăzi / Săptămâna aceasta / Mai
// târziu, sticky and collapsible) and a collapsed "Finalizate azi" at the
// bottom. All business logic — TaskService, WorkSessionStore, deep links,
// realtime, calendar/reminders sync — is untouched; only the surface moved.

struct TasksView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(DocumentService.self) private var documentService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(AppRouter.self) private var router
    @Environment(FamilyService.self) private var familyService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: TaskFilter = .all
    @State private var showAdd = false
    @State private var historyPeriod: HistoryPeriod = .month
    @State private var searchText = ""
    @State private var showSearch = false
    /// "Finalizate azi" starts folded — it's a receipt, not a to-do.
    @State private var collapsed: Set<TaskSectionKind> = [.doneToday]
    /// Position in the hero shortlist ("următorul" cycles through it).
    @State private var heroIndex = 0
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

    // MARK: - Filtering (one system: chips, the header menu and search all
    // drive this same state)

    private var filtered: [MaintenanceTask] {
        let base: [MaintenanceTask]
        switch filter {
        case .all:
            // The default view plans the open work; finished items live in
            // "Finalizate azi" below and under the Finalizate chip.
            base = taskService.tasks.filter { !$0.isCompleted && $0.status != "cancelled" }
        case .open:
            base = taskService.tasks.filter { !$0.isCompleted && $0.status != "cancelled" }
        case .overdue:
            base = taskService.tasks.filter { $0.isOverdue || $0.status == "overdue" }
        case .done:
            base = historyPeriod.apply(to: taskService.tasks.filter { $0.isCompleted })
        }
        return applySearch(to: base)
    }

    private func applySearch(to tasks: [MaintenanceTask]) -> [MaintenanceTask] {
        guard !searchText.isEmpty else { return tasks }
        return tasks.filter {
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
        // The user's configurable speed dial (the "P cu acoperiș" floating
        // button with quick actions) — explicitly preferred over a plain
        // purple "+" FAB.
        .floatingSpeedDial(.tasks)
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
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                list
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
            .onChange(of: router.deepLinkTaskId) { resolveTaskDeepLink(proxy) }
            .task(id: taskService.tasks.count) { resolveTaskDeepLink(proxy) }
        }
    }

    private var list: some View {
        // The hero only exists in the default, unfiltered view — don't rank
        // the shortlist at all while a chip or a search narrows the list.
        let candidates = (filter == .all && searchText.isEmpty)
            ? TaskTriage.heroCandidates(in: taskService.tasks) : []
        let hero = candidates.isEmpty ? nil : candidates[heroIndex % candidates.count]
        let openSections = sections(excluding: hero?.id)
        let doneToday = filter == .all ? applySearch(to: doneTodayTasks) : []

        return LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
            Section {
                header
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                if showSearch { searchBar }
                progressLine
                    .padding(.horizontal, AppSpacing.xl)
                heroArea(hero: hero, candidates: candidates,
                         hasAnythingBelow: !openSections.isEmpty || !doneToday.isEmpty)
            }

            if filter == .done {
                Section {
                    historyPeriodBar
                    if filtered.isEmpty {
                        inlineEmpty
                    } else {
                        ForEach(filtered) { task in
                            taskRow(task)
                        }
                    }
                }
            } else if openSections.isEmpty && doneToday.isEmpty && hero == nil {
                Section { inlineEmpty }
            } else {
                ForEach(openSections, id: \.kind) { section in
                    Section {
                        if !collapsed.contains(section.kind) {
                            ForEach(section.tasks) { task in
                                taskRow(task)
                                    .transition(reduceMotion
                                                ? .opacity
                                                : .move(edge: .top).combined(with: .opacity))
                            }
                        }
                    } header: {
                        sectionHeader(kind: section.kind)
                    }
                }

                if !doneToday.isEmpty {
                    Section {
                        if !collapsed.contains(.doneToday) {
                            ForEach(doneToday) { task in
                                taskRow(task)
                                    .transition(reduceMotion
                                                ? .opacity
                                                : .move(edge: .top).combined(with: .opacity))
                            }
                        }
                    } header: {
                        sectionHeader(kind: .doneToday, count: doneToday.count)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .taskSpring, value: taskService.tasks)
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        TaskRowView(task: task)
            .environment(taskService)
            .environment(propertyService)
            .environment(familyService)
            .padding(.horizontal, AppSpacing.xl)
            .id(task.id)
    }

    // MARK: - Hero ("Acum")

    @ViewBuilder
    private func heroArea(hero: MaintenanceTask?, candidates: [MaintenanceTask],
                          hasAnythingBelow: Bool) -> some View {
        if let hero {
            TaskHeroCard(task: hero, candidateCount: candidates.count) { delta in
                advanceHero(delta, count: candidates.count)
            }
            .environment(taskService)
            .environment(propertyService)
            .environment(familyService)
            .id(hero.id)
            .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                      removal: .move(edge: .leading).combined(with: .opacity)))
            .padding(.horizontal, AppSpacing.xl)
        } else if filter == .all, searchText.isEmpty, hasAnythingBelow {
            // Nothing on today's plate but the list still has content below —
            // say so, with the real house streak, instead of an abrupt gap.
            TaskAllClearCard { showAdd = true }
                .padding(.horizontal, AppSpacing.xl)
        }
    }

    private func advanceHero(_ delta: Int, count: Int) {
        guard count > 1 else { return }
        withAnimation(reduceMotion ? .smooth(duration: 0.2) : .taskSpring) {
            heroIndex = ((heroIndex % count) + delta + count) % count
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

    // MARK: - Progress line

    private var progressLine: some View {
        TaskProgressLine(
            doneToday: completedTodayCount,
            plateToday: todayPlateCount,
            chips: [
                .init(id: "overdue", label: "task_stat_overdue",
                      count: taskService.overdueCount, tint: .brandWarning,
                      isSelected: filter == .overdue) { select(.overdue) },
                .init(id: "open", label: "task_stat_in_progress",
                      count: taskService.openCount, tint: .brandPurple,
                      isSelected: filter == .open) { select(.open) },
                .init(id: "done", label: "task_stat_completed",
                      count: completedCount, tint: .brandTeal,
                      isSelected: filter == .done) { select(.done) }
            ]
        )
    }

    private var completedCount: Int {
        taskService.tasks.filter { $0.isCompleted }.count
    }

    private var completedTodayCount: Int { doneTodayTasks.count }

    /// Today's plate: everything already finished today plus everything
    /// still actionable today — so "3 din 5 azi" reads as real progress.
    private var todayPlateCount: Int {
        completedTodayCount + taskService.tasks.filter { TaskTriage.isActionableToday($0) }.count
    }

    private var doneTodayTasks: [MaintenanceTask] {
        taskService.tasks
            .filter { TaskTriage.isCompletedToday($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func select(_ f: TaskFilter) {
        withAnimation(.taskSpring) { filter = (filter == f && f != .all) ? .all : f }
    }

    // MARK: - Section header

    private func sectionHeader(kind: TaskSectionKind, count: Int? = nil) -> some View {
        Button {
            HapticFeedback.impact(.light)
            withAnimation(.taskSpring) {
                if collapsed.contains(kind) { collapsed.remove(kind) }
                else { collapsed.insert(kind) }
            }
        } label: {
            HStack {
                Text(kind.title)
                    .font(AppFont.title3)
                    .foregroundStyle(kind == .doneToday ? Color.secondaryTextColor : Color.primary)
                Spacer()
                HStack(spacing: 6) {
                    if let count {
                        Text(verbatim: "\(count)")
                            .font(AppFont.captionStrong)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Color.secondaryTextColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.subtleFill, in: Capsule())
                    } else {
                        Text("task_see_all")
                            .font(AppFont.footnote)
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                        .rotationEffect(.degrees(collapsed.contains(kind) ? 90 : 0))
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
            .background(appBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Grouping

    private struct TaskSection { let kind: TaskSectionKind; let tasks: [MaintenanceTask] }

    /// Temporal grouping of the open work; the task featured in the hero is
    /// excluded so it never appears twice on screen.
    private func sections(excluding heroId: UUID?) -> [TaskSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: today) else { return [] }

        var todayTasks: [MaintenanceTask] = []
        var weekTasks: [MaintenanceTask] = []
        var laterTasks: [MaintenanceTask] = []

        for task in filtered where task.id != heroId {
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

    @ViewBuilder
    private var inlineEmpty: some View {
        if !searchText.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "No results")
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if filter == .all {
            if taskService.tasks.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: "No tasks yet",
                    actionLabel: "Add your first task",
                    action: { showAdd = true }
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                // Everything's handled: the all-clear voice, with the real
                // house streak when there is one.
                let streak = SharedDataStore.currentHouseStreak()
                EmptyStateView(
                    icon: "checkmark.seal.fill",
                    title: "task_empty_all_clear",
                    message: streak > 0 ? "task_empty_streak \(streak)" : nil,
                    actionLabel: "task_empty_add_hint",
                    action: { showAdd = true }
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            EmptyStateView(
                icon: "checklist",
                title: LocalizedStringKey("No \(filter.rawValue.lowercased()) tasks")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    // MARK: - Helpers

    /// Scrolls to the deep-linked task (the hero and every row share
    /// `.id(task.id)`, so both are valid targets) and opens its editor.
    private func resolveTaskDeepLink(_ proxy: ScrollViewProxy) {
        guard let id = router.deepLinkTaskId,
              let task = taskService.tasks.first(where: { $0.id == id }) else { return }
        router.deepLinkTaskId = nil
        withAnimation(reduceMotion ? nil : .taskSpring) {
            proxy.scrollTo(id, anchor: .center)
        }
        // Present after the scroll settles so the sheet rises from context.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            deepLinkedTask = task
        }
    }

    private func countFor(_ f: TaskFilter) -> Int {
        switch f {
        case .all:     return taskService.tasks.count
        case .open:    return taskService.openCount
        case .overdue: return taskService.overdueCount
        case .done:    return completedCount
        }
    }
}

// MARK: - Section kind

enum TaskSectionKind: Hashable {
    case today, week, later, doneToday

    var title: LocalizedStringKey {
        switch self {
        case .today:     return "task_section_today"
        case .week:      return "task_section_week"
        case .later:     return "task_section_later"
        case .doneToday: return "task_section_done_today"
        }
    }
}

import AppIntents
import WidgetKit

// MARK: - Home-screen widget configuration (edit-widget sheet)
//
// AppIntentConfiguration replaces the static Tasks/Plants configurations so a
// long-press → Edit Widget offers real choices. Every option filters the SAME
// App Group catalogs the static widgets already render — nothing is invented,
// and the catalogs are written untruncated, so filtered counts stay honest.
// Widgets placed before this change keep working: a StaticConfiguration kind
// migrated to AppIntentConfiguration renders with the intent's defaults.

// MARK: Tasks

enum TaskPriorityFilter: String, AppEnum {
    case all, high, medium, low

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"
    static var caseDisplayRepresentations: [TaskPriorityFilter: DisplayRepresentation] = [
        .all: "All", .high: "High", .medium: "Medium", .low: "Low",
    ]

    /// Raw `priority` value in TaskCatalogEntry, nil when no filtering applies.
    var rawPriority: String? {
        self == .all ? nil : rawValue
    }
}

struct TasksWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Tasks Widget"
    static var description = IntentDescription("Choose which tasks the widget shows.")

    @Parameter(title: "Priority", default: .all)
    var priority: TaskPriorityFilter

    @Parameter(title: "Overdue only", default: false)
    var overdueOnly: Bool

    /// The configured slice of the task catalog, still pending-first.
    func filter(_ catalog: [TaskCatalogEntry]) -> [TaskCatalogEntry] {
        catalog.filter { task in
            guard !task.isCompleted else { return false }
            if overdueOnly, task.isOverdue != true { return false }
            if let wanted = priority.rawPriority, task.priority != wanted { return false }
            return true
        }
    }

    var isFiltering: Bool { overdueOnly || priority != .all }
}

struct TasksConfigProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PRVIOWidgetEntry {
        PRVIOTimelineProvider().makeEntry()
    }

    func snapshot(for configuration: TasksWidgetConfigIntent, in context: Context) async -> PRVIOWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: TasksWidgetConfigIntent, in context: Context) async -> Timeline<PRVIOWidgetEntry> {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        return Timeline(entries: [entry(for: configuration)], policy: .after(next))
    }

    private func entry(for configuration: TasksWidgetConfigIntent) -> PRVIOWidgetEntry {
        var entry = PRVIOTimelineProvider().makeEntry()
        entry.tasksConfig = configuration
        return entry
    }
}

// MARK: Plants

struct PlantsWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Plants Widget"
    static var description = IntentDescription("Choose which plants the widget shows.")

    @Parameter(title: "Show healthy plants too", default: false)
    var includeHealthy: Bool
}

struct PlantsConfigProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PRVIOWidgetEntry {
        PRVIOTimelineProvider().makeEntry()
    }

    func snapshot(for configuration: PlantsWidgetConfigIntent, in context: Context) async -> PRVIOWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: PlantsWidgetConfigIntent, in context: Context) async -> Timeline<PRVIOWidgetEntry> {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        return Timeline(entries: [entry(for: configuration)], policy: .after(next))
    }

    private func entry(for configuration: PlantsWidgetConfigIntent) -> PRVIOWidgetEntry {
        var entry = PRVIOTimelineProvider().makeEntry()
        entry.plantsConfig = configuration
        return entry
    }
}

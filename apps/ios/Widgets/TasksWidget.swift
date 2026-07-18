import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Tasks Widget

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        // Configurable (Edit Widget): priority + overdue-only filters over the
        // same catalog the static widget rendered. Placed widgets migrate with
        // the intent's defaults, which reproduce the unfiltered widget.
        AppIntentConfiguration(kind: kind, intent: TasksWidgetConfigIntent.self,
                               provider: TasksConfigProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_tasks_name", comment: ""))
        .description(NSLocalizedString("widget_tasks_desc", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Small View

struct TasksWidgetSmallView: View {
    let entry: PRVIOWidgetEntry

    /// Counts honor the configured filter; the default configuration falls
    /// back to the snapshot's authoritative totals (identical pre-config look).
    private var counts: (open: Int, overdue: Int) {
        if let cfg = entry.tasksConfig, cfg.isFiltering {
            let filtered = cfg.filter(entry.taskCatalog)
            return (filtered.count, filtered.filter { $0.isOverdue ?? false }.count)
        }
        return (entry.snapshot.openTaskCount, entry.snapshot.overdueTaskCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .font(AppFont.headline)
                    .foregroundStyle(.blue)
                Spacer()
                if counts.overdue > 0 {
                    Text("\(counts.overdue)")
                        .font(AppFont.scaled(28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(24))
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(counts.overdue > 0
                     ? NSLocalizedString("widget_overdue_label", comment: "")
                     : NSLocalizedString("widget_tasks_label", comment: ""))
                    .font(AppFont.scaled(9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(counts.overdue > 0
                     ? "\(counts.overdue) \(NSLocalizedString("widget_overdue", comment: ""))"
                     : "\(counts.open) \(NSLocalizedString("widget_open", comment: ""))")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .moodContainerBackground()
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: - Medium View

struct TasksMediumView: View {
    let entry: PRVIOWidgetEntry

    var pendingTasks: [TaskCatalogEntry] {
        let pending = entry.tasksConfig?.filter(entry.taskCatalog)
            ?? entry.taskCatalog.filter { !$0.isCompleted }
        return pending.prefix(3).map { $0 }
    }

    private func makeCompleteTaskIntent(id: UUID, title: String, priority: String) -> CompleteTaskIntent {
        var i = CompleteTaskIntent()
        i.task = TaskEntity(id: id, title: title, priority: priority)
        return i
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("TASKS")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checklist")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.blue)
                }
                Spacer()
                if entry.snapshot.overdueTaskCount > 0 {
                    Text(String(format: String(localized: "%d overdue"), entry.snapshot.overdueTaskCount))
                        .font(AppFont.label)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
            }

            if pendingTasks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All tasks are complete!")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendingTasks, id: \.id) { task in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(task.priority == "high" ? Color.red : task.priority == "medium" ? Color.orange : Color.blue)
                                .frame(width: 6, height: 6)
                            Text(task.title)
                                .font(AppFont.scaled(13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Button(intent: makeCompleteTaskIntent(id: task.id, title: task.title, priority: task.priority)) {
                                Image(systemName: "circle")
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .moodContainerBackground()
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: - Dispatcher

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:  TasksWidgetSmallView(entry: entry)
        case .systemMedium: TasksMediumView(entry: entry)
        default:            TasksWidgetSmallView(entry: entry)
        }
    }
}

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Tasks Widget

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer()
                if entry.snapshot.overdueTaskCount > 0 {
                    Text("\(entry.snapshot.overdueTaskCount)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.overdueTaskCount > 0
                     ? NSLocalizedString("widget_overdue_label", comment: "")
                     : NSLocalizedString("widget_tasks_label", comment: ""))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(entry.snapshot.overdueTaskCount > 0
                     ? "\(entry.snapshot.overdueTaskCount) \(NSLocalizedString("widget_overdue", comment: ""))"
                     : "\(entry.snapshot.openTaskCount) \(NSLocalizedString("widget_open", comment: ""))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://tasks"))
    }
}

// MARK: - Medium View

struct TasksMediumView: View {
    let entry: PRVIOWidgetEntry

    var pendingTasks: [TaskCatalogEntry] {
        entry.taskCatalog.filter { !$0.isCompleted }.prefix(3).map { $0 }
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                Spacer()
                if entry.snapshot.overdueTaskCount > 0 {
                    Text(String(format: String(localized: "%d overdue"), entry.snapshot.overdueTaskCount))
                        .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 13))
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
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Button(intent: makeCompleteTaskIntent(id: task.id, title: task.title, priority: task.priority)) {
                                Image(systemName: "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
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

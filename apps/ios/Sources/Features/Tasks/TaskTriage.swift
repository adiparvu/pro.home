import Foundation

// MARK: - Task triage
//
// The pure decision core behind the "assistant" Tasks page: which single task
// deserves the hero spot, what "done today" means, and where a snoozed task
// lands. No UI, no service calls — just deterministic functions over
// `MaintenanceTask`, so the hero, the progress line and the rows all agree on
// one definition of "actionable" and the logic stays unit-testable.

enum TaskTriage {

    // MARK: Actionability

    /// A task is on today's plate when it is open (not completed/cancelled)
    /// and either overdue or due today.
    static func isActionableToday(_ task: MaintenanceTask, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard !task.isCompleted, task.status != "cancelled" else { return false }
        guard let ds = task.dueDate, let due = MaintenanceTask.parseDate(ds) else { return false }
        return calendar.startOfDay(for: due) <= calendar.startOfDay(for: now)
    }

    /// The hero's ordered shortlist: every task actionable today, ranked
    /// overdue first → due today → highest priority → earliest due date,
    /// with the id as a stable final tiebreak so the order never flickers
    /// between renders.
    static func heroCandidates(in tasks: [MaintenanceTask], calendar: Calendar = .current, now: Date = Date()) -> [MaintenanceTask] {
        let today = calendar.startOfDay(for: now)
        return tasks
            .filter { isActionableToday($0, calendar: calendar, now: now) }
            .sorted { a, b in
                let aOverdue = dueDay(of: a, calendar: calendar).map { $0 < today } ?? false
                let bOverdue = dueDay(of: b, calendar: calendar).map { $0 < today } ?? false
                if aOverdue != bOverdue { return aOverdue }

                let ap = priorityRank(a), bp = priorityRank(b)
                if ap != bp { return ap > bp }

                let ad = dueDay(of: a, calendar: calendar) ?? .distantFuture
                let bd = dueDay(of: b, calendar: calendar) ?? .distantFuture
                if ad != bd { return ad < bd }

                return a.id.uuidString < b.id.uuidString
            }
    }

    // MARK: Today's tally (the progress line)

    /// Completed today — status is `completed` and the completing update
    /// happened today (tolerant of every server timestamp shape).
    static func isCompletedToday(_ task: MaintenanceTask, calendar: Calendar = .current) -> Bool {
        guard task.isCompleted, let d = AppDate.timestamp(from: task.updatedAt) else { return false }
        return calendar.isDateInToday(d)
    }

    // MARK: Snooze

    /// Where "snooze to tomorrow" moves a task: the start of tomorrow,
    /// keeping the original time of day when the task had one. Returns the
    /// wire string in the exact format the editor's save path writes
    /// (`yyyy-MM-dd` or `yyyy-MM-dd HH:mm`), so the update path stays uniform.
    static func snoozedDueDate(for task: MaintenanceTask, calendar: Calendar = .current, now: Date = Date()) -> String {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let hadTime = (task.dueDate?.count ?? 0) > 10
        guard hadTime,
              let ds = task.dueDate, let original = MaintenanceTask.parseDate(ds) else {
            return AppDate.day.string(from: tomorrow)
        }
        let time = calendar.dateComponents([.hour, .minute], from: original)
        var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = time.hour
        comps.minute = time.minute
        return AppDate.dayTime.string(from: calendar.date(from: comps) ?? tomorrow)
    }

    // MARK: Shared display helpers

    /// One relative-due phrase shared by the hero and the rows: Today /
    /// Tomorrow / Yesterday, a weekday within the week, else the short date.
    static func relativeDueLabel(for task: MaintenanceTask, calendar: Calendar = .current, now: Date = Date()) -> String? {
        guard let ds = task.dueDate, let d = MaintenanceTask.parseDate(ds) else { return nil }
        if calendar.isDateInToday(d)     { return String(localized: "task_relative_today") }
        if calendar.isDateInTomorrow(d)  { return String(localized: "task_relative_tomorrow") }
        if calendar.isDateInYesterday(d) { return String(localized: "task_relative_yesterday") }
        if let days = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: now),
                                              to: calendar.startOfDay(for: d)).day,
           (0...6).contains(days) {
            return weekday.string(from: d).capitalized
        }
        return AppDate.monthDayYear.string(from: d)
    }

    // MARK: Private

    private static func priorityRank(_ task: MaintenanceTask) -> Int {
        TaskPriorityStyle.order.firstIndex(of: task.priority) ?? 1
    }

    private static func dueDay(of task: MaintenanceTask, calendar: Calendar) -> Date? {
        guard let ds = task.dueDate, let d = MaintenanceTask.parseDate(ds) else { return nil }
        return calendar.startOfDay(for: d)
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()
}

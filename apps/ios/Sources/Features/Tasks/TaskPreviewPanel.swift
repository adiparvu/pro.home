import SwiftUI

// MARK: - Live preview panel
//
// The right-hand (iPad) / top (iPhone) surface of the task editor. Every field
// in the form feeds straight into this view's parameters, so as the user types
// a title, flips a priority or toggles a sync destination, the hero card, the
// list preview, the calendar strip and the reminder row all re-render on the
// same spring — no delay, no intermediate model. Read-only by construction.

struct TaskPreviewPanel: View {
    let title: String
    let description: String
    let priority: String
    let category: String
    let dueDate: Date?
    let hasDueTime: Bool
    let assigneeNames: [String]
    let addToCalendar: Bool
    let addToReminders: Bool

    @Environment(FamilyService.self) private var familyService
    @State private var livePulse = false

    private var priorityStyle: TaskPriorityStyle { TaskPriorityStyle(priority) }
    private var categoryStyle: TaskCategoryStyle { TaskCategoryStyle(category) }
    private var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "task_preview_placeholder_title") : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            previewChrome
            heroCard
            listPreview
            calendarPreview
            remindersPreview
        }
        .animation(.taskSpring, value: priority)
        .animation(.taskSpring, value: category)
        .animation(.taskSpring, value: dueDate)
        .animation(.taskSpring, value: addToCalendar)
        .animation(.taskSpring, value: addToReminders)
        .animation(.snappy, value: assigneeNames)
        .onAppear { livePulse = true }
    }

    // MARK: - Chrome

    private var previewChrome: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("task_preview_title")
                        .font(AppFont.title3)
                        .foregroundStyle(.primary)
                    Circle()
                        .fill(Color.brandSuccess)
                        .frame(width: 8, height: 8)
                        .opacity(livePulse ? 1 : 0.35)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: livePulse)
                }
                Text("task_preview_subtitle")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            Spacer()
            Image(systemName: "eye")
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: 40, height: 40)
                .glassCircle()
                .accessibilityHidden(true)
        }
    }

    // MARK: - Hero card (shared TaskGradientCard, fed by the live fields)

    private var heroCard: some View {
        TaskGradientCard(
            title: displayTitle,
            description: description.trimmingCharacters(in: .whitespaces),
            priorityStyle: priorityStyle,
            categoryStyle: categoryStyle,
            dueDateText: dueDateText,
            assigneeText: assigneeText,
            showsCalendarChip: addToCalendar,
            showsRemindersChip: addToReminders
        )
    }

    // MARK: - List preview

    private var listPreview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("task_preview_in_list")
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(priorityStyle.color).frame(width: 9, height: 9).padding(.top, 5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        Text(displayTitle)
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        PriorityPill(style: priorityStyle, compact: true)
                    }
                    HStack(spacing: 6) {
                        Text(dueDate != nil ? shortDate : String(localized: "No date"))
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.secondaryTextColor)
                        Text("·").foregroundStyle(Color.primary.opacity(0.25))
                        Image(systemName: categoryStyle.icon)
                            .font(AppFont.scaled(10, weight: .semibold))
                            .foregroundStyle(Color.secondaryTextColor)
                        Text(categoryStyle.label)
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .padding(.top, 2)
            }
            .padding(AppSpacing.base)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
        }
    }

    // MARK: - Calendar preview

    private var calendarPreview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("task_preview_calendar")
            VStack(alignment: .leading, spacing: 12) {
                Text(monthTitle)
                    .font(AppFont.label)
                    .foregroundStyle(Color.secondaryTextColor)
                    .textCase(.uppercase)

                let days = weekDays
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                        Text(sym)
                            .font(AppFont.scaled(11, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        let isDue = isSameDay(day, dueDate)
                        VStack(spacing: 4) {
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(AppFont.scaled(15, weight: isDue ? .bold : .regular))
                                .foregroundStyle(isDue ? .white : Color.primary.opacity(0.8))
                                .frame(width: 30, height: 30)
                                .background {
                                    if isDue { Circle().fill(Color.brandPurple) }
                                }
                            Circle()
                                .fill(isDue ? priorityStyle.color : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if dueDate != nil {
                    HStack(spacing: 10) {
                        Text(hasDueTime ? timeString : allDayString)
                            .font(AppFont.scaled(12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.secondaryTextColor)
                            .frame(width: 44, alignment: .leading)
                        HStack(spacing: 8) {
                            Circle().fill(priorityStyle.color).frame(width: 7, height: 7)
                            Text(displayTitle)
                                .font(AppFont.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(priorityStyle.color.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(AppSpacing.base)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
        }
    }

    // MARK: - Reminders preview

    private var remindersPreview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("task_preview_reminders")
            HStack(spacing: 12) {
                Image(systemName: "list.bullet")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.brandWarning)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Text(displayTitle)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(priorityStyle.color).frame(width: 8, height: 8)
            }
            .padding(AppSpacing.base)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.captionEmphasis)
            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
    }

    private var dueDateText: String {
        guard let d = dueDate else { return String(localized: "No date") }
        return hasDueTime ? AppDate.monthDayTime.string(from: d) : AppDate.monthDayYear.string(from: d)
    }

    private var shortDate: String {
        guard let d = dueDate else { return "" }
        return AppDate.monthDayYear.string(from: d)
    }

    private var assigneeText: String {
        assigneeNames.isEmpty ? String(localized: "Unassigned") : assigneeNames.joined(separator: ", ")
    }

    private var monthTitle: String {
        AppDate.monthYear.string(from: dueDate ?? Date())
    }

    private var timeString: String { TaskPreviewPanel.time.string(from: dueDate ?? Date()) }
    private var allDayString: String { String(localized: "task_all_day") }

    /// The Mon–Sun week that contains the due date (or today).
    private var weekDays: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let anchor = dueDate ?? Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekdaySymbols: [String] {
        // Monday-first single-letter symbols, locale aware.
        var cal = Calendar.current
        cal.firstWeekday = 2
        let symbols = cal.veryShortStandaloneWeekdaySymbols // [Sun,Mon,...]
        return Array(symbols[1...6]) + [symbols[0]]
    }

    private func isSameDay(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f
    }()
}

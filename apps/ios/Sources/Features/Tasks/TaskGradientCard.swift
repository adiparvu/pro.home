import SwiftUI

// MARK: - Gradient task card
//
// The signature "hero" presentation of a task — priority pill top-left,
// category pill top-right, big white title, description, date and assignee
// rows over a priority-tinted dark gradient. Extracted from the editor's
// live preview so ONE component now renders in three places: the editor
// preview (field-fed), the long-press context-menu preview, and the top of
// the task detail page (both task-fed via the convenience init).

struct TaskGradientCard: View {
    let title: String
    let description: String?
    let priorityStyle: TaskPriorityStyle
    let categoryStyle: TaskCategoryStyle
    let dueDateText: String
    let assigneeText: String
    var showsCalendarChip: Bool = false
    var showsRemindersChip: Bool = false
    var minHeight: CGFloat = 300
    /// Shadow treatment. The default is a discreet elevation shadow — large
    /// colored blurs are a real compositor cost when cards sit in scrolling
    /// content. The long-press context-menu preview opts into the rich
    /// priority-tinted shadow, where exactly one card is on screen.
    var prominentShadow: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                darkPill(dot: priorityStyle.color, text: Text(priorityStyle.label))
                Spacer()
                darkPill(icon: categoryStyle.icon, text: Text(categoryStyle.label))
            }

            Text(verbatim: title)
                .font(AppFont.scaled(28, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .contentTransition(.interpolate)

            if let description, !description.isEmpty {
                Text(verbatim: description)
                    .font(AppFont.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 10) {
                heroRow(icon: "calendar", text: dueDateText)
                heroRow(icon: "person.2", text: assigneeText)
            }

            if showsCalendarChip || showsRemindersChip {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 0.5)
                HStack(spacing: AppSpacing.xl) {
                    if showsCalendarChip {
                        syncChip(icon: "calendar", tint: Color.brandPurple, text: Text("task_in_calendar"))
                    }
                    if showsRemindersChip {
                        syncChip(icon: "list.bullet", tint: Color.brandWarning, text: Text("task_in_reminders"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: priorityStyle.color.opacity(prominentShadow ? 0.28 : 0.12),
                radius: prominentShadow ? 24 : 8,
                y: prominentShadow ? 12 : 3)
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [priorityStyle.color, Color.brandPurple],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.25)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func heroRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 20)
            Text(verbatim: text)
                .font(AppFont.subheadline)
                .foregroundStyle(.white)
        }
    }

    private func syncChip(icon: String, tint: Color, text: Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.caption)
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            text
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.white)
        }
    }

    private func darkPill(dot: Color? = nil, icon: String? = nil, text: Text) -> some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            if let icon {
                Image(systemName: icon).font(AppFont.scaled(11, weight: .semibold))
            }
            text.font(AppFont.footnoteEmphasis)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
    }
}

// MARK: - Task-fed convenience (context-menu preview, detail header)

extension TaskGradientCard {
    init(task: MaintenanceTask, minHeight: CGFloat = 300, prominentShadow: Bool = false) {
        self.init(
            title: task.title,
            description: task.description?.trimmingCharacters(in: .whitespaces),
            priorityStyle: task.priorityStyle,
            categoryStyle: task.categoryStyle,
            dueDateText: task.dueDateDisplay,
            assigneeText: task.assigneeNames.isEmpty
                ? String(localized: "Unassigned")
                : task.assigneeNames.joined(separator: ", "),
            minHeight: minHeight,
            prominentShadow: prominentShadow
        )
    }
}

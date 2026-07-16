import SwiftUI

// MARK: - Calendar view modes (C1)
//
// The house calendar reads every dated fact from ONE aggregator (HouseAgenda);
// these are just different lenses onto that same `[AgendaItem]` stream — Month
// grid, a Week strip + day, a single Day, and a forward Agenda list. Each view
// is a pure presenter: `CalendarView` owns the data + the task check-off, and
// hands each mode the items plus a task lookup / toggle closure.

enum CalendarMode: String, CaseIterable, Identifiable {
    case month, week, day, agenda
    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .month:  return "cal_mode_month"
        case .week:   return "cal_mode_week"
        case .day:    return "cal_mode_day"
        case .agenda: return "cal_mode_agenda"
        }
    }

    var icon: String {
        switch self {
        case .month:  return "calendar"
        case .week:   return "calendar.day.timeline.left"
        case .day:    return "sun.max"
        case .agenda: return "list.bullet"
        }
    }

    /// The calendar component a prev/next step shifts by (agenda pages by month).
    var stepComponent: Calendar.Component {
        switch self {
        case .month, .agenda: return .month
        case .week:           return .weekOfYear
        case .day:            return .day
        }
    }
}

// MARK: - Shared agenda row (one dated item)

/// One agenda entry, reused by every calendar mode and the day detail. A `.task`
/// item shows a real check circle whose completion flows through TaskService
/// (which mirrors the linked Apple Reminder both ways); every other category
/// shows its coloured badge and, when it has one, deep-links to its own screen.
struct HouseAgendaRow: View {
    let item: AgendaItem
    var task: MaintenanceTask? = nil
    var onToggle: (() -> Void)? = nil
    /// Reschedule a task to another day (tasks only) — surfaced as a context menu.
    var onReschedule: (() -> Void)? = nil

    /// Shared so a scrolling list doesn't allocate a formatter per row.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("HH:mm"); return f
    }()

    private var timeLabel: String? {
        guard item.hasTime else { return nil }
        return Self.timeFormatter.string(from: item.date)
    }

    var body: some View {
        Button {
            guard let link = item.deepLink, let url = URL(string: link) else { return }
            HapticFeedback.selection()
            NotificationCenter.default.post(name: .prvioOpenURL, object: url)
        } label: {
            HStack(spacing: 12) {
                if task != nil, let onToggle {
                    Button {
                        HapticFeedback.selection()
                        onToggle()
                    } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(AppFont.scaled(20))
                            .foregroundStyle(item.isCompleted ? Color.brandSuccess : Color.primary.opacity(0.3))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(item.isCompleted ? "task_mark_incomplete" : "task_mark_complete"))
                } else {
                    ColoredIconBadge(icon: item.category.icon, color: item.category.color, size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                        .strikethrough(item.isCompleted, color: Color.primary.opacity(0.4))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: AppSpacing.sm)
                if let timeLabel {
                    Text(timeLabel)
                        .font(AppFont.scaled(11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .monospacedDigit()
                } else if item.deepLink != nil {
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(item.deepLink == nil && task == nil)
        .contextMenu {
            if let onReschedule {
                Button { onReschedule() } label: {
                    Label("cal_reschedule", systemImage: "calendar.badge.clock")
                }
            }
        }
    }
}

// MARK: - Agenda section (a non-empty day in the forward Agenda list)

struct CalendarAgendaSection: Identifiable {
    let day: Date
    let items: [AgendaItem]
    var id: Date { day }
}

// MARK: - Empty state

struct CalendarEmptyDay: View {
    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: AppSpacing.xl)
            Image(systemName: "checkmark.circle")
                .font(AppFont.scaled(30))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text("cal_nothing_scheduled")
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            Spacer(minLength: AppSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Week strip (7 tappable day cells with category dots)

struct CalendarWeekStrip: View {
    let weekDays: [Date]
    let selectedDay: Date?
    let dotsFor: (Date) -> [Color]
    let onSelect: (Date) -> Void

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let isSel = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                Button { onSelect(day) } label: {
                    VStack(spacing: 5) {
                        Text(weekdayLetter(day))
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.primary.opacity(0.35))
                        ZStack {
                            Circle()
                                .fill(isSel ? Color.white : isToday ? Color.primary.opacity(0.15) : .clear)
                                .frame(width: 34, height: 34)
                            Text("\(cal.component(.day, from: day))")
                                .font(AppFont.scaled(15, weight: isToday || isSel ? .bold : .regular))
                                .foregroundStyle(isSel ? .black : Color.primary.opacity(isToday ? 1 : 0.75))
                        }
                        HStack(spacing: 3) {
                            ForEach(Array(dotsFor(day).prefix(3).enumerated()), id: \.offset) { _, c in
                                Circle().fill(c).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    private func weekdayLetter(_ d: Date) -> String {
        let syms = cal.veryShortStandaloneWeekdaySymbols
        return syms[cal.component(.weekday, from: d) - 1]
    }
}

// MARK: - Day header (big date, for Day mode)

struct CalendarDayHeader: View {
    let date: Date
    private let cal = Calendar.current

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(cal.component(.day, from: date))")
                .font(AppFont.scaled(34, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 1) {
                Text(weekday)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(cal.isDateInToday(date) ? Color.accentColor : .primary)
                Text(monthYear)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    private var weekday: String {
        if cal.isDateInToday(date) { return String(localized: "cal_today") }
        if cal.isDateInTomorrow(date) { return String(localized: "cal_tomorrow") }
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEE"); return f.string(from: date).capitalized
    }
    private var monthYear: String {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy"); return f.string(from: date)
    }
}

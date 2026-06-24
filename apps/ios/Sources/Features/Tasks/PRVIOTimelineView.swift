import SwiftUI

// MARK: - PRVIO Timeline — matches dark mockup (chronological events + filter chips)

struct PRVIOTimelineView: View {
    @EnvironmentObject var taskService: TaskService
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    enum TimeFilter: String, CaseIterable {
        case today  = "Today"
        case fiveMin = "5m"
        case thirtyMin = "30m"
        case day = "24h"

        var interval: TimeInterval? {
            switch self {
            case .today:    return nil
            case .fiveMin:  return 5 * 60
            case .thirtyMin: return 30 * 60
            case .day:      return 24 * 3600
            }
        }
    }

    @State private var filter: TimeFilter = .today

    private var filteredEvents: [TimelineEvent] {
        let all = buildEvents()
        guard let interval = filter.interval else {
            // "Today" → events from today only
            return all.filter { Calendar.current.isDateInToday($0.date) || $0.date > Date() }
        }
        let cutoff = Date().addingTimeInterval(-interval)
        return all.filter { $0.date >= cutoff }
    }

    private var groupedEvents: [(String, [TimelineEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { $0.groupKey }
        let sorted = grouped.sorted { a, b in
            guard let d1 = a.value.first?.date, let d2 = b.value.first?.date else { return false }
            return d1 > d2
        }
        return sorted.map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                filterChipsRow
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                if groupedEvents.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    ForEach(groupedEvents, id: \.0) { group, events in
                        sectionHeader(group)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 8)

                        ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                            HStack(alignment: .top, spacing: 0) {
                                // Timeline spine
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(event.color)
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                    if idx < events.count - 1 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.1))
                                            .frame(width: 1.5)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                .frame(width: 30)
                                .padding(.leading, 16)

                                // Event card
                                TimelineEventCard(event: event)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top, 8)
            .trackTabScroll()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(filteredEvents.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimeFilter.allCases, id: \.self) { f in
                    CategoryFilterChip(label: f.rawValue, isActive: filter == f) {
                        withAnimation(.spring(response: 0.3)) { filter = f }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text("No events")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text("No activity in this time range")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.35))
            .kerning(0.8)
    }

    private func buildEvents() -> [TimelineEvent] {
        var events: [TimelineEvent] = []

        // Completed tasks → timeline events
        let completed = taskService.tasks.filter { $0.isCompleted }
        for task in completed.prefix(20) {
            let date = parseDate(task.updatedAt) ?? Date()
            events.append(.init(
                id: task.id,
                icon: "checkmark.circle.fill",
                color: Color(red: 0.20, green: 0.82, blue: 0.48),
                title: task.title,
                subtitle: task.category.capitalized,
                date: date
            ))
        }

        // Active tasks with due dates
        let active = taskService.tasks.filter { !$0.isCompleted && $0.dueDate != nil }
        for task in active.prefix(10) {
            let date = parseDate(task.dueDate ?? task.createdAt) ?? Date()
            let isOverdue = date < Date()
            events.append(.init(
                id: task.id,
                icon: isOverdue ? "exclamationmark.circle.fill" : "clock.fill",
                color: isOverdue ? .red : .orange,
                title: task.title,
                subtitle: isOverdue ? "Overdue" : "Due " + relativeDate(date),
                date: date
            ))
        }

        // Elements — recent additions
        for element in elementService.elements.prefix(8) {
            let date = parseDate(element.createdAt) ?? Date()
            events.append(.init(
                id: element.id,
                icon: element.elementType.icon,
                color: element.layer.color,
                title: element.name + " added",
                subtitle: element.elementType.displayName,
                date: date
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    private func parseDate(_ str: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: str)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "today" }
        if cal.isDateInTomorrow(date) { return "tomorrow" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }
}

// MARK: - TimelineEvent model

struct TimelineEvent: Identifiable {
    let id: UUID
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let date: Date

    var groupKey: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    var timeLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            let df = DateFormatter()
            df.timeStyle = .short
            return df.string(from: date)
        }
        return ""
    }
}

// MARK: - Timeline Event Card

struct TimelineEventCard: View {
    let event: TimelineEvent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(event.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: event.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(event.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(event.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.45))
            }

            Spacer()

            if !event.timeLabel.isEmpty {
                Text(event.timeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

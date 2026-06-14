import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService
    @State private var displayedMonth = Date()
    @State private var selectedDay: Date? = nil

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                monthHeader
                weekdayRow
                daysGrid
                Divider().background(Color.primary.opacity(0.06)).padding(.top, 8)
                dayDetail
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack {
            Button {
                if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                    withAnimation(.spring(response: 0.3)) { displayedMonth = prev }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                    withAnimation(.spring(response: 0.3)) { displayedMonth = next }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Weekday labels

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(["Mo","Tu","We","Th","Fr","Sa","Su"], id: \.self) { d in
                Text(d)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Days grid

    private var daysGrid: some View {
        let days = daysInMonth()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    DayCell(
                        date: day,
                        isToday: calendar.isDateInToday(day),
                        isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                        taskDots: dotsFor(day)
                    ) {
                        withAnimation(.spring(response: 0.22)) {
                            selectedDay = calendar.isDate(selectedDay ?? .distantPast, inSameDayAs: day) ? nil : day
                        }
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Day detail

    @ViewBuilder
    private var dayDetail: some View {
        if let day = selectedDay {
            let tasks = tasksFor(day)
            let docs  = documentsFor(day)

            if tasks.isEmpty && docs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.primary.opacity(0.2))
                    Text("Nothing scheduled")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.35))
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(tasks) { task in
                            CalendarEventRow(
                                icon: "checklist",
                                color: task.priorityColor,
                                title: task.title,
                                subtitle: task.statusDisplay
                            )
                        }
                        ForEach(docs) { doc in
                            CalendarEventRow(
                                icon: doc.categoryIcon,
                                color: .orange,
                                title: doc.name,
                                subtitle: "Expires \(doc.expiresDisplay ?? "")"
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.bottom, 100)
                }
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Text("Tap a day to see events")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.25))
                Spacer()
            }
        }
    }

    // MARK: - Data helpers

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private func daysInMonth() -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        // weekday of first day (monday = 0)
        var weekday = calendar.component(.weekday, from: monthStart) - 2
        if weekday < 0 { weekday += 7 }

        var days: [Date?] = Array(repeating: nil, count: weekday)
        for d in range {
            days.append(calendar.date(byAdding: .day, value: d - 1, to: monthStart))
        }
        // pad to full rows
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func dotsFor(_ date: Date) -> [Color] {
        var colors: [Color] = []
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let dateStr = iso.string(from: date)

        if taskService.tasks.contains(where: { $0.dueDate == dateStr && !$0.isCompleted }) {
            colors.append(.blue)
        }
        if documentService.documents.contains(where: { $0.expiresAt == dateStr }) {
            colors.append(.orange)
        }
        return colors
    }

    private func tasksFor(_ date: Date) -> [MaintenanceTask] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let s = iso.string(from: date)
        return taskService.tasks.filter { $0.dueDate == s }
    }

    private func documentsFor(_ date: Date) -> [DocumentModel] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let s = iso.string(from: date)
        return documentService.documents.filter { $0.expiresAt == s }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let taskDots: [Color]
    let action: () -> Void

    private var day: Int { Calendar.current.component(.day, from: date) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white : isToday ? Color.primary.opacity(0.15) : Color.clear)
                        .frame(width: 32, height: 32)
                    Text("\(day)")
                        .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Color.black : Color.primary.opacity(isToday ? 1 : 0.7))
                }
                HStack(spacing: 3) {
                    ForEach(Array(taskDots.prefix(3).enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Event Row

private struct CalendarEventRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

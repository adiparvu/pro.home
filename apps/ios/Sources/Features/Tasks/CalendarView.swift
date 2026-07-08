import SwiftUI

// The house calendar: every date the property knows about, in one grid —
// task due dates, document expirations, appliance warranty ends and family
// birthdays. Exportable as .ics so the household's deadlines can live next
// to the owner's own appointments in Apple Calendar.
struct CalendarView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(FamilyService.self) private var familyService
    @State private var displayedMonth = Date()
    @State private var selectedDay: Date? = nil
    @State private var icsURL: URL? = nil

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                monthHeader
                weekdayRow
                daysGrid
                Divider().background(Color.primary.opacity(AppOpacity.hairline)).padding(.top, AppSpacing.sm)
                dayDetail
            }
        }
        .navigationTitle(Text("house_calendar_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let icsURL {
                    ShareLink(item: icsURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(AppFont.headline)
                    }
                    .accessibilityLabel(Text("cal_export_ics"))
                }
            }
        }
        .onAppear(perform: buildICS)
    }

    /// The export is rebuilt whenever the screen appears — the data is
    /// already in memory, so this is a string concatenation, not a fetch.
    private func buildICS() {
        icsURL = HouseCalendarICS.writeFile(
            tasks: taskService.tasks,
            documents: documentService.documents,
            appliances: applianceService.appliances,
            members: familyService.members)
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
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(LocalizedStringKey(monthTitle))
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                    withAnimation(.spring(response: 0.3)) { displayedMonth = next }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Weekday labels

    private var weekdayRow: some View {
        // Monday-first, in the user's language — the system symbols, not
        // hardcoded English abbreviations.
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let mondayFirst = (0..<7).map { symbols[($0 + 1) % 7] }
        return HStack(spacing: 0) {
            ForEach(Array(mondayFirst.enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppSpacing.md)
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
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xxs)
    }

    // MARK: - Day detail

    @ViewBuilder
    private var dayDetail: some View {
        if let day = selectedDay {
            let tasks = tasksFor(day)
            let docs  = documentsFor(day)
            let warr  = warrantiesFor(day)
            let bdays = birthdaysFor(day)

            if tasks.isEmpty && docs.isEmpty && warr.isEmpty && bdays.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(AppFont.scaled(30))
                        .foregroundStyle(Color.primary.opacity(0.2))
                    Text("Nothing scheduled")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
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
                                subtitle: String(format: String(localized: "cal_expires_fmt"),
                                                 doc.expiresDisplay ?? "")
                            )
                        }
                        ForEach(warr) { appliance in
                            CalendarEventRow(
                                icon: "checkmark.seal.fill",
                                color: Color.brandSuccess,
                                title: appliance.name,
                                subtitle: String(localized: "cal_warranty_ends")
                            )
                        }
                        ForEach(bdays) { member in
                            CalendarEventRow(
                                icon: "gift.fill",
                                color: .pink,
                                title: member.name,
                                subtitle: String(localized: "cal_birthday")
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
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
        let dateStr = AppDate.dayString(from: date)

        // Due dates may carry a time ("yyyy-MM-dd HH:mm") — match by day prefix.
        if taskService.tasks.contains(where: { ($0.dueDate?.hasPrefix(dateStr) ?? false) && !$0.isCompleted }) {
            colors.append(.blue)
        }
        if documentService.documents.contains(where: { $0.expiresAt == dateStr }) {
            colors.append(.orange)
        }
        if applianceService.appliances.contains(where: { $0.warrantyUntil?.hasPrefix(dateStr) ?? false }) {
            colors.append(Color.brandSuccess)
        }
        if familyService.members.contains(where: { isBirthday($0, on: date) }) {
            colors.append(.pink)
        }
        return colors
    }

    private func tasksFor(_ date: Date) -> [MaintenanceTask] {
        let s = AppDate.dayString(from: date)
        return taskService.tasks.filter { $0.dueDate?.hasPrefix(s) ?? false }
    }

    private func documentsFor(_ date: Date) -> [DocumentModel] {
        let s = AppDate.dayString(from: date)
        return documentService.documents.filter { $0.expiresAt == s }
    }

    private func warrantiesFor(_ date: Date) -> [Appliance] {
        let s = AppDate.dayString(from: date)
        return applianceService.appliances.filter { $0.warrantyUntil?.hasPrefix(s) ?? false }
    }

    /// Birthdays recur yearly — match month and day, whatever the birth year.
    private func birthdaysFor(_ date: Date) -> [FamilyMember] {
        familyService.members.filter { isBirthday($0, on: date) }
    }

    private func isBirthday(_ member: FamilyMember, on date: Date) -> Bool {
        guard let birth = member.birthdayDate else { return false }
        let b = calendar.dateComponents([.month, .day], from: birth)
        let d = calendar.dateComponents([.month, .day], from: date)
        return b.month == d.month && b.day == d.day
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
                        .font(AppFont.scaled(14, weight: isToday || isSelected ? .bold : .regular))
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
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(LocalizedStringKey(subtitle))
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
    }
}

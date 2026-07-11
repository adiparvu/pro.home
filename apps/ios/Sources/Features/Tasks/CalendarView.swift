import SwiftUI

// The house calendar: EVERY date the property knows about, in one grid —
// task due dates, document/paper expirations, appliance warranties, family
// birthdays, recurring bills and plant care. All of it flows from one
// aggregator (HouseAgenda), filtered by category chips, and exports as .ics so
// the household's deadlines can live next to the owner's own appointments.
struct CalendarView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(PlantService.self) private var plantService
    @State private var displayedMonth = Date()
    @State private var selectedDay: Date? = nil
    @State private var icsURL: URL? = nil
    /// Which categories are shown. All on by default; chips toggle them.
    @State private var active: Set<AgendaCategory> = Set(AgendaCategory.allCases)
    /// Mirror-to-Apple-Calendar toggle (mirrors the persisted flag).
    @State private var mirrorOn = HouseCalendarMirror.isEnabled

    private var calendar: Calendar { Calendar.current }

    /// The full mirror window (−1…+12 months), ALL categories — what the Apple
    /// Calendar mirror reconciles against, independent of the on-screen filter.
    private func fullAgenda() -> [AgendaItem] {
        let now = Date()
        let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let end = calendar.date(byAdding: .month, value: 12, to: now) ?? now
        return HouseAgenda.items(
            in: start...end,
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members,
            financial: financialService.records, plants: plantService.plants)
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                monthHeader
                categoryFilterRow
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
                Menu {
                    Toggle(isOn: $mirrorOn) {
                        Label("cal_sync_apple", systemImage: "calendar")
                    }
                    if mirrorOn {
                        Button {
                            Task { await HouseCalendarMirror.sync(fullAgenda()) }
                        } label: {
                            Label("cal_sync_now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    if let icsURL {
                        ShareLink(item: icsURL) {
                            Label("cal_export_ics", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(AppFont.headline)
                }
                .accessibilityLabel(Text("Calendar options"))
            }
        }
        .onAppear {
            buildICS()
            // Keep the mirror fresh whenever the calendar is opened.
            if HouseCalendarMirror.isEnabled {
                Task { await HouseCalendarMirror.sync(fullAgenda()) }
            }
        }
        .onChange(of: mirrorOn) { _, on in
            Task {
                if on {
                    // Ask for access + do the first sync; revert if denied.
                    let ok = await HouseCalendarMirror.enable(with: fullAgenda())
                    if !ok { mirrorOn = false }
                } else {
                    HouseCalendarMirror.disableAndRemove()
                }
            }
        }
    }

    // MARK: - Agenda for the displayed month

    /// The visible month's start...end, so recurring items project only across
    /// what's on screen.
    private var monthRange: ClosedRange<Date>? {
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: start),
              let end = calendar.date(byAdding: .day, value: range.count - 1, to: start) else { return nil }
        return start...end
    }

    /// The full agenda for the month, filtered by the active chips, grouped by
    /// day string. Computed once per body pass — month-scoped, so small.
    private var itemsByDay: [String: [AgendaItem]] {
        guard let range = monthRange else { return [:] }
        let all = HouseAgenda.items(
            in: range,
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members,
            financial: financialService.records, plants: plantService.plants
        ).filter { active.contains($0.category) }
        return Dictionary(grouping: all) { AppDate.dayString(from: $0.date) }
    }

    /// The export is rebuilt whenever the screen appears — data is already in
    /// memory, so this is a string concatenation, not a fetch.
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
            monthButton(system: "chevron.left", label: "Previous month", delta: -1)
            Spacer()
            Text(LocalizedStringKey(monthTitle))
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            monthButton(system: "chevron.right", label: "Next month", delta: 1)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
    }

    private func monthButton(system: String, label: LocalizedStringKey, delta: Int) -> some View {
        Button {
            if let d = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
                withAnimation(.spring(response: 0.3)) { displayedMonth = d }
            }
        } label: {
            Image(systemName: system)
                .font(AppFont.headline)
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Category filter

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(AgendaCategory.allCases) { cat in
                    GlassFilterChip(
                        label: catLabel(cat),
                        systemImage: cat.icon,
                        isSelected: active.contains(cat)
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if active.contains(cat) { active.remove(cat) } else { active.insert(cat) }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .padding(.bottom, AppSpacing.xs)
    }

    private func catLabel(_ cat: AgendaCategory) -> String {
        switch cat {
        case .task:      return String(localized: "agenda_cat_tasks")
        case .document:  return String(localized: "agenda_cat_documents")
        case .warranty:  return String(localized: "agenda_cat_warranties")
        case .birthday:  return String(localized: "agenda_cat_birthdays")
        case .financial: return String(localized: "agenda_cat_financial")
        case .plant:     return String(localized: "agenda_cat_plants")
        }
    }

    // MARK: - Weekday labels

    private var weekdayRow: some View {
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
        let byDay = itemsByDay
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    DayCell(
                        date: day,
                        isToday: calendar.isDateInToday(day),
                        isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                        dots: dots(for: day, byDay: byDay)
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
            let items = itemsByDay[AppDate.dayString(from: day)] ?? []
            if items.isEmpty {
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
                        ForEach(items) { item in
                            AgendaRow(item: item)
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
        AppDateDisplay.fullMonthYear.string(from: displayedMonth).capitalized
    }

    private func daysInMonth() -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        var weekday = calendar.component(.weekday, from: monthStart) - 2
        if weekday < 0 { weekday += 7 }
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for d in range {
            days.append(calendar.date(byAdding: .day, value: d - 1, to: monthStart))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    /// Up to three category dots for a day (distinct categories present).
    private func dots(for date: Date, byDay: [String: [AgendaItem]]) -> [Color] {
        let items = byDay[AppDate.dayString(from: date)] ?? []
        var seen = Set<AgendaCategory>()
        var colors: [Color] = []
        for it in items where !seen.contains(it.category) {
            seen.insert(it.category); colors.append(it.category.color)
        }
        return colors
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let dots: [Color]
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
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, c in
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

// MARK: - Agenda row (one deadline)

private struct AgendaRow: View {
    let item: AgendaItem

    var body: some View {
        Button {
            guard let link = item.deepLink, let url = URL(string: link) else { return }
            HapticFeedback.selection()
            NotificationCenter.default.post(name: .prvioOpenURL, object: url)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: item.category.icon, color: item.category.color, size: 36)
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
                Spacer()
                if item.deepLink != nil {
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
        .disabled(item.deepLink == nil)
    }
}

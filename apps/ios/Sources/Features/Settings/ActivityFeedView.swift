import SwiftUI

// MARK: - Models

private enum ActivityPeriod: String, CaseIterable {
    case week = "1W", month = "1M", threeMonths = "3M", sixMonths = "6M", year = "1Y"

    var days: Int {
        switch self {
        case .week:        return 7
        case .month:       return 30
        case .threeMonths: return 90
        case .sixMonths:   return 180
        case .year:        return 365
        }
    }
}

private enum ActivityCategory: String, CaseIterable {
    case all        = "All"
    case tasks      = "Tasks"
    case finances   = "Finances"
    case documents  = "Documents"
    case elements   = "Elements"
    case appliances = "Appliances"
    case plants     = "Plants"

    /// Outline symbols — the chips and timeline render monochrome and
    /// hierarchical, so the lighter variants read cleaner than `.fill`.
    var icon: String {
        switch self {
        case .all:        return "square.grid.2x2"
        case .tasks:      return "checkmark.circle"
        case .finances:   return "banknote"
        case .documents:  return "doc.text"
        case .elements:   return "cube"
        case .appliances: return "washer"
        case .plants:     return "leaf"
        }
    }
}

/// One synthesized feed entry. `title` is a `LocalizedStringKey` built from a
/// catalog key at the synthesis site, so every event title resolves through
/// Localizable.xcstrings (ro + en) instead of shipping raw English text.
private struct ActivityEvent: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let subtitle: String
    let date: Date
    let member: String
    let category: ActivityCategory
}

/// Events of one calendar day, newest first.
private struct ActivityDayGroup: Identifiable {
    let day: Date
    let events: [ActivityEvent]
    var id: Date { day }
}

/// The whole feed derived in a single pass per body evaluation — the body
/// never re-filters or re-groups inside its loops.
private struct ActivityFeedSnapshot {
    let groups: [ActivityDayGroup]
    /// Events inside the selected period, before category/member filters —
    /// distinguishes "no activity at all" from "filters matched nothing".
    let periodCount: Int
    let visibleCount: Int
}

// MARK: - View

struct ActivityFeedView: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(FamilyService.self) private var familyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PlantService.self) private var plantService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period:           ActivityPeriod   = .month
    @State private var selectedMember:   String?          = nil
    @State private var selectedCategory: ActivityCategory = .all

    /// Internal sentinel for "the signed-in user" — kept stable for filter
    /// equality; presented through the localized "You" catalog key.
    private let currentUser = "You"

    private var filterAnimation: Animation? { reduceMotion ? nil : .smooth }

    // MARK: Event synthesis

    private var allEvents: [ActivityEvent] {
        var events: [ActivityEvent] = []

        // Finances
        for r in financialService.records {
            guard let date = AppDate.day(from: r.date) else { continue }
            let isIncome = r.type == "income"
            events.append(ActivityEvent(
                icon:     isIncome ? "arrow.down.circle" : "arrow.up.circle",
                title:    isIncome ? "Income added" : "Expense recorded",
                subtitle: "\(r.title) · \(financialService.moneyDisplay(r.amount))",
                date:     date,
                member:   currentUser,
                category: .finances
            ))
        }

        // Documents
        for doc in documentService.documents {
            let date = AppDate.timestamp(from: doc.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     doc.categoryIcon,
                title:    "Document added",
                subtitle: doc.name,
                date:     date,
                member:   currentUser,
                category: .documents
            ))
        }

        // Tasks
        for task in taskService.tasks {
            let date = AppDate.timestamp(from: task.updatedAt)
                ?? AppDate.timestamp(from: task.createdAt) ?? Date()
            let taskMember = task.assigneeNames.first ?? currentUser
            if task.isCompleted {
                events.append(ActivityEvent(
                    icon:     "checkmark.circle",
                    title:    "Task completed",
                    subtitle: task.title,
                    date:     date,
                    member:   taskMember,
                    category: .tasks
                ))
            } else if let due = task.dueDate,
                      let dueDate = AppDate.timestamp(from: due), dueDate < Date() {
                events.append(ActivityEvent(
                    icon:     "exclamationmark.circle",
                    title:    "Task overdue",
                    subtitle: task.title,
                    date:     dueDate,
                    member:   taskMember,
                    category: .tasks
                ))
            } else {
                let created = AppDate.timestamp(from: task.createdAt) ?? Date()
                events.append(ActivityEvent(
                    icon:     "clock",
                    title:    "Task added",
                    subtitle: task.title,
                    date:     created,
                    member:   taskMember,
                    category: .tasks
                ))
            }
        }

        // Plants
        for plant in plantService.plants {
            if let wateredStr = plant.lastWateredAt,
               let wateredDate = AppDate.timestamp(from: wateredStr) {
                events.append(ActivityEvent(
                    icon:     "drop",
                    title:    "Plant watered",
                    subtitle: plant.name,
                    date:     wateredDate,
                    member:   currentUser,
                    category: .plants
                ))
            }
            let addedDate = AppDate.timestamp(from: plant.createdAt) ?? Date()
            let plantSubtitle = plant.emoji.isEmpty ? plant.name : "\(plant.emoji) \(plant.name)"
            events.append(ActivityEvent(
                icon:     "leaf",
                title:    "Plant added",
                subtitle: plantSubtitle,
                date:     addedDate,
                member:   currentUser,
                category: .plants
            ))
        }

        // Property elements
        for el in elementService.elements {
            let date = AppDate.timestamp(from: el.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     el.elementType.icon,
                title:    "Element added",
                subtitle: el.name,
                date:     date,
                member:   currentUser,
                category: .elements
            ))
        }

        // Appliances
        for ap in applianceService.appliances {
            let date = AppDate.timestamp(from: ap.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     ap.categoryIcon,
                title:    "Appliance added",
                subtitle: [ap.brand, ap.name].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " "),
                date:     date,
                member:   currentUser,
                category: .appliances
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    /// Filters and groups in one pass; called once per body evaluation.
    private var feedSnapshot: ActivityFeedSnapshot {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period.days, to: Date()) ?? Date()
        let inPeriod = allEvents.filter { $0.date >= cutoff }
        let visible = inPeriod.filter {
            (selectedMember == nil || $0.member == selectedMember)
                && (selectedCategory == .all || $0.category == selectedCategory)
        }

        let cal = Calendar.current
        var buckets: [Date: [ActivityEvent]] = [:]
        for event in visible {
            buckets[cal.startOfDay(for: event.date), default: []].append(event)
        }
        // `visible` is already newest-first, so each bucket stays sorted.
        let groups = buckets.keys.sorted(by: >).map {
            ActivityDayGroup(day: $0, events: buckets[$0] ?? [])
        }
        return ActivityFeedSnapshot(groups: groups,
                                    periodCount: inPeriod.count,
                                    visibleCount: visible.count)
    }

    // MARK: Members for filter

    private var allMembers: [String] {
        [currentUser] + familyService.members.map(\.name)
    }

    // MARK: Body

    var body: some View {
        let snapshot = feedSnapshot
        VStack(spacing: 0) {
            PageHeader(titleKey: "Activity", subtitleKey: "PROPERTY")

            periodRow(count: snapshot.visibleCount)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)

            categoryRow
                .padding(.top, AppSpacing.sm)

            memberRow
                .padding(.top, AppSpacing.xs)

            Divider().opacity(0.3).padding(.top, AppSpacing.sm)

            if snapshot.visibleCount == 0 {
                emptyState(filtersMatchedNothing: snapshot.periodCount > 0)
            } else {
                timeline(snapshot.groups)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Period chips

    private func periodRow(count: Int) -> some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(ActivityPeriod.allCases, id: \.self) { p in
                let isSelected = period == p
                Button {
                    HapticFeedback.selection()
                    withAnimation(filterAnimation) { period = p }
                } label: {
                    Text(LocalizedStringKey(p.rawValue))
                        .font(isSelected ? AppFont.captionStrong : AppFont.caption)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondaryTextColor)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .filterChip(isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
            Text("\(count)")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .glassCapsule()
                .contentTransition(.numericText())
                .animation(filterAnimation, value: count)
        }
    }

    // MARK: Category chips

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    Button {
                        HapticFeedback.selection()
                        withAnimation(filterAnimation) { selectedCategory = cat }
                    } label: {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: cat.icon)
                                .font(AppFont.label)
                                .symbolRenderingMode(.hierarchical)
                            Text(LocalizedStringKey(cat.rawValue))
                                .font(isSelected ? AppFont.captionStrong : AppFont.caption)
                        }
                        .foregroundStyle(isSelected ? Color.primary : Color.secondaryTextColor)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .filterChip(isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: Member filter

    private var memberRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(allMembers, id: \.self) { name in
                    let isSelected = selectedMember == name
                    Button {
                        HapticFeedback.selection()
                        withAnimation(filterAnimation) {
                            selectedMember = isSelected ? nil : name
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            memberAvatar(name: name, size: 22)
                            Text(displayName(name))
                                .font(isSelected ? AppFont.captionEmphasis : AppFont.caption)
                                .foregroundStyle(isSelected ? Color.primary : Color.secondaryTextColor)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .filterChip(isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                if selectedMember != nil {
                    Button {
                        HapticFeedback.selection()
                        withAnimation(filterAnimation) { selectedMember = nil }
                    } label: {
                        Text("All")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .filterChip(isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: Timeline

    private func timeline(_ groups: [ActivityDayGroup]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.xl, pinnedViews: .sectionHeaders) {
                ForEach(groups) { group in
                    Section {
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { idx, event in
                                    eventRow(event, isLast: idx == group.events.count - 1)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)
                    } header: {
                        dayHeader(group.day)
                    }
                }
                Spacer(minLength: 100)
            }
            .padding(.top, AppSpacing.md)
            .animation(filterAnimation, value: period)
            .animation(filterAnimation, value: selectedCategory)
            .animation(filterAnimation, value: selectedMember)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack {
            dayTitle(day)
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl + AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(appBackground)
    }

    /// "Today"/"Yesterday" resolve through the catalog; other days use the
    /// shared locale-aware formatters (year appended once it's not this year).
    private func dayTitle(_ day: Date) -> Text {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Text("Today") }
        if cal.isDateInYesterday(day) { return Text("Yesterday") }
        let formatter = cal.isDate(day, equalTo: Date(), toGranularity: .year)
            ? AppDate.monthDay : AppDate.monthDayYear
        return Text(formatter.string(from: day))
    }

    private func eventRow(_ event: ActivityEvent, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                // Monochrome hierarchical symbol on a neutral circle — the
                // sanctioned icon idiom; never a tinted color square.
                Image(systemName: event.icon)
                    .font(AppFont.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.subtleFill, in: Circle())
                    .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text(event.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text(event.date, format: .dateTime.hour().minute())
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    memberAvatar(name: event.member, size: 18)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)

            if !isLast {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, AppSpacing.base + 36 + AppSpacing.md)
            }
        }
    }

    // MARK: Empty state

    private func emptyState(filtersMatchedNothing: Bool) -> some View {
        VStack {
            Spacer()
            if filtersMatchedNothing {
                EmptyStateView(icon: "line.3.horizontal.decrease",
                               title: "No results")
            } else {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No activity in this period",
                    message: "Activities appear automatically as you\nadd tasks, documents, and transactions."
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    private func displayName(_ member: String) -> String {
        member == currentUser ? String(localized: "You") : member
    }

    private func memberAvatar(name: String, size: CGFloat) -> some View {
        let member = familyService.members.first { $0.name == name }
        let color: Color = member.map { colorFromHex($0.color) } ?? .blue
        return ZStack {
            Circle().fill(color.opacity(0.2))
            Text(String(displayName(name).prefix(1)).uppercased())
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }

    private func colorFromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        return Color(red: Double((int >> 16) & 0xFF) / 255,
                     green: Double((int >> 8) & 0xFF) / 255,
                     blue: Double(int & 0xFF) / 255)
    }
}

// MARK: - Filter chip style

/// The feed's one neutral chip treatment: a quiet capsule fill with a subtle
/// primary stroke when selected — never an accent-color fill. Monochrome keeps
/// every state legible on Liquid Glass in both light and dark.
private struct FilterChipStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                Color.primary.opacity(isSelected ? AppOpacity.subtleFill + 0.05 : AppOpacity.subtleFill),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    Color.primary.opacity(isSelected ? 0.25 : AppOpacity.hairline),
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
            .contentShape(Capsule())
    }
}

private extension View {
    func filterChip(isSelected: Bool) -> some View {
        modifier(FilterChipStyle(isSelected: isSelected))
    }
}

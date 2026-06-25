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

    var icon: String {
        switch self {
        case .all:        return "square.grid.2x2.fill"
        case .tasks:      return "checkmark.circle.fill"
        case .finances:   return "banknote.fill"
        case .documents:  return "doc.text.fill"
        case .elements:   return "cube.fill"
        case .appliances: return "washer.fill"
        case .plants:     return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .all:        return .blue
        case .tasks:      return Color(red: 0.2, green: 0.78, blue: 0.45)
        case .finances:   return Color(red: 0.3, green: 0.6, blue: 1.0)
        case .documents:  return .orange
        case .elements:   return .purple
        case .appliances: return Color(red: 0.2, green: 0.55, blue: 0.95)
        case .plants:     return Color(red: 0.15, green: 0.75, blue: 0.40)
        }
    }
}

private struct ActivityEvent: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let date: Date
    let member: String
    let category: ActivityCategory
}

// MARK: - View

struct ActivityFeedView: View {
    @EnvironmentObject private var financialService:  FinancialService
    @EnvironmentObject private var documentService:   DocumentService
    @EnvironmentObject private var familyService:     FamilyService
    @EnvironmentObject private var appSettings:       AppSettings
    @EnvironmentObject private var taskService:       TaskService
    @EnvironmentObject private var elementService:    PropertyElementService
    @EnvironmentObject private var applianceService:  ApplianceService
    @EnvironmentObject private var plantService:      PlantService

    @State private var period:           ActivityPeriod   = .month
    @State private var selectedMember:   String?          = nil
    @State private var selectedCategory: ActivityCategory = .all

    private let currentUser = "You"

    // MARK: Event synthesis

    private var allEvents: [ActivityEvent] {
        var events: [ActivityEvent] = []
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let isoFull = ISO8601DateFormatter()

        // Finances
        for r in financialService.records {
            guard let date = iso.date(from: r.date) else { continue }
            let isIncome = r.type == "income"
            events.append(ActivityEvent(
                icon:     isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                color:    isIncome ? Color(red: 0.2, green: 0.78, blue: 0.45) : .red,
                title:    isIncome ? "Income added" : "Expense recorded",
                subtitle: "\(r.title) · \(financialService.currencySymbol)\(Int(r.amount))",
                date:     date,
                member:   currentUser,
                category: .finances
            ))
        }

        // Documents
        for doc in documentService.documents {
            let date = isoFull.date(from: doc.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     doc.categoryIcon,
                color:    .orange,
                title:    "Document added",
                subtitle: doc.name,
                date:     date,
                member:   currentUser,
                category: .documents
            ))
        }

        // Tasks
        let isoTask = makeISOParser()
        for task in taskService.tasks {
            let date = isoTask(task.updatedAt) ?? isoTask(task.createdAt) ?? Date()
            let taskMember = task.assigneeNames.first ?? currentUser
            if task.isCompleted {
                events.append(ActivityEvent(
                    icon:     "checkmark.circle.fill",
                    color:    Color(red: 0.2, green: 0.78, blue: 0.45),
                    title:    "Task completed",
                    subtitle: task.title,
                    date:     date,
                    member:   taskMember,
                    category: .tasks
                ))
            } else if let due = task.dueDate, let dueDate = isoTask(due), dueDate < Date() {
                events.append(ActivityEvent(
                    icon:     "exclamationmark.circle.fill",
                    color:    .red,
                    title:    "Task overdue",
                    subtitle: task.title,
                    date:     dueDate,
                    member:   taskMember,
                    category: .tasks
                ))
            } else {
                let created = isoTask(task.createdAt) ?? Date()
                events.append(ActivityEvent(
                    icon:     "clock.fill",
                    color:    .orange,
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
            if let wateredStr = plant.lastWateredAt, let wateredDate = isoTask(wateredStr) {
                events.append(ActivityEvent(
                    icon:     "drop.fill",
                    color:    Color(red: 0.15, green: 0.75, blue: 0.40),
                    title:    "Plant watered",
                    subtitle: plant.name,
                    date:     wateredDate,
                    member:   currentUser,
                    category: .plants
                ))
            }
            let addedDate = isoTask(plant.createdAt) ?? Date()
            let plantSubtitle = plant.emoji.isEmpty ? plant.name : "\(plant.emoji) \(plant.name)"
            events.append(ActivityEvent(
                icon:     "leaf.fill",
                color:    Color(red: 0.15, green: 0.75, blue: 0.40),
                title:    "Plant added",
                subtitle: plantSubtitle,
                date:     addedDate,
                member:   currentUser,
                category: .plants
            ))
        }

        // Property elements
        for el in elementService.elements {
            let date = isoTask(el.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     el.elementType.icon,
                color:    el.layer.color,
                title:    "Element added",
                subtitle: el.name,
                date:     date,
                member:   currentUser,
                category: .elements
            ))
        }

        // Appliances
        for ap in applianceService.appliances {
            let date = isoTask(ap.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     ap.categoryIcon,
                color:    Color(red: 0.2, green: 0.55, blue: 0.95),
                title:    "Appliance added",
                subtitle: [ap.brand, ap.name].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " "),
                date:     date,
                member:   currentUser,
                category: .appliances
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    private var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -period.days, to: Date()) ?? Date()
    }

    private var filteredEvents: [ActivityEvent] {
        allEvents
            .filter { $0.date >= cutoffDate }
            .filter { selectedMember == nil || $0.member == selectedMember }
            .filter { selectedCategory == .all || $0.category == selectedCategory }
    }

    private var groupedByDay: [(label: String, events: [ActivityEvent])] {
        let cal = Calendar.current
        let formatter = DateFormatter(); formatter.locale = .current
        let grouped = Dictionary(grouping: filteredEvents) {
            cal.startOfDay(for: $0.date)
        }
        return grouped.keys
            .sorted(by: >)
            .map { day in
                formatter.dateFormat = cal.isDateInToday(day) ? "'Today'" :
                    cal.isDateInYesterday(day) ? "'Yesterday'" : "d MMMM"
                return (formatter.string(from: day), (grouped[day] ?? []).sorted { $0.date > $1.date })
            }
    }

    // MARK: Members for filter

    private var allMembers: [String] {
        [currentUser] + familyService.members.map(\.name)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "Activity", subtitleKey: "PROPERTY")

            periodRow
                .padding(.horizontal, 20)
                .padding(.top, 8)

            categoryRow
                .padding(.top, 8)

            memberRow
                .padding(.top, 6)

            Divider().opacity(0.3).padding(.top, 8)

            if filteredEvents.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Period chips

    private var periodRow: some View {
        HStack(spacing: 6) {
            ForEach(ActivityPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { period = p }
                } label: {
                    Text(LocalizedStringKey(p.rawValue))
                        .font(.system(size: 12, weight: period == p ? .semibold : .regular))
                        .foregroundStyle(period == p ? .white : Color.primary.opacity(0.6))
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(period == p ? Color.accentColor : Color.primary.opacity(0.08),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(filteredEvents.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
    }

    // MARK: Category chips

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Spacer(minLength: 20)
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = cat }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(LocalizedStringKey(cat.rawValue))
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundStyle(isSelected ? cat.color : Color.primary.opacity(0.6))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(
                            isSelected ? cat.color.opacity(0.14) : Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(isSelected ? cat.color.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 20)
            }
        }
    }

    // MARK: Member filter

    private var memberRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Spacer(minLength: 20)
                ForEach(allMembers, id: \.self) { name in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMember = selectedMember == name ? nil : name
                        }
                    } label: {
                        HStack(spacing: 6) {
                            memberAvatar(name: name, size: 22)
                            Text(name)
                                .font(.system(size: 13, weight: selectedMember == name ? .semibold : .regular))
                                .foregroundStyle(selectedMember == name ? .blue : .primary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            selectedMember == name
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }

                if selectedMember != nil {
                    Button {
                        withAnimation { selectedMember = nil }
                    } label: {
                        Text("All")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20, pinnedViews: .sectionHeaders) {
                ForEach(groupedByDay, id: \.label) { group in
                    Section {
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { idx, event in
                                    eventRow(event, isLast: idx == group.events.count - 1)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } header: {
                        dayHeader(LocalizedStringKey(group.label))
                    }
                }
                Spacer(minLength: 100)
            }
            .padding(.top, 12)
        }
    }

    private func dayHeader(_ label: LocalizedStringKey) -> some View {
        HStack {
            Text(label).textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .background(appBackground)
    }

    private func eventRow(_ event: ActivityEvent, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(event.color.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: event.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(event.color)
                        .symbolRenderingMode(.hierarchical)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(event.title))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(event.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeString(event.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.35))
                    memberAvatar(name: event.member, size: 18)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 0.5)
                    .padding(.leading, 62)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No activity in this period")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("Activities appear automatically as you\nadd tasks, documents, and transactions.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: Helpers

    private func memberAvatar(name: String, size: CGFloat) -> some View {
        let member = familyService.members.first { $0.name == name }
        let color: Color = member.map { colorFromHex($0.color) } ?? .blue
        return ZStack {
            Circle().fill(color.opacity(0.2))
            Text(String(name.prefix(1)).uppercased())
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

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func makeISOParser() -> (String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return { str in f1.date(from: str) ?? f2.date(from: str) }
    }
}

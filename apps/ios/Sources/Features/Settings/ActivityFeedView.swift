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

private struct ActivityEvent: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let date: Date
    let member: String
}

// MARK: - View

struct ActivityFeedView: View {
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var documentService:  DocumentService
    @EnvironmentObject private var familyService:    FamilyService
    @EnvironmentObject private var appSettings:      AppSettings

    @State private var period: ActivityPeriod = .month
    @State private var selectedMember: String? = nil

    private let currentUser = "You"

    // MARK: Event synthesis

    private var allEvents: [ActivityEvent] {
        var events: [ActivityEvent] = []
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let isoFull = ISO8601DateFormatter()

        for r in financialService.records {
            guard let date = iso.date(from: r.date) else { continue }
            let isIncome = r.type == "income"
            events.append(ActivityEvent(
                icon:     isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                color:    isIncome ? Color(red: 0.2, green: 0.78, blue: 0.45) : .red,
                title:    isIncome ? "Income added" : "Expense recorded",
                subtitle: "\(r.title) · \(financialService.currencySymbol)\(Int(r.amount))",
                date:     date,
                member:   currentUser
            ))
        }

        for doc in documentService.documents {
            let date = isoFull.date(from: doc.createdAt) ?? Date()
            events.append(ActivityEvent(
                icon:     doc.categoryIcon,
                color:    .orange,
                title:    "Document added",
                subtitle: doc.name,
                date:     date,
                member:   currentUser
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    private var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -period.days, to: Date()) ?? Date()
    }

    private var filteredEvents: [ActivityEvent] {
        allEvents.filter { $0.date >= cutoffDate }
            .filter { selectedMember == nil || $0.member == selectedMember }
    }

    private var groupedByDay: [(label: String, events: [ActivityEvent])] {
        let cal = Calendar.current
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US")
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
        ([currentUser] + familyService.members.map(\.name))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Activity", subtitle: "PROPERTY")

            periodRow
                .padding(.horizontal, 20)
                .padding(.top, 8)

            memberRow
                .padding(.top, 10)

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
                    Text(p.rawValue)
                        .font(.system(size: 12, weight: period == p ? .semibold : .regular))
                        .foregroundStyle(period == p ? .white : Color.primary.opacity(0.6))
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(period == p ? Color.accentColor : Color.primary.opacity(0.08),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Member filter

    private var memberRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Spacer(minLength: 20)
                ForEach(allMembers, id: \.self) { name in
                    let isSelected = selectedMember == name || (selectedMember == nil && name == currentUser && allMembers.count == 1)
                    let isAll = selectedMember == nil
                    let pick = name == currentUser

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if name == currentUser && selectedMember == nil {
                                // already showing all — do nothing special
                            } else if selectedMember == name {
                                selectedMember = nil
                            } else {
                                selectedMember = name
                            }
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
                        dayHeader(group.label)
                    }
                }
                Spacer(minLength: 100)
            }
            .padding(.top, 12)
        }
    }

    private func dayHeader(_ label: String) -> some View {
        HStack {
            Text(label.uppercased())
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
                    Text(event.title)
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
}

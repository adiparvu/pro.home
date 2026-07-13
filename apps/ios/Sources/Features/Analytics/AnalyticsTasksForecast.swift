import SwiftUI
import Charts

// MARK: - Tasks Section

struct TasksSection: View {
    var service: TaskService
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService

    private var cal: Calendar { Calendar.current }

    // MARK: Priority / category breakdowns
    //
    // Persisted raw values go through the Tasks module's own style types
    // (TaskStyle.swift) so labels are LOCALIZED here — the chart used to plot
    // `priority.capitalized`, which printed raw English ("Medium") on a
    // Romanian device, and it counted a "urgent" value that doesn't exist in
    // the priority vocabulary (low/medium/high/critical), so critical tasks
    // vanished from the chart entirely.

    private var tasksByPriority: [(label: String, count: Int, color: Color)] {
        var counts: [TaskPriorityStyle: Int] = [:]
        for t in service.tasks { counts[t.priorityStyle, default: 0] += 1 }
        return TaskPriorityStyle.allCases.reversed().compactMap { p in
            guard let c = counts[p], c > 0 else { return nil }
            return (Self.priorityName(p), c, p.color)
        }
    }

    private var tasksByCategory: [(label: String, count: Int)] {
        var counts: [TaskCategoryStyle: Int] = [:]
        for t in service.tasks { counts[t.categoryStyle, default: 0] += 1 }
        return TaskCategoryStyle.allCases.compactMap { c in
            guard let n = counts[c], n > 0 else { return nil }
            return (Self.categoryName(c), n)
        }
        .sorted { $0.count > $1.count }
    }

    /// Resolved (not `LocalizedStringKey`) labels — Swift Charts plots plain
    /// strings, so localization must happen before the axis sees them.
    private static func priorityName(_ p: TaskPriorityStyle) -> String {
        switch p {
        case .low:      return String(localized: "Low")
        case .medium:   return String(localized: "Medium")
        case .high:     return String(localized: "High")
        case .critical: return String(localized: "Critical")
        }
    }

    private static func categoryName(_ c: TaskCategoryStyle) -> String {
        switch c {
        case .maintenance:    return String(localized: "Maintenance")
        case .repair:         return String(localized: "Repair")
        case .inspection:     return String(localized: "Inspection")
        case .cleaning:       return String(localized: "Cleaning")
        case .upgrade:        return String(localized: "Upgrade")
        case .administrative: return String(localized: "Administrative")
        case .other:          return String(localized: "Other")
        }
    }

    // MARK: Member completions
    //
    // Completed tasks per assignee — an honest "assigned and finished" count
    // (the backend records no separate "completed by"). Family surface only.

    private struct MemberCompletion: Identifiable {
        let id: String
        let member: FamilyMember?
        let name: String
        let count: Int
    }

    private var memberCompletions: [MemberCompletion] {
        var counts: [String: (member: FamilyMember?, name: String, count: Int)] = [:]
        for t in service.tasks where t.isCompleted {
            for (i, aid) in t.assigneeIds.enumerated() {
                let member = familyService.members.first { $0.id.uuidString == aid }
                let name = member?.name
                    ?? (i < t.assigneeNames.count ? t.assigneeNames[i] : "")
                guard member != nil || !name.isEmpty else { continue }
                var entry = counts[aid] ?? (member, name, 0)
                entry.count += 1
                counts[aid] = entry
            }
        }
        return counts
            .map { MemberCompletion(id: $0.key, member: $0.value.member,
                                    name: $0.value.name, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Time stats

    /// Total banked work-session seconds on tasks COMPLETED this month —
    /// `worked_seconds` is a per-task lifetime total with no timestamps, so
    /// the month attribution rides on the completion date and the caption
    /// says exactly that.
    private var workedThisMonth: TimeInterval {
        let now = Date()
        return service.tasks.reduce(0) { acc, t in
            guard t.isCompleted, t.workedSeconds > 0,
                  let done = AppDate.timestamp(from: t.updatedAt),
                  cal.isDate(done, equalTo: now, toGranularity: .month) else { return acc }
            return acc + TimeInterval(t.workedSeconds)
        }
    }

    /// Mean creation→completion interval over completed tasks (completion =
    /// the status change's `updated_at`, the same signal "Done/7d" uses).
    /// Needs at least three completions to say anything.
    private var averageCompletion: TimeInterval? {
        let intervals: [TimeInterval] = service.tasks.compactMap { t in
            guard t.isCompleted,
                  let created = AppDate.timestamp(from: t.createdAt),
                  let done = AppDate.timestamp(from: t.updatedAt),
                  done > created else { return nil }
            return done.timeIntervalSince(created)
        }
        guard intervals.count >= 3 else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    var completionRate: Double {
        guard !service.tasks.isEmpty else { return 0 }
        return Double(service.tasks.filter(\.isCompleted).count) / Double(service.tasks.count) * 100
    }

    // MARK: Body

    var body: some View {
        let priorities = tasksByPriority
        let categories = tasksByCategory
        let members = memberCompletions
        let worked = workedThisMonth
        let avgCompletion = averageCompletion

        VStack(spacing: 16) {
            HStack(spacing: 10) {
                TrendKPICard(label: "Open", value: "\(service.openCount)", icon: "circle", trendPct: nil, trendPositive: true)
                TrendKPICard(label: "Overdue", value: "\(service.overdueCount)", icon: "exclamationmark.circle",
                             trendPct: nil, trendPositive: service.overdueCount == 0,
                             highlightValue: service.overdueCount > 0, positiveValue: false)
                TrendKPICard(label: "Done/7d", value: "\(service.completedThisWeek)", icon: "checkmark.circle.fill",
                             trendPct: nil, trendPositive: true, highlightValue: service.completedThisWeek > 0, positiveValue: true)
            }

            completionCard

            if worked > 0 || avgCompletion != nil {
                HStack(spacing: 10) {
                    if worked > 0 {
                        timeStatCard(icon: "timer",
                                     value: worked.workedTotalDisplay,
                                     label: "ana_hours_worked",
                                     sub: "ana_hours_worked_sub")
                    }
                    if let avgCompletion,
                       let display = Self.durationFormatter.string(from: avgCompletion) {
                        timeStatCard(icon: "clock.arrow.circlepath",
                                     value: display,
                                     label: "ana_avg_completion",
                                     sub: "ana_avg_completion_sub")
                    }
                }
            }

            if !priorities.isEmpty {
                barChartCard(header: "By priority") {
                    Chart(priorities, id: \.label) { item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Priority", item.label)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [item.color.opacity(0.9), item.color.opacity(0.6)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(6)
                    }
                }
            }

            if !categories.isEmpty {
                barChartCard(header: "ana_tasks_by_category") {
                    Chart(categories, id: \.label) { item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Category", item.label)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [Color.brandPrimaryBlue.opacity(0.9),
                                                    Color.brandPrimaryBlue.opacity(0.55)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(6)
                    }
                }
            }

            if propertyService.isFamilyMember, !members.isEmpty {
                memberCard(members)
            }
        }
    }

    // MARK: Cards

    private var completionCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Completion rate")
                        .font(AppFont.subheadline)
                    Spacer()
                    Text(String(format: "%.0f%%", completionRate))
                        .font(AppFont.scaled(18, weight: .bold))
                        .foregroundStyle(completionRate >= 70 ? Color.brandSuccess : .orange)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 10)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.blue, Color.brandSuccess],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * (completionRate / 100), height: 10)
                            .animation(.spring(response: 0.7), value: completionRate)
                    }
                }
                .frame(height: 10)
            }
        }
    }

    private func timeStatCard(icon: String, value: String,
                              label: LocalizedStringKey, sub: LocalizedStringKey) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(verbatim: value)
                    .font(AppFont.scaled(17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(label)
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(AppFont.scaled(10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func barChartCard<C: View>(header: LocalizedStringKey,
                                       @ViewBuilder chart: @escaping () -> C) -> some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(header)
                    .font(AppFont.subheadline)

                chart()
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                                .foregroundStyle(Color.primary.opacity(0.05))
                            AxisValueLabel().foregroundStyle(.secondary).font(AppFont.scaled(10))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.secondary).font(AppFont.scaled(11))
                        }
                    }
                    .frame(height: 110)
            }
        }
    }

    private func memberCard(_ members: [MemberCompletion]) -> some View {
        let top = members.first?.count ?? 1
        return GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ana_tasks_by_member")
                        .font(AppFont.subheadline)
                    Text("ana_tasks_by_member_sub")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }

                ForEach(members) { entry in
                    HStack(spacing: AppSpacing.md) {
                        if let member = entry.member {
                            MemberAvatar(member: member, size: 30)
                        } else {
                            initialsAvatar(entry.name)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: entry.name)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Capsule()
                                .fill(Color.brandSuccess.opacity(0.15))
                                .frame(height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.brandSuccess)
                                        .scaleEffect(x: max(0.02, top > 0 ? Double(entry.count) / Double(top) : 0),
                                                     y: 1, anchor: .leading)
                                }
                                .clipShape(Capsule())
                        }

                        Text(verbatim: "\(entry.count)")
                            .font(AppFont.scaled(15, weight: .bold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func initialsAvatar(_ name: String) -> some View {
        let parts = name.split(separator: " ")
        let initials = parts.count >= 2
            ? String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
            : String(name.prefix(2)).uppercased()
        return Text(verbatim: initials)
            .font(AppFont.scaled(11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.08), in: Circle())
    }
}

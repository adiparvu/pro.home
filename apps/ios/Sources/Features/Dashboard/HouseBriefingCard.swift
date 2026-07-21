import SwiftUI
import WeatherKit

// MARK: - House Briefing — the dashboard's composed "state of the home" card
//
// A deterministic, on-device composition — no LLM, no network of its own.
// Every line is a fact from a service the startup orchestration already
// loaded: Apple Weather, the house agenda's next entry, today's tasks, live
// deliveries and family presence. Facts render only when they exist; with
// nothing to report the card says "all calm" honestly instead of padding
// itself with filler.

struct HouseBriefingCard: View {
    /// The repaired dashboard agenda entry (now includes calendar events).
    let nextItem: AgendaItem?
    /// Half-width tiles get the lead + top fact only.
    var compact: Bool = false

    @Environment(TaskService.self) private var taskService
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(FamilyService.self) private var familyService
    @Environment(PresenceService.self) private var presenceService
    @Environment(PropertyService.self) private var propertyService

    var body: some View {
        // Minute clock: presence windows, "due today" and the rain hour all
        // drift with real time — re-evaluate while visible instead of
        // freezing at first render.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        // Yuna's server-side take arrives once per day (cached), added under
        // the deterministic facts — never replacing them.
        .task(id: propertyService.primary?.id) {
            await AriaBriefingService.shared.refreshIfStale(
                propertyId: propertyService.primary?.id)
        }
    }

    private func content(now: Date) -> some View {
        let facts = Array(facts(now: now).prefix(compact ? 1 : 4))
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("House Briefing")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(leadKey(now: now))
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if facts.isEmpty {
                factRow(icon: "checkmark.circle.fill", tint: Color.brandSuccess,
                        text: Text("All calm at home today."))
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(facts) { fact in
                        factRow(icon: fact.icon, tint: fact.tint, text: fact.text)
                    }
                }
            }

            // Yuna's daily take — grounded AI prose over the same data the
            // owner allowed the assistant to see. Facts above stay authoritative;
            // this is the butler's voice, once a day.
            if !compact, let take = AriaBriefingService.shared.briefing {
                Divider().overlay(Color.hairline)
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.brandPurple)
                        .frame(width: 20)
                    Text(verbatim: take)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
    }

    private func factRow(icon: String, tint: Color, text: Text) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 20)
            text
                .font(AppFont.scaled(13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Composition

    private func leadKey(now: Date) -> LocalizedStringKey {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12:  return "Here's how your home starts the day."
        case 12..<18: return "Your home right now."
        default:      return "Your home this evening."
        }
    }

    private struct Fact: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let text: Text
    }

    /// Ordered by usefulness: weather ambience, imminent rain, the next
    /// agenda entry, today's workload, packages, who's around.
    private func facts(now: Date) -> [Fact] {
        var facts: [Fact] = []
        let weather = WeatherKitService.shared

        if weather.currentWeather != nil {
            facts.append(Fact(
                id: "weather", icon: weather.conditionSymbol, tint: Color.accentColor,
                text: Text(verbatim: "\(weather.temperatureString) · ")
                    + Text(verbatim: weather.conditionDescription)))
        }
        if let rainHour = weather.hourlyForecast
            .first(where: { $0.date > now && $0.date < now.addingTimeInterval(12 * 3600)
                            && $0.precipitationChance >= 0.5 })?.date {
            let hour = rainHour.formatted(date: .omitted, time: .shortened)
            facts.append(Fact(
                id: "rain", icon: "cloud.rain.fill", tint: Color.brandSkyBlue,
                text: Text("Rain expected around \(hour)")))
        }
        if let item = nextItem {
            let when = item.hasTime
                ? item.date.formatted(date: .omitted, time: .shortened)
                : item.date.formatted(.dateTime.weekday(.wide))
            facts.append(Fact(
                id: "next", icon: "calendar.badge.clock", tint: Color.brandPurple,
                text: Text("Next: \(item.title)") + Text(verbatim: " · \(when)")))
        }
        let overdue = taskService.overdueCount
        let dueToday = tasksDueToday(now: now)
        if overdue > 0 {
            facts.append(Fact(
                id: "overdue", icon: "exclamationmark.circle.fill", tint: Color.brandWarning,
                text: overdue == 1 ? Text("One task overdue")
                                   : Text("\(overdue) tasks overdue")))
        } else if dueToday > 0 {
            facts.append(Fact(
                id: "due", icon: "checklist", tint: Color.accentColor,
                text: dueToday == 1 ? Text("One task due today")
                                    : Text("\(dueToday) tasks due today")))
        }
        let deliveries = deliveryService.activeDeliveries.count
        if deliveries > 0 {
            facts.append(Fact(
                id: "packages", icon: "shippingbox.fill", tint: Color.brandSkyBlue,
                text: deliveries == 1 ? Text("One delivery on the way")
                                      : Text("\(deliveries) deliveries on the way")))
        }
        let online = onlineFamilyCount(now: now)
        if online > 0 {
            facts.append(Fact(
                id: "online", icon: "person.2.fill", tint: Color.brandSuccess,
                text: online == 1 ? Text("One family member online")
                                  : Text("\(online) family members online")))
        }
        return facts
    }

    private func tasksDueToday(now: Date) -> Int {
        let cal = Calendar.current
        return taskService.tasks.filter { task in
            guard !task.isCompleted, task.status != "cancelled",
                  let ds = task.dueDate, let due = MaintenanceTask.parseDate(ds)
            else { return false }
            return cal.isDate(due, inSameDayAs: now)
        }.count
    }

    private func onlineFamilyCount(now: Date) -> Int {
        familyService.members.filter { member in
            member.isFamilyCore
                && presenceService.status(userId: member.userId,
                                          name: member.name, at: now) == .online
        }.count
    }
}

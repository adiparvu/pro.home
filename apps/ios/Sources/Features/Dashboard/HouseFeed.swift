import SwiftUI

// MARK: - "Today at home" — the house's chronological feed
//
// A focused, day-scoped sibling of the Settings activity feed: the same
// honest client-side synthesis (no new tables, no invented timestamps), but
// scoped to today/yesterday and extended with the sources the long-lookback
// feed doesn't carry — delivery tracking checkpoints and house-calendar
// events. `HouseFeedEngine` is a pure composer over already-loaded services,
// so the widget, the page and any future surface can never drift apart.

// MARK: Event

struct HouseFeedEvent: Identifiable {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: String
    let date: Date
    /// False when the source stores only a calendar day — the row then
    /// shows no fictitious "00:00".
    let hasTime: Bool

    var id: String { "\(icon)|\(subtitle)|\(Int(date.timeIntervalSince1970))" }
}

// MARK: Engine

@MainActor
enum HouseFeedEngine {

    /// Everything that HAPPENED on `day`, newest first. Every entry comes
    /// from a real stored timestamp on data the world reload already holds.
    static func events(on day: Date,
                       tasks: TaskService,
                       financial: FinancialService,
                       documents: DocumentService,
                       plants: PlantService,
                       deliveries: DeliveryService,
                       journal: PhotoJournalService,
                       calendar calendarEvents: [CalendarEvent]) -> [HouseFeedEvent] {
        let cal = Calendar.current
        var events: [HouseFeedEvent] = []

        func onDay(_ date: Date) -> Bool { cal.isDate(date, inSameDayAs: day) }

        // Tasks completed (status flip stamps updated_at) + tasks created.
        for task in tasks.tasks {
            if task.isCompleted, let done = AppDate.timestamp(from: task.updatedAt), onDay(done) {
                events.append(HouseFeedEvent(
                    icon: "checkmark.circle.fill", tint: .brandSuccess,
                    title: "Task completed", subtitle: task.title,
                    date: done, hasTime: true))
            } else if let created = AppDate.timestamp(from: task.createdAt), onDay(created) {
                events.append(HouseFeedEvent(
                    icon: "plus.circle.fill", tint: .brandPrimaryBlue,
                    title: "Task added", subtitle: task.title,
                    date: created, hasTime: true))
            }
        }

        // Money moved (record dates are calendar days).
        for record in financial.records {
            guard let date = AppDate.day(from: record.date), onDay(date) else { continue }
            let isIncome = record.type == "income"
            events.append(HouseFeedEvent(
                icon: isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                tint: .brandSuccess,
                title: isIncome ? "Income added" : "Expense recorded",
                subtitle: "\(record.title) · \(financial.moneyDisplay(record.amount))",
                date: date, hasTime: record.date.count > 10))
        }

        // Documents filed.
        for doc in documents.documents {
            guard let date = AppDate.timestamp(from: doc.createdAt), onDay(date) else { continue }
            events.append(HouseFeedEvent(
                icon: "doc.fill", tint: .brandWarning,
                title: "Document added", subtitle: doc.name,
                date: date, hasTime: true))
        }

        // Plants watered.
        for plant in plants.plants {
            guard let watered = plant.lastWateredAt,
                  let date = AppDate.timestamp(from: watered), onDay(date) else { continue }
            events.append(HouseFeedEvent(
                icon: "drop.fill", tint: .brandSkyBlue,
                title: "Plant watered", subtitle: plant.name,
                date: date, hasTime: true))
        }

        // Delivery movement — the tracker's own last-event stamp, so the
        // row reflects the courier's real update, not our refresh clock.
        for delivery in deliveries.deliveries {
            guard let stamp = delivery.lastEventAt,
                  let date = AppDate.timestamp(from: stamp), onDay(date) else { continue }
            events.append(HouseFeedEvent(
                icon: "shippingbox.fill", tint: .brandSkyBlue,
                title: "Delivery update",
                subtitle: "\(delivery.description) · \(delivery.liveStatusLabel ?? delivery.statusLabel)",
                date: date, hasTime: true))
        }

        // Journal photos.
        for entry in journal.entries {
            guard let date = AppDate.timestamp(from: entry.takenAt)
                    ?? AppDate.day(from: entry.takenAt), onDay(date) else { continue }
            events.append(HouseFeedEvent(
                icon: "photo.fill", tint: .brandPurple,
                title: "Journal photo", subtitle: entry.title,
                date: date, hasTime: entry.takenAt.count > 10))
        }

        // House-calendar events scheduled on this day.
        for event in calendarEvents {
            guard let date = AppDate.timestamp(from: event.startsAt)
                    ?? AppDate.day(from: event.startsAt), onDay(date) else { continue }
            events.append(HouseFeedEvent(
                icon: "calendar", tint: .orange,
                title: "Event", subtitle: event.title,
                date: date, hasTime: !event.allDay))
        }

        return events.sorted { $0.date > $1.date }
    }
}

// MARK: - Widget card (full-width)

struct TodayAtHomeCard: View {
    var compact: Bool = false
    let onOpen: () -> Void

    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(PlantService.self) private var plantService
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(CalendarEventService.self) private var calendarEventService

    var body: some View {
        let events = Array(todayEvents().prefix(compact ? 2 : 3))
        Button {
            HapticFeedback.impact(.light)
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Today at home")
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                if events.isEmpty {
                    Text("Nothing yet today.")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(events) { event in
                            HouseFeedRow(event: event, dense: true)
                        }
                    }
                }
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func todayEvents() -> [HouseFeedEvent] {
        HouseFeedEngine.events(on: Date(),
                               tasks: taskService, financial: financialService,
                               documents: documentService, plants: plantService,
                               deliveries: deliveryService, journal: photoJournalService,
                               calendar: calendarEventService.events)
    }
}

// MARK: - Shared row

struct HouseFeedRow: View {
    let event: HouseFeedEvent
    var dense: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: event.icon)
                .font(AppFont.scaled(dense ? 12 : 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(event.tint)
                .frame(width: dense ? 20 : 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(AppFont.scaled(dense ? 13 : 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: event.subtitle)
                    .font(AppFont.scaled(dense ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: AppSpacing.xs)
            if event.hasTime {
                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(AppFont.scaled(dense ? 11 : 12))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Full page (routed)

struct HouseFeedView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(PlantService.self) private var plantService
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(CalendarEventService.self) private var calendarEventService

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    daySection(titleKey: "Today", day: Date())
                    daySection(titleKey: "Yesterday",
                               day: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
            }
        }
        .navigationTitle(Text("Today at home"))
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func daySection(titleKey: LocalizedStringKey, day: Date) -> some View {
        let events = HouseFeedEngine.events(on: day,
                                            tasks: taskService, financial: financialService,
                                            documents: documentService, plants: plantService,
                                            deliveries: deliveryService, journal: photoJournalService,
                                            calendar: calendarEventService.events)
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(titleKey)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            if events.isEmpty {
                Text("Nothing yet today.")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppSpacing.sm)
            } else {
                GlassCard {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(events) { event in
                            HouseFeedRow(event: event)
                        }
                    }
                }
            }
        }
    }
}

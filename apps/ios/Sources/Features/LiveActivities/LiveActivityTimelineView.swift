import SwiftUI

// MARK: - Live Activity Timeline
//
// A day-grouped, animated journal of the REAL Live Activity event log kept
// by LiveActivityHubStore (started / updated / ended / completed). Nothing
// here is synthesized: every row is one recorded event, rendered with the
// kind's canonical icon and tint and the exact recorded time.

struct LiveActivityTimelineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: LiveActivityHubStore { .shared }

    private var sections: [(day: Date, events: [LiveActivityHubStore.LAEvent])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.events) { cal.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, events: grouped[day, default: []].sorted { $0.at > $1.at })
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.lg) {
                if store.events.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath",
                                   title: "la_timeline_empty")
                        .padding(.top, 60)
                } else {
                    ForEach(sections, id: \.day) { section in
                        daySection(section.day, events: section.events)
                            .transition(reduceMotion
                                        ? .opacity
                                        : .move(edge: .top).combined(with: .opacity))
                    }
                }
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: store.events)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("la_timeline_title")
        .navigationBarTitleDisplayMode(.large)
        .task { store.reloadEvents() }
    }

    // MARK: Day section

    private func daySection(_ day: Date,
                            events: [LiveActivityHubStore.LAEvent]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            dayTitle(day)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            GlassCard(padding: AppSpacing.lg, cornerRadius: AppRadius.xl) {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                        TimelineEventRow(event: event,
                                         isLast: idx == events.count - 1)
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> Text {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Text("la_timeline_today") }
        if cal.isDateInYesterday(day) { return Text("la_timeline_yesterday") }
        return Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
    }
}

// MARK: - One event row (time · rail dot · icon · title · phase)

private struct TimelineEventRow: View {
    let event: LiveActivityHubStore.LAEvent
    let isLast: Bool

    private var kind: LiveActivityKind? { LiveActivityKind(rawValue: event.kind) }
    private var tint: Color { kind?.color ?? .secondary }

    private var phaseLabel: LocalizedStringKey {
        switch event.phase {
        case "started":   return "la_timeline_started"
        case "updated":   return "la_timeline_updated"
        case "ended":     return "la_timeline_ended"
        case "completed": return "la_timeline_completed"
        default:          return LocalizedStringKey(event.phase)
        }
    }

    private var phaseColor: Color {
        switch event.phase {
        case "started":   return tint
        case "completed": return .brandSuccess
        default:          return Color.secondaryTextColor
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text(event.at, format: .dateTime.hour().minute())
                .font(AppFont.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.secondaryTextColor)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, AppSpacing.sm)

            // Vertical rail: a tinted dot, joined to the next row by a line.
            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .padding(.top, AppSpacing.sm + 3)
                if !isLast {
                    Rectangle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 2)
                }
            }
            .frame(width: 12)

            Image(systemName: kind?.icon ?? "bolt.badge.clock.fill")
                .font(AppFont.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(AppOpacity.tintedFill), in: Circle())
                .padding(.top, AppSpacing.xs)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(phaseLabel)
                    .font(AppFont.caption2)
                    .foregroundStyle(phaseColor)
            }
            .padding(.vertical, AppSpacing.sm)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

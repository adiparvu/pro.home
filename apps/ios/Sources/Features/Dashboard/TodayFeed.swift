import SwiftUI

// MARK: - "Today" — the dashboard's actionable heart
//
// The home screen doesn't report numbers; it answers "what matters today?".
// Today's items come from the same signals the notification generator uses
// (tasks due/overdue, plants to water, packages arriving, birthdays), shown
// as at most three Reminders-style rows you can complete in place. Tasks
// that live on the map also pulse on the hero photo — the day happens ON
// the property, not under it.

struct TodayItem: Identifiable {
    enum Kind {
        case task(MaintenanceTask)
        case plant(Plant)
        case delivery(Delivery)
        case birthday(FamilyMember)
    }

    let kind: Kind
    let icon: String
    let tint: Color
    let title: String
    let subtitle: LocalizedStringKey
    let urgent: Bool
    /// Anchors the item to its element pin on the hero photo, when it has one.
    let elementId: UUID?
    /// True when the row can be completed in place (task done, plant watered).
    let completable: Bool

    var id: String {
        switch kind {
        case .task(let t):     return "task-\(t.id)"
        case .plant(let p):    return "plant-\(p.id)"
        case .delivery(let d): return "delivery-\(d.id)"
        case .birthday(let m): return "bday-\(m.id)"
        }
    }
}

enum TodayFeed {
    /// Everything that needs the user today, most urgent first.
    static func items(tasks: [MaintenanceTask],
                      plants: [Plant],
                      deliveries: [Delivery],
                      members: [FamilyMember]) -> [TodayItem] {
        var result: [TodayItem] = []
        let todayPrefix = Self.todayPrefix()

        for t in tasks where !t.isCompleted && t.status != "cancelled" {
            let dueToday = t.dueDate?.hasPrefix(todayPrefix) ?? false
            guard t.isOverdue || dueToday else { continue }
            let urgent = t.isOverdue || t.priority == "urgent" || t.priority == "high"
            result.append(TodayItem(
                kind: .task(t),
                icon: "checkmark.circle",
                tint: urgent ? Color.brandDanger : Color.brandWarning,
                title: t.title,
                subtitle: t.isOverdue ? "Overdue" : "Due today",
                urgent: urgent,
                elementId: t.elementId,
                completable: true
            ))
        }

        for p in plants where p.needsWatering {
            result.append(TodayItem(
                kind: .plant(p),
                icon: "drop.fill",
                tint: Color.brandSkyBlue,
                title: p.name,
                subtitle: "Needs watering",
                urgent: false,
                elementId: nil,
                completable: true
            ))
        }

        for d in deliveries where (d.liveStatus ?? d.status) == "out_for_delivery" {
            result.append(TodayItem(
                kind: .delivery(d),
                icon: "shippingbox.fill",
                tint: Color.brandPrimaryBlue,
                title: d.description,
                subtitle: "Arriving today",
                urgent: false,
                elementId: nil,
                completable: false
            ))
        }

        let cal = Calendar.current
        let now = Date()
        for m in members {
            guard let bd = m.birthdayDate,
                  cal.component(.month, from: bd) == cal.component(.month, from: now),
                  cal.component(.day, from: bd) == cal.component(.day, from: now) else { continue }
            result.append(TodayItem(
                kind: .birthday(m),
                icon: "gift.fill",
                tint: .pink,
                title: m.name,
                subtitle: "Birthday today",
                urgent: false,
                elementId: nil,
                completable: false
            ))
        }

        return result.sorted { $0.urgent && !$1.urgent }
    }

    private static func todayPrefix() -> String {
        AppDate.dayString(from: Date())
    }
}

// MARK: - Today row (Reminders-style: complete in place)

struct TodayRow: View {
    let item: TodayItem
    var onComplete: () -> Void = {}
    var onOpen: () -> Void = {}

    @State private var completing = false

    var body: some View {
        HStack(spacing: 12) {
            if item.completable {
                Button {
                    guard !completing else { return }
                    HapticFeedback.success()
                    withAnimation(.snappy) { completing = true }
                    onComplete()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(item.tint.opacity(completing ? 0 : 0.7), lineWidth: 1.8)
                        if completing {
                            Circle().fill(item.tint)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark done")
            } else {
                Image(systemName: item.icon)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(item.tint)
                    .frame(width: 26, height: 26)
            }

            Button(action: onOpen) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .strikethrough(completing, color: .secondary)
                        Text(item.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(item.urgent ? item.tint : Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                    if !item.completable {
                        Image(systemName: "chevron.right")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(0.3))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .opacity(completing ? 0.55 : 1)
    }
}

// MARK: - Today card (rows + reward-style empty state)

struct TodayCard: View {
    let items: [TodayItem]
    /// Shown when there are more items than the card displays.
    let overflowCount: Int
    var onComplete: (TodayItem) -> Void = { _ in }
    var onOpen: (TodayItem) -> Void = { _ in }
    var onOverflow: () -> Void = {}

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        TodayRow(
                            item: item,
                            onComplete: { onComplete(item) },
                            onOpen: { onOpen(item) }
                        )
                        if idx < items.count - 1 || overflowCount > 0 {
                            Rectangle().fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                    }
                    if overflowCount > 0 {
                        Button {
                            HapticFeedback.impact(.light)
                            onOverflow()
                        } label: {
                            Text("+\(overflowCount) more")
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(AppFont.headline)
                .foregroundStyle(Color.brandSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text("All clear today")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text("Nothing needs you right now — enjoy your home.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 14)
    }
}

// MARK: - Hero status pill (the health story, in one sentence)

struct HeroStatusPill: View {
    let todayCount: Int
    let healthScore: Int
    var onTap: () -> Void = {}

    private var allClear: Bool { todayCount == 0 }
    private var tint: Color {
        if allClear { return Color.brandSuccess }
        return todayCount > 2 ? Color.brandDanger : Color.brandWarning
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: allClear ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(tint)
                if allClear {
                    Text("All clear today")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.white)
                } else {
                    Text("\(todayCount) for today")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Circle().fill(.white.opacity(0.35)).frame(width: 3, height: 3)
                Text(verbatim: "\(healthScore)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(healthColor)
            }
            .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(allClear ? "All clear today" : "Things to do today")
    }

    private var healthColor: Color {
        switch healthScore {
        case 80...:   return Color.brandSuccess
        case 50..<80: return .orange
        default:      return Color.brandDanger
        }
    }
}

import SwiftUI

// MARK: - Live dashboard widgets — presence & budget
//
// Two half-tile widgets that surface services the dashboard never showed:
// PresenceService (who's online right now, Find My-style avatars) and the
// property budget (this month's spend against the configured limits). Both
// mirror HomeWidget's exact card anatomy — icon/ornament row, big value,
// subtitle, title — so the grid reads as one family.

// MARK: Family presence

struct FamilyPresenceWidget: View {
    let action: () -> Void

    @Environment(FamilyService.self) private var familyService
    @Environment(PresenceService.self) private var presenceService

    var body: some View {
        // Presence statuses are time-window based (90 s heartbeat window) —
        // re-evaluate on a slow clock while visible.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        let members = rankedMembers(now: now)
        let online = members.filter { isOnline($0, now: now) }.count
        return Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    avatarStack(Array(members.prefix(4)), now: now)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(online)")
                        .font(AppFont.scaled(22, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(online > 0 ? String(localized: "online now")
                                    : String(localized: "no one online"))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("Presence")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text("Presence"))
        .accessibilityValue(Text(verbatim: "\(online)"))
    }

    /// Online members first so the visible avatar row always shows life
    /// when there is any.
    private func rankedMembers(now: Date) -> [FamilyMember] {
        familyService.members
            .filter(\.isFamilyCore)
            .sorted { isOnline($0, now: now) && !isOnline($1, now: now) }
    }

    private func isOnline(_ member: FamilyMember, now: Date) -> Bool {
        presenceService.status(userId: member.userId, name: member.name, at: now) == .online
    }

    private func avatarStack(_ members: [FamilyMember], now: Date) -> some View {
        HStack(spacing: -10) {
            ForEach(members) { member in
                MemberAvatar(member: member, size: 34)
                    .overlay(alignment: .bottomTrailing) {
                        if isOnline(member, now: now) {
                            Circle()
                                .fill(Color.brandSuccess)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        }
                    }
            }
        }
    }
}

// MARK: Budget ring

struct BudgetRingWidget: View {
    let action: () -> Void

    @Environment(FinancialService.self) private var financialService
    @Environment(BudgetService.self) private var budgetService

    /// This month's spending, household currency only — the same honesty
    /// rule the Watch complication applies (a EUR bill never inflates a
    /// RON total).
    private var spent: Double {
        let currency = financialService.currency
        return financialService.currentMonthRecords
            .filter { $0.type == "expense" && $0.currency == currency }
            .reduce(0) { $0 + $1.amount }
    }

    private var limit: Double { budgetService.totalBudget() }

    private var progress: Double { limit > 0 ? spent / limit : 0 }

    private var ringColor: Color {
        switch progress {
        case ..<0.8:  return Color.accentColor
        case ..<1.0:  return Color.brandWarning
        default:      return Color.brandDanger
        }
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if limit > 0 {
                        ring
                    } else {
                        Image(systemName: "chart.pie.fill")
                            .font(AppFont.scaled(22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(limit > 0 ? financialService.moneyDisplay(spent) : "–")
                        .font(AppFont.scaled(22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    subtitle
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("Budget")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text("Budget"))
        .accessibilityValue(Text(verbatim: limit > 0
            ? "\(Int(progress * 100))%" : ""))
    }

    private var subtitle: Text {
        if limit <= 0 { return Text("Set a budget") }
        if progress > 1 { return Text("over budget") }
        return Text("of \(financialService.moneyDisplay(limit))")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.subtleFill, lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(Int(min(progress, 9.99) * 100))%")
                .font(AppFont.scaled(9, weight: .bold))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 36, height: 36)
    }
}

import SwiftUI

// MARK: - "Who's home" — the geofenced family card (wave 3B)
//
// Renders the household's real home/away states from HomePresenceService
// (migration 160). Honest degradations: with nobody opted in it says how to
// turn the feature on instead of showing an empty guess; rows exist only
// for members who chose to share.

struct WhoIsHomeCard: View {
    let action: () -> Void

    @Environment(FamilyService.self) private var familyService

    private var service: HomePresenceService { HomePresenceService.shared }

    var body: some View {
        // Minute clock: the "since" sublines drift with real time.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        // Home first, then away — the visible row answers the question.
        let rows = service.household.sorted { $0.isHome && !$1.isHome }
        let homeCount = rows.filter(\.isHome).count
        return Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if rows.isEmpty {
                        Image(systemName: "location.fill.viewfinder")
                            .font(AppFont.scaled(22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                    } else {
                        avatarStack(Array(rows.prefix(4)))
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 2) {
                    if rows.isEmpty {
                        Text(verbatim: "–")
                            .font(AppFont.scaled(22, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("whohome_enable_hint")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(homeCount)")
                            .font(AppFont.scaled(22, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(subtitle(rows: rows, now: now))
                            .font(AppFont.scaled(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text("Who's home")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Who's home"))
        .accessibilityValue(Text(verbatim: rows.isEmpty ? "" : "\(homeCount)"))
    }

    /// "at home now" with the freshest arrival's time when one exists —
    /// region monitoring is minute-grained, so the copy says "since ~".
    private func subtitle(rows: [HomePresenceRow], now: Date) -> String {
        if let latest = rows.first(where: \.isHome)?.sinceDate {
            let time = latest.formatted(date: .omitted, time: .shortened)
            return String(localized: "home since ~\(time)")
        }
        return String(localized: "nobody home now")
    }

    private func avatarStack(_ rows: [HomePresenceRow]) -> some View {
        HStack(spacing: -10) {
            ForEach(rows) { row in
                Group {
                    if let member = familyService.members.first(where: { $0.userId == row.userId }) {
                        MemberAvatar(member: member, size: 34)
                    } else {
                        // Opted-in member without a roster row (edge case):
                        // initials on a neutral disc, never a blank.
                        ZStack {
                            Circle().fill(Color.subtleFill)
                            Text(verbatim: String(row.userName.prefix(2)).uppercased())
                                .font(AppFont.scaled(11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 34, height: 34)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(row.isHome ? Color.brandSuccess : Color.secondary.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }
            }
        }
    }
}

import SwiftUI

// MARK: - Savings goal progress card (mockup FullSizeRender)
//
// One goal at a glance: colored icon disc, title + per-member pledge, percent,
// a tinted progress bar, and the Collected / Remaining / Total triad. Every
// number comes from `SavingsGoalProgress` (the real ledger) — the honesty law.

struct SavingsGoalCard: View {
    let progress: SavingsGoalProgress

    private var goal: SavingsGoal { progress.goal }

    var body: some View {
        VStack(spacing: AppSpacing.base) {
            header
            ProgressBar(fraction: progress.fraction, tint: goal.tint)
            triad
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(goal.title), \(progress.percent)%"))
    }

    private var header: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(goal.tint.opacity(AppOpacity.tintedFill))
                Image(systemName: goal.iconName)
                    .font(AppFont.scaled(18, weight: .semibold))
                    .foregroundStyle(goal.tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: goal.title)
                    .font(AppFont.scaled(18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let pledge = goal.monthlyPerMember, pledge > 0 {
                    Text(String(format: String(localized: "goal_per_member_fmt"),
                                CurrencyService.money(pledge, code: goal.currency, whole: true)))
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "\(progress.percent)%")
                    .font(AppFont.scaled(24, weight: .bold))
                    .foregroundStyle(goal.tint)
                    .monospacedDigit()
                Text("goal_of_target")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
            }
        }
    }

    private var triad: some View {
        HStack(alignment: .top) {
            stat("goal_collected",
                 CurrencyService.money(progress.collected, code: goal.currency, whole: true),
                 alignment: .leading)
            Spacer()
            VStack(spacing: 2) {
                Text("goal_remaining_label")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                remainingValue
            }
            Spacer()
            stat("goal_total",
                 CurrencyService.money(goal.targetAmount, code: goal.currency, whole: true),
                 alignment: .trailing)
        }
    }

    @ViewBuilder private var remainingValue: some View {
        if progress.isComplete {
            Text("goal_done").font(AppFont.scaled(17, weight: .bold)).foregroundStyle(Color.brandSuccess)
        } else if let m = progress.monthsRemaining {
            Text(String(format: String(localized: "goal_months_left_fmt"), m))
                .font(AppFont.scaled(17, weight: .bold)).foregroundStyle(goal.tint).monospacedDigit()
        } else {
            // No proven pace — show the amount left, never a fabricated ETA.
            Text(CurrencyService.money(progress.remaining, code: goal.currency, whole: true))
                .font(AppFont.scaled(17, weight: .bold)).foregroundStyle(.primary).monospacedDigit()
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String,
                      alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
            Text(verbatim: value).font(AppFont.scaled(17, weight: .bold))
                .foregroundStyle(.primary).monospacedDigit()
        }
    }
}

// MARK: - Progress bar

struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(AppOpacity.subtleFill))
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

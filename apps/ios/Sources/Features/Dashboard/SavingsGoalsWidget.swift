import SwiftUI

// MARK: - "Obiective" dashboard widget (phase 2)
//
// A full-width glance at the household's shared savings goals: the top targets
// with their honest progress, straight on the home screen. Self-contained — it
// reads its own service from the environment (like ProactiveInsightsCard) and
// taps through to the Finances page where the goals live.

struct SavingsGoalsWidget: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(AppRouter.self) private var router

    /// The two goals furthest from done lead the widget — the ones a family is
    /// most likely acting on. Complete goals sink to the bottom.
    private var topGoals: [SavingsGoal] {
        service.goals.sorted { a, b in
            service.progress(for: a).fraction < service.progress(for: b).fraction
        }.prefix(2).map { $0 }
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            router.navigate(to: .finances)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                header
                if service.goals.isEmpty {
                    Text("goal_empty_title")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, AppSpacing.xs)
                } else {
                    ForEach(topGoals) { goal in
                        row(for: goal)
                    }
                }
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("goal_section_title"))
    }

    private var header: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "target")
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("goal_section_title")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            Spacer()
            if !service.goals.isEmpty {
                Text(verbatim: "\(service.goals.count)")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func row(for goal: SavingsGoal) -> some View {
        let p = service.progress(for: goal)
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: goal.iconName)
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(goal.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: goal.title)
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.xs)
                    Text(verbatim: "\(p.percent)%")
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(goal.tint)
                        .monospacedDigit()
                }
                ProgressBar(fraction: p.fraction, tint: goal.tint)
            }
        }
    }
}

import SwiftUI

// MARK: - Property Health Detail View
// Full-screen breakdown of the property health score with improvement suggestions

struct PropertyHealthDetailView: View {
    let score: Int
    var maintenancePct: Int
    var utilitiesPct: Int
    var securityPct: Int
    var tasksPct: Int
    /// The score's story in one sentence, computed from real data by the
    /// caller ("Pulling the score down: 3 overdue tasks, 2 documents…").
    var narrative: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Hero score ───────────────────────────────────────────
                heroScoreCard

                // ── Category breakdown ──────────────────────────────────
                categoryBreakdownCard

                // ── Suggestions ─────────────────────────────────────────
                suggestionsCard

                // ── How score works ─────────────────────────────────────
                howItWorksCard

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Property Health")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .font(AppFont.subheadline)
            }
        }
    }

    // MARK: - Hero Score

    private var heroScoreCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 14)
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor.opacity(0.6), scoreColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.1, dampingFraction: 0.82), value: score)
                    .frame(width: 160, height: 160)
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("/ 100")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
            }

            VStack(spacing: 6) {
                Text(scoreLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(scoreColor)
                Text(scoreDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
                if let narrative {
                    Text(narrative)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(scoreColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xxl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .strokeBorder(scoreColor.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: scoreColor.opacity(0.18), radius: 20, y: 6)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Breakdown")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            categoryRow(
                icon: "wrench.and.screwdriver",
                label: "Maintenance",
                detail: maintenanceDetail,
                pct: maintenancePct,
                color: .orange
            )
            Divider().opacity(0.3)
            categoryRow(
                icon: "bolt.fill",
                label: "Utilities",
                detail: utilitiesDetail,
                pct: utilitiesPct,
                color: Color.brandSkyBlue
            )
            Divider().opacity(0.3)
            categoryRow(
                icon: "lock.shield.fill",
                label: "Security",
                detail: securityDetail,
                pct: securityPct,
                color: Color.brandPurple
            )
            Divider().opacity(0.3)
            categoryRow(
                icon: "checklist",
                label: "Tasks",
                detail: tasksDetail,
                pct: tasksPct,
                color: Color.brandSuccess
            )
        }
        .padding(AppSpacing.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func categoryRow(icon: String, label: String, detail: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFont.headline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(pct)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(pct >= 80 ? color : pct >= 60 ? .orange : .red)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(pct) / 100, height: 5)
                    }
                }
                .frame(height: 5)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.brandPurple)
                Text("How to Improve")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
            }

            ForEach(suggestions, id: \.title) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(tip.color)
                        .frame(width: 30, height: 30)
                        .background(tip.color.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.title)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text(tip.body)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("+\(tip.points)pts")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tip.color)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(tip.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(AppSpacing.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - How it Works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How the Score Works")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(Color.primary.opacity(0.55))
            Text("The property health score is calculated from four categories: Maintenance (30%), Utilities (25%), Security (25%), and Tasks completion (20%). Completing tasks, keeping documents current, and resolving alerts all raise your score.")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.lg)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    // MARK: - Computed helpers

    private var scoreColor: Color {
        score >= 80 ? Color.brandSuccess :
        score >= 55 ? .orange : .red
    }

    private var scoreLabel: String {
        score >= 90 ? String(localized: "Excellent") :
        score >= 80 ? String(localized: "Good") :
        score >= 65 ? String(localized: "Fair") :
        score >= 50 ? String(localized: "Needs attention") : String(localized: "Critical")
    }

    private var scoreDescription: String {
        score >= 80
            ? String(localized: "Your property is well maintained. Keep resolving tasks on time.")
            : String(localized: "Some areas need attention. Follow the suggestions below to raise the score.")
    }

    private var maintenanceDetail: String {
        maintenancePct >= 80 ? String(localized: "Good — equipment running fine") :
        maintenancePct >= 60 ? String(localized: "A few appliances need a check") :
        String(localized: "Several appliances need inspection")
    }

    private var utilitiesDetail: String {
        utilitiesPct >= 80 ? String(localized: "Bills up to date, normal usage") :
        utilitiesPct >= 60 ? String(localized: "Check outstanding bills") :
        String(localized: "Unpaid bills or unusual usage")
    }

    private var securityDetail: String {
        securityPct >= 80 ? String(localized: "Security systems active") :
        securityPct >= 60 ? String(localized: "Some checks recommended") :
        String(localized: "Security needs urgent attention")
    }

    private var tasksDetail: String {
        tasksPct >= 90 ? String(localized: "All tasks completed") :
        tasksPct >= 60 ? String(localized: "Active tasks in progress") :
        String(localized: "Overdue tasks — prioritize them")
    }

    private struct Tip {
        let icon: String
        let color: Color
        let title: String
        let body: String
        let points: Int
    }

    private var suggestions: [Tip] {
        var tips: [Tip] = []
        if maintenancePct < 85 {
            tips.append(.init(icon: "wrench.and.screwdriver", color: .orange,
                title: String(localized: "Check your equipment"),
                body: String(localized: "Add a yearly inspection for the boiler, electrical system and plumbing."),
                points: 8))
        }
        if utilitiesPct < 90 {
            tips.append(.init(icon: "bolt.fill", color: Color.brandSkyBlue,
                title: String(localized: "Update your bills"),
                body: String(localized: "Log utility receipts to keep the history complete."),
                points: 5))
        }
        if securityPct < 85 {
            tips.append(.init(icon: "lock.shield.fill", color: Color.brandPurple,
                title: String(localized: "Improve security"),
                body: String(localized: "Add cameras or sensors to uncovered areas of the property."),
                points: 7))
        }
        if tasksPct < 80 {
            tips.append(.init(icon: "checklist", color: Color.brandSuccess,
                title: String(localized: "Resolve overdue tasks"),
                body: String(localized: "Complete due tasks — every finished task raises the score."),
                points: 3))
        }
        if tips.isEmpty {
            tips.append(.init(icon: "star.fill", color: .yellow,
                title: String(localized: "Property in excellent shape!"),
                body: String(localized: "Keep the rhythm: monthly checks + updated documents + tasks on time."),
                points: 0))
        }
        return tips
    }
}

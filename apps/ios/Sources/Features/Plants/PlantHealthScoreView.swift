import SwiftUI

// MARK: - Plant Health Score card + ring (Plant OS P6)
//
// Renders the explainable 0–100 score with an Activity-ring-quality gauge and,
// beneath it, one row per factor showing its contribution AND a concrete
// recommendation. Factors with no real data are listed separately as "not
// counted" — the UI states exactly what is missing, and the ring reads "—"
// when nothing can be measured. No fabricated numbers, ever.

struct PlantHealthScoreCard: View {
    let score: PlantHealthScore

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Label("plant_score_title", systemImage: "heart.text.square")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: AppSpacing.lg) {
                    HealthScoreRing(score: score)
                    summary
                }

                if !score.availableFactors.isEmpty {
                    Divider().opacity(0.12)
                    VStack(spacing: AppSpacing.md) {
                        ForEach(score.availableFactors) { factorRow($0) }
                    }
                }

                if !score.missingFactors.isEmpty {
                    missingSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Summary beside the ring

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(score.bandLabel)
                .font(AppFont.headline)
                .foregroundStyle(.primary)
            if score.value != nil {
                Text(String(format: String(localized: "plant_score_based_on_fmt"),
                            score.availableFactors.count, score.factors.count))
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                if let top = topRecommendation {
                    Label {
                        Text(top).font(AppFont.footnote).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    } icon: {
                        Image(systemName: "lightbulb.fill").font(AppFont.caption).foregroundStyle(Color.brandWarning)
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("plant_score_no_data")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The recommendation of the lowest-scoring available factor — the single
    /// most useful next action.
    private var topRecommendation: String? {
        score.availableFactors
            .min { ($0.subScore ?? 1) < ($1.subScore ?? 1) }
            .flatMap { ($0.subScore ?? 1) < 0.85 ? $0.recommendation : nil }
    }

    // MARK: Factor row

    private func factorRow(_ factor: PlantHealthFactor) -> some View {
        let tint = factorTint(factor.subScore ?? 0)
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(tint.opacity(AppOpacity.tintedFill))
                        .frame(width: 30, height: 30)
                    Image(systemName: factor.kind.icon)
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(factor.kind.title)
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Text(factor.headline)
                        .font(AppFont.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: AppSpacing.sm)
                Text(String(format: String(localized: "plant_score_points_fmt"),
                            Int(factor.earnedPoints.rounded()), Int(factor.maxPoints.rounded())))
                    .font(AppFont.captionStrong)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            // Contribution bar (earned / max points for this factor).
            GeometryReader { geo in
                let frac = factor.maxPoints > 0 ? factor.earnedPoints / factor.maxPoints : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(AppOpacity.hairline))
                    Capsule().fill(tint).frame(width: max(0, geo.size.width * frac))
                }
            }
            .frame(height: 4)
            .padding(.leading, 42)

            Text(factor.recommendation)
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 42)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(factor.kind.title))
        .accessibilityValue(Text("\(factor.headline). \(Int(factor.earnedPoints.rounded())) \(String(localized: "plant_score_a11y_points")). \(factor.recommendation)"))
    }

    // MARK: Missing factors

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("plant_score_missing_title", systemImage: "questionmark.circle")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(score.missingFactors) { factor in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: factor.kind.icon)
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(factor.kind.title)
                            .font(AppFont.footnote).foregroundStyle(.secondary)
                        Text(factor.recommendation)
                            .font(AppFont.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.top, AppSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func factorTint(_ sub: Double) -> Color {
        switch sub {
        case 0.85...:  return .brandSuccess
        case 0.6..<0.85: return Color(red: 0.55, green: 0.78, blue: 0.35)
        case 0.4..<0.6:  return .brandWarning
        default:         return .brandDanger
        }
    }
}

// MARK: - Health score ring (Activity-ring style, honest)

private struct HealthScoreRing: View {
    let score: PlantHealthScore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateTo: CGFloat = 0

    private let lineWidth: CGFloat = 12
    private let diameter: CGFloat = 128

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(AppOpacity.hairline),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if score.value != nil {
                Circle()
                    .trim(from: 0, to: animateTo)
                    .stroke(score.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: score.color.opacity(0.35), radius: 4)
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(AppOpacity.disabled),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [3, 7]))
            }

            center
        }
        .frame(width: diameter, height: diameter)
        .onAppear { runFill() }
        .onChange(of: score.value) { _, _ in animateTo = 0; runFill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("plant_score_title"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var center: some View {
        VStack(spacing: 0) {
            if let v = score.value {
                Text("\(v)")
                    .font(AppFont.scaled(40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("plant_score_out_of")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(AppFont.scaled(34, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func runFill() {
        let target = CGFloat(score.value ?? 0) / 100
        if reduceMotion {
            animateTo = target
        } else {
            withAnimation(.smooth(duration: 0.9)) { animateTo = target }
        }
    }

    private var accessibilityValue: String {
        if let v = score.value {
            return String(format: String(localized: "plant_score_a11y_value"), v)
        }
        return String(localized: "plant_score_no_data")
    }
}

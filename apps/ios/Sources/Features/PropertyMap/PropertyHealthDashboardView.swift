import SwiftUI

/// The health dashboard sheet, in the smart-home warm glass skin: blurred
/// cover-photo backdrop, SmartGlassCards, warm-white text. Score colors
/// stay semantic (green→red by condition) — the skin never repaints truth.
struct PropertyHealthDashboardView: View {
    @Environment(PropertyElementService.self) private var elementService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"

    var body: some View {
        NavigationStack {
            ZStack {
                SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Overall score
                        overallScoreCard
                        // Critical elements
                        if !elementService.criticalElements.isEmpty {
                            criticalSection
                        }
                        // All elements ranked
                        allElementsSection
                        // Layer breakdown
                        layerBreakdownSection
                        // Total value
                        if elementService.totalEstimatedValue() > 0 {
                            totalValueCard
                        }
                        // AI Recommendations (UI architecture)
                        aiRecommendationsCard
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
                .environment(\.colorScheme, .dark)
            }
            .navigationTitle("Property Health Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.smartTextSecondary)
                }
            }
        }
    }

    // MARK: - Overall

    private var overallScoreCard: some View {
        SmartGlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.smartGlassFill, lineWidth: 8)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: CGFloat(elementService.overallHealthScore) / 100)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [scoreColor(elementService.overallHealthScore).opacity(0.6), scoreColor(elementService.overallHealthScore)]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(elementService.overallHealthScore)")
                            .font(AppFont.scaled(26, weight: .black))
                            .foregroundStyle(scoreColor(elementService.overallHealthScore))
                        Text("/100")
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.smartTextSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Health Score")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.smartTextPrimary)
                    Text(LocalizedStringKey(scoreLabel(elementService.overallHealthScore)))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.smartTextSecondary)
                    HStack(spacing: 16) {
                        miniStat(label: "Elements", value: "\(elementService.elements.count)")
                        miniStat(label: "Critical", value: "\(elementService.criticalElements.count)", color: elementService.criticalElements.isEmpty ? Color.smartTextSecondary : Color.red)
                        miniStat(label: "Attention", value: "\(elementService.elementsNeedingAttention.count)", color: .orange)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Critical

    private var criticalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Requires urgent attention", systemImage: "exclamationmark.triangle.fill")
                .font(AppFont.subheadline)
                .foregroundStyle(.red)
            ForEach(elementService.criticalElements.prefix(3)) { el in
                HealthElementRow(element: el)
            }
        }
    }

    // MARK: - All elements

    private var allElementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All elements")
                .font(AppFont.subheadline)
                .foregroundStyle(Color.smartTextPrimary)
            ForEach(elementService.elements.sorted { $0.healthScore < $1.healthScore }) { el in
                HealthElementRow(element: el)
            }
        }
    }

    // MARK: - Layer breakdown

    private var layerBreakdownSection: some View {
        SmartGlassCard(padding: AppSpacing.base) {
            VStack(spacing: 12) {
                HStack {
                    Text("Breakdown per layer")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.smartTextPrimary)
                    Spacer()
                }
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    let els = elementService.elements(for: layer)
                    if !els.isEmpty {
                        let avg = els.reduce(0) { $0 + $1.healthScore } / els.count
                        VStack(spacing: 4) {
                            HStack {
                                Label(layer.displayName, systemImage: layer.icon)
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.smartTextSecondary)
                                Spacer()
                                Text("\(avg)/100")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(scoreColor(avg))
                                Text("(\(els.count))")
                                    .font(AppFont.caption2)
                                    .foregroundStyle(Color.smartTextSecondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.smartGlassFill).frame(height: 5)
                                    Capsule()
                                        .fill(scoreColor(avg))
                                        .frame(width: geo.size.width * CGFloat(avg) / 100, height: 5)
                                }
                            }.frame(height: 5)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Total value

    private var totalValueCard: some View {
        SmartGlassCard(padding: AppSpacing.base) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Total estimated value", systemImage: "banknote")
                        .font(AppFont.captionStrong).foregroundStyle(Color.smartTextSecondary)
                    Text(currencyService.formatted(elementService.totalEstimatedValue(), from: "EUR", preferred: appSettings.preferredCurrency))
                        .font(AppFont.scaled(18, weight: .bold))
                        .foregroundStyle(Color.brandSuccess)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.brandSuccess.opacity(0.5))
            }
        }
    }

    // MARK: - AI Recommendations

    private var aiRecommendationsCard: some View {
        SmartGlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI Recommendations", systemImage: "sparkles")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.brandPurple)

                VStack(spacing: 8) {
                    if let worst = elementService.elements.min(by: { $0.healthScore < $1.healthScore }) {
                        aiTip(
                            icon: "wrench.and.screwdriver",
                            title: "Priority: \(worst.name)",
                            desc: "Lowest score (\(worst.healthScore)/100). We recommend an inspection within 30 days.",
                            color: worst.healthColor
                        )
                    }
                    aiTip(
                        icon: "calendar.badge.clock",
                        title: "Periodic review",
                        desc: "Schedule annual reviews for the boiler and electrical panel.",
                        color: .orange
                    )
                    aiTip(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Cost analysis",
                        desc: "Add maintenance costs for an accurate expense prediction.",
                        color: Color.smartAmber
                    )
                }

                Text("Full AI functionality — \(assistantName) integration coming in next version")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.smartTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func miniStat(label: LocalizedStringKey, value: String, color: Color = .smartTextSecondary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(AppFont.scaled(15, weight: .bold)).foregroundStyle(color)
            Text(label).font(AppFont.caption2).foregroundStyle(Color.smartTextSecondary)
        }
    }

    private func aiTip(icon: String, title: LocalizedStringKey, desc: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(AppOpacity.tintedFill), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.captionStrong).foregroundStyle(Color.smartTextPrimary)
                Text(desc).font(AppFont.caption).foregroundStyle(Color.smartTextSecondary)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return Color.brandSuccess
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return .orange
        case 25..<50:  return Color.brandWarning
        default:       return .red
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 90...100: return String(localized: "Property in excellent condition")
        case 70..<90:  return String(localized: "Property in good condition")
        case 50..<70:  return String(localized: "Some elements need attention")
        case 25..<50:  return String(localized: "Multiple issues identified")
        default:       return String(localized: "Urgent intervention required")
        }
    }
}

// MARK: - HealthElementRow

private struct HealthElementRow: View {
    let element: PropertyElement

    var body: some View {
        SmartGlassCard(padding: AppSpacing.md) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(element.elementType.accentColor.opacity(AppOpacity.tintedFill))
                        .frame(width: 36, height: 36)
                    Image(systemName: element.elementType.icon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(element.elementType.accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(element.name)
                        .font(AppFont.scaled(15, weight: .medium))
                        .foregroundStyle(Color.smartTextPrimary)
                        .lineLimit(1)
                    Text(element.elementType.displayName)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.smartTextSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(element.healthScore)")
                        .font(AppFont.scaled(15, weight: .bold))
                        .foregroundStyle(element.healthColor)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.smartGlassFill).frame(height: 4)
                            Capsule()
                                .fill(element.healthColor)
                                .frame(width: geo.size.width * CGFloat(element.healthScore) / 100, height: 4)
                        }
                    }
                    .frame(width: 60, height: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

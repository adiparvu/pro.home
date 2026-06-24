import SwiftUI

struct PropertyHealthDashboardView: View {
    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
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
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Property Health Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Overall

    private var overallScoreCard: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 8)
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
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(scoreColor(elementService.overallHealthScore))
                        Text("/100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Health Score")
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(scoreLabel(elementService.overallHealthScore)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        miniStat(label: "Elements", value: "\(elementService.elements.count)")
                        miniStat(label: "Critical", value: "\(elementService.criticalElements.count)", color: elementService.criticalElements.isEmpty ? Color.secondary : Color.red)
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
                .font(.subheadline.weight(.semibold))
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
                .font(.subheadline.weight(.semibold))
            ForEach(elementService.elements.sorted { $0.healthScore < $1.healthScore }) { el in
                HealthElementRow(element: el)
            }
        }
    }

    // MARK: - Layer breakdown

    private var layerBreakdownSection: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 12) {
                HStack {
                    Text("Breakdown per layer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    let els = elementService.elements(for: layer)
                    if !els.isEmpty {
                        let avg = els.reduce(0) { $0 + $1.healthScore } / els.count
                        VStack(spacing: 4) {
                            HStack {
                                Label(layer.displayName, systemImage: layer.icon)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(avg)/100")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(scoreColor(avg))
                                Text("(\(els.count))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
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
        GlassCard(padding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Total estimated value", systemImage: "banknote")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(currencyService.formatted(elementService.totalEstimatedValue(), from: "EUR", preferred: appSettings.preferredCurrency))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.5))
            }
        }
    }

    // MARK: - AI Recommendations

    private var aiRecommendationsCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI Recommendations", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.48, green: 0.41, blue: 0.93))

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
                        color: Color(red: 0.29, green: 0.56, blue: 0.89)
                    )
                }

                Text("Full AI functionality — \(assistantName) integration coming in next version")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func miniStat(label: LocalizedStringKey, value: String, color: Color = .secondary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func aiTip(icon: String, title: LocalizedStringKey, desc: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return .orange
        case 25..<50:  return Color(red: 1.0, green: 0.45, blue: 0.1)
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
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(element.elementType.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: element.elementType.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(element.elementType.accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(element.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(element.elementType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(element.healthScore)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(element.healthColor)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08)).frame(height: 4)
                            Capsule()
                                .fill(element.healthColor)
                                .frame(width: geo.size.width * CGFloat(element.healthScore) / 100, height: 4)
                        }
                    }
                    .frame(width: 60, height: 4)
                }
            }
        }
    }
}

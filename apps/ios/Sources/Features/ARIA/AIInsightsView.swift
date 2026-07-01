import SwiftUI

// MARK: - AI Insights — matches dark mockup (blue orb + proactive recommendations)

struct AIInsightsView: View {
    @Environment(AppRouter.self) var router
    @Environment(TaskService.self) var taskService
    @Environment(PropertyElementService.self) var elementService
    @Environment(PropertyZoneService.self) var zoneService
    @Environment(PlantService.self) var plantService
    @EnvironmentObject var propertyService: PropertyService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"

    @State private var orbPulse = false
    @State private var showTimeline = false

    private var insights: [AIInsight] { computeInsights() }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Blue orb hero
                orbHero
                    .padding(.top, 28)
                    .padding(.bottom, AppSpacing.xxl)

                // Recommendations section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "ai_insights_recommendations"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        if !insights.isEmpty {
                            Text("\(insights.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(insights.enumerated()), id: \.element.id) { idx, insight in
                                AIInsightRow(insight: insight,
                                           isLast: idx == insights.count - 1)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                Spacer().frame(height: 28)

                // Open ARIA Chat button
                Button {
                    HapticFeedback.impact(.medium)
                    router.showARIA = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(AppFont.subheadline)
                        Text(String(localized: "ai_insights_ask_aria"))
                            .font(AppFont.subheadline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.45, blue: 0.95),
                                     Color(red: 0.55, green: 0.30, blue: 0.90)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.35, green: 0.30, blue: 0.90).opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.lg)

                Spacer().frame(height: 14)

                // View Full Timeline — outline button
                NavigationLink {
                    PRVIOTimelineView()
                        .environment(taskService)
                        .environment(elementService)
                        .environment(tabBarVis)
                } label: {
                    Text(String(localized: "ai_insights_timeline"))
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(red: 0.45, green: 0.60, blue: 1.0).opacity(0.4), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.lg)

                Spacer().frame(height: 10)

                // Automation Builder — outline button
                NavigationLink {
                    AutomationBuilderView()
                } label: {
                    Text(String(localized: "ai_insights_automation"))
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(red: 0.45, green: 0.60, blue: 1.0).opacity(0.4), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.lg)

                Spacer(minLength: 32)
            }
            .trackTabScroll()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "ai_insights_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { orbPulse = true } }
    }

    // MARK: - Orb hero

    private var orbHero: some View {
        VStack(spacing: 16) {
            ZStack {
                // Outer glow layers
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.30, green: 0.55, blue: 1.0).opacity(orbPulse ? 0.35 : 0.20),
                                     Color.clear],
                            center: .center, startRadius: 0, endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(orbPulse ? 1.1 : 1.0)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.45, green: 0.30, blue: 0.95).opacity(orbPulse ? 0.5 : 0.35),
                                     Color.clear],
                            center: .center, startRadius: 0, endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)

                // Core orb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.55, blue: 1.0),
                                     Color(red: 0.55, green: 0.30, blue: 0.95)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 24, height: 24)
                            .offset(x: -10, y: -10)
                            .blur(radius: 6)
                    )
                    .shadow(color: Color(red: 0.35, green: 0.45, blue: 1.0).opacity(0.8), radius: 20, y: 4)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(assistantName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Text(String(localized: "ai_insights_property_intelligence"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
        }
    }

    // MARK: - Empty state

    private var emptyInsights: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color(red: 0.20, green: 0.82, blue: 0.48).opacity(0.6))
                .padding(.top, AppSpacing.xl)
            Text(String(localized: "ai_insights_all_good"))
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(0.55))
            Text(String(localized: "ai_insights_healthy"))
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }

    // MARK: - Compute insights from live data

    private func computeInsights() -> [AIInsight] {
        var result: [AIInsight] = []

        // Overdue tasks
        if taskService.overdueCount > 0 {
            result.append(.init(
                icon: "exclamationmark.triangle.fill",
                iconColor: .red,
                title: "\(taskService.overdueCount) overdue task\(taskService.overdueCount == 1 ? "" : "s") need attention",
                elapsed: "Now"
            ))
        }

        // Elements with low health
        if let first = elementService.elements.first(where: { $0.healthScore < 50 }) {
            result.append(.init(
                icon: "wrench.and.screwdriver.fill",
                iconColor: .orange,
                title: "\(first.name) needs maintenance",
                elapsed: "Today"
            ))
        }

        // Plants needing water
        let needsWater = plantService.plantsNeedingWater
        if let firstPlant = needsWater.first {
            let plantsToWater = needsWater
            result.append(.init(
                icon: "drop.fill",
                iconColor: Color(red: 0.25, green: 0.65, blue: 1.0),
                title: needsWater.count == 1
                    ? "\(firstPlant.name) needs watering"
                    : "\(needsWater.count) plants need watering",
                elapsed: "Today",
                actionLabel: String(localized: "ai_insights_water_all"),
                action: { [plantService] in
                    for plant in plantsToWater {
                        await plantService.markWatered(plant)
                    }
                }
            ))
        }

        // Low zone health
        let poorZone = zoneService.zones.filter { $0.healthScore < 55 }.first
        if let zone = poorZone {
            result.append(.init(
                icon: "exclamationmark.circle.fill",
                iconColor: .orange,
                title: "Zone \"\(zone.name)\" health is \(zone.healthScore)%",
                elapsed: "This week"
            ))
        }

        // Expiring warranties
        if let expiring = elementService.elements.first(where: {
            if case .expiringSoon = $0.warrantyStatus { return true }
            return false
        }) {
            result.append(.init(
                icon: "shield.slash.fill",
                iconColor: Color(red: 0.95, green: 0.70, blue: 0.20),
                title: "Warranty expiring soon: \(expiring.name)",
                elapsed: "Soon"
            ))
        }

        // Good news if all healthy
        if result.isEmpty {
            let score = propertyService.primary?.healthScore ?? 100
            result.append(.init(
                icon: "checkmark.seal.fill",
                iconColor: Color(red: 0.20, green: 0.82, blue: 0.48),
                title: "Property health is excellent (\(score)%)",
                elapsed: "Now"
            ))
        }

        return result
    }
}

// MARK: - AIInsight model

struct AIInsight: Identifiable {
    var id: String { icon + title }
    let icon: String
    let iconColor: Color
    let title: String
    let elapsed: String
    var actionLabel: String? = nil
    var action: (() async -> Void)? = nil
}

// MARK: - AIInsightRow

struct AIInsightRow: View {
    let insight: AIInsight
    var isLast: Bool = false
    @State private var isActing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(insight.iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: insight.icon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(insight.iconColor)
                }

                Text(LocalizedStringKey(insight.title))
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if let actionLabel = insight.actionLabel, let action = insight.action {
                    Button {
                        HapticFeedback.impact(.light)
                        isActing = true
                        Task {
                            await action()
                            isActing = false
                        }
                    } label: {
                        if isActing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 52, height: 24)
                        } else {
                            Text(actionLabel)
                                .font(AppFont.label)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(insight.iconColor, in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isActing)
                } else {
                    Text(LocalizedStringKey(insight.elapsed))
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 0.5)
                    .padding(.leading, 66)
            }
        }
    }
}

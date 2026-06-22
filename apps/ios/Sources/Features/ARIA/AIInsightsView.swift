import SwiftUI

// MARK: - AI Insights — matches dark mockup (blue orb + proactive recommendations)

struct AIInsightsView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var taskService: TaskService
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject var zoneService: PropertyZoneService
    @EnvironmentObject var plantService: PlantService
    @EnvironmentObject var propertyService: PropertyService
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State private var orbPulse = false
    @State private var showTimeline = false

    private var insights: [ProactiveInsight] { computeInsights() }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Blue orb hero
                orbHero
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                // Recommendations section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Proactive Recommendations")
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

                    if insights.isEmpty {
                        emptyInsights
                    } else {
                        ForEach(insights) { insight in
                            InsightRow(insight: insight)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 28)

                // Open ARIA Chat button
                Button {
                    HapticFeedback.impact(.medium)
                    router.showARIA = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Ask ARIA")
                            .font(.system(size: 15, weight: .semibold))
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
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.35, green: 0.30, blue: 0.90).opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer().frame(height: 14)

                // View Full Timeline — outline button
                NavigationLink {
                    PRVIOTimelineView()
                        .environmentObject(taskService)
                        .environmentObject(elementService)
                        .environmentObject(tabBarVis)
                } label: {
                    Text("View Full Timeline")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(red: 0.45, green: 0.60, blue: 1.0).opacity(0.4), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer().frame(height: 10)

                // Automation Builder — outline button
                NavigationLink {
                    AutomationBuilderView()
                } label: {
                    Text("Automation Builder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(red: 0.45, green: 0.60, blue: 1.0).opacity(0.4), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
            .trackTabScroll()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("AI Insights")
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
                Text("ARIA")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Property Intelligence")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
            }
        }
    }

    // MARK: - Empty state

    private var emptyInsights: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color(red: 0.20, green: 0.82, blue: 0.48).opacity(0.6))
                .padding(.top, 20)
            Text("All good!")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
            Text("No immediate recommendations. Your property looks healthy.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Compute insights from live data

    private func computeInsights() -> [ProactiveInsight] {
        var result: [ProactiveInsight] = []

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
        let lowHealth = elementService.elements.filter { $0.healthScore < 50 }
        if !lowHealth.isEmpty {
            let first = lowHealth[0]
            result.append(.init(
                icon: "wrench.and.screwdriver.fill",
                iconColor: .orange,
                title: "\(first.name) needs maintenance",
                elapsed: "Today"
            ))
        }

        // Plants needing water
        let needsWater = plantService.plantsNeedingWater
        if !needsWater.isEmpty {
            result.append(.init(
                icon: "drop.fill",
                iconColor: Color(red: 0.25, green: 0.65, blue: 1.0),
                title: needsWater.count == 1
                    ? "\(needsWater[0].name) needs watering"
                    : "\(needsWater.count) plants need watering",
                elapsed: "Today"
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
        let expiring = elementService.elements.filter {
            if case .expiringSoon = $0.warrantyStatus { return true }
            return false
        }
        if !expiring.isEmpty {
            result.append(.init(
                icon: "shield.slash.fill",
                iconColor: Color(red: 0.95, green: 0.70, blue: 0.20),
                title: "Warranty expiring soon: \(expiring[0].name)",
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

// MARK: - ProactiveInsight model

struct ProactiveInsight: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let elapsed: String
}

// MARK: - InsightRow

struct InsightRow: View {
    let insight: ProactiveInsight

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(insight.iconColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: insight.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(insight.iconColor)
            }

            Text(insight.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(insight.elapsed)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

import SwiftUI

// MARK: - PondDashboardView
//
// Main entry point for Pond OS. Accessed from PropertyHomeView → "Your Ponds" card.
// Shows health orb, all 7 primary water parameters, equipment status, quick actions.
// Requires: GlassCard, liquidGlass(), StatRow from PRVIO Components/GlassCard.swift

struct PondDashboardView: View {
    let pond: Pond

    @StateObject private var waterQuality = WaterQualityService()
    @StateObject private var fishService  = FishService()
    @StateObject private var feeding      = FeedingService()
    @StateObject private var pondService  = PondService()

    @State private var equipment: [PondEquipment] = []
    @State private var zones: [PondZone] = []
    @State private var healthSnapshot: PondHealthSnapshot?
    @State private var showWaterQuality = false
    @State private var showFish = false
    @State private var showFeeding = false
    @State private var showTwin = false
    @State private var showAddReading = false
    @State private var addReadingParam: WaterParameter = .ph

    private let primaryParameters: [WaterParameter] = [
        .temperature, .ph, .dissolvedOxygen,
        .turbidity, .waterLevel, .conductivity, .salinity
    ]

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 16) {
                    // Health orb + overview
                    healthSection
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Active alerts
                    if !waterQuality.activeAlerts.isEmpty {
                        PondAlertBanner(alerts: waterQuality.activeAlerts) { alert in
                            Task { try? await waterQuality.acknowledgeAlert(alert) }
                        }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Water quality grid
                    waterQualitySection

                    // Equipment
                    if !equipment.isEmpty {
                        equipmentSection
                    }

                    // Module links
                    moduleLinks
                        .padding(.horizontal, 16)

                    // Feeding status
                    feedingStatusSection
                        .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
                .padding(.top, 4)
            }
        }
        .navigationTitle(pond.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .task { await loadAll() }
        .navigationDestination(isPresented: $showWaterQuality) {
            WaterQualityCenter(pond: pond, waterQualityService: waterQuality)
        }
        .navigationDestination(isPresented: $showFish) {
            FishManagementView(pond: pond, fishService: fishService)
        }
        .navigationDestination(isPresented: $showFeeding) {
            FeedingSystemView(pond: pond, feedingService: feeding)
        }
        .navigationDestination(isPresented: $showTwin) {
            PondDigitalTwinView(pond: pond, zones: zones, equipment: equipment,
                                latestReadings: waterQuality.latestReadings)
        }
        .sheet(isPresented: $showAddReading) {
            AddWaterReadingSheet(pond: pond, parameter: addReadingParam, service: waterQuality)
        }
    }

    // MARK: Health Section

    private var healthSection: some View {
        GlassCard {
            HStack(spacing: 16) {
                PondHealthOrbView(
                    score: healthSnapshot?.overallScore ?? 0,
                    color: healthSnapshot?.healthColor ?? .gray
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(healthSnapshot?.healthLabel ?? "Loading…")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        miniStat(value: "\(healthSnapshot?.waterQualityScore ?? 0)",
                                 label: "Water", color: Color(hex: "#0A84FF"))
                        miniStat(value: "\(healthSnapshot?.fishHealthScore ?? 0)",
                                 label: "Fish",  color: Color(hex: "#34C759"))
                        miniStat(value: "\(healthSnapshot?.equipmentScore ?? 0)",
                                 label: "Equip", color: Color(hex: "#FF9F0A"))
                    }

                    if let updated = waterQuality.latestReadings.values.max(by: { $0.recordedAt < $1.recordedAt })?.recordedAt {
                        Text("Updated " + updated.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer()
            }
        }
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Water Quality Grid

    private var waterQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Water Quality",
                icon: "drop.fill",
                action: ("See All", { showWaterQuality = true })
            )
            .padding(.horizontal, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(primaryParameters, id: \.self) { param in
                    WaterParameterCard(
                        parameter: param,
                        reading: waterQuality.latestReadings[param]
                    ) {
                        addReadingParam = param
                        showAddReading = true
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Equipment Section

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Equipment", icon: "arrow.triangle.2.circlepath")
                .padding(.horizontal, 16)

            GlassCard(padding: 14) {
                VStack(spacing: 0) {
                    ForEach(equipment.filter { [.pump, .filter, .aerator, .uv].contains($0.type) }) { item in
                        PondEquipmentRow(equipment: item)
                        if item.id != equipment.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Module Links

    private var moduleLinks: some View {
        HStack(spacing: 10) {
            ModuleLinkButton(
                icon: "fish.fill",
                title: "Fish",
                subtitle: "\(fishService.totalFishCount) total",
                color: Color(hex: "#30B0C7")
            ) { showFish = true }

            ModuleLinkButton(
                icon: "fork.knife",
                title: "Feeding",
                subtitle: nextFeedingLabel,
                color: Color(hex: "#FF9F0A")
            ) { showFeeding = true }

            ModuleLinkButton(
                icon: "square.3.layers.3d",
                title: "Twin",
                subtitle: "\(zones.count) zones",
                color: Color(hex: "#0A84FF")
            ) { showTwin = true }
        }
    }

    private var nextFeedingLabel: String {
        guard let schedule = feeding.schedules.first(where: { $0.isActive }) else {
            return "No schedule"
        }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let schedHour = schedule.hour
        let schedMin  = schedule.minute
        if (schedHour > now.hour ?? 0) ||
           (schedHour == now.hour && schedMin > now.minute ?? 0) {
            return "Today \(String(format: "%02d:%02d", schedHour, schedMin))"
        }
        return "Tomorrow \(String(format: "%02d:%02d", schedHour, schedMin))"
    }

    // MARK: Feeding Status

    private var feedingStatusSection: some View {
        Group {
            if let lastFed = feeding.lastFeedingTime(for: pond.id) {
                GlassCard(padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: "#FF9F0A"))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Last feeding")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(lastFed.relativeFormatted)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Spacer()

                        Text("Feed Now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#FF9F0A"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "#FF9F0A").opacity(0.15))
                            )
                            .onTapGesture {
                                Task {
                                    try? await feeding.logManualFeeding(
                                        pondId: pond.id,
                                        foodType: .pellet,
                                        amountGrams: 50
                                    )
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                addReadingParam = .ph
                showAddReading = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "#0A84FF"))
            }
        }
    }

    // MARK: Load

    private func loadAll() async {
        let pondId = pond.id
        await waterQuality.loadLatest(for: pondId)
        await fishService.loadPopulations(for: pondId)
        try? await feeding.loadSchedules(for: pondId)
        try? await feeding.loadRecentLogs(for: pondId)
        equipment = (try? await pondService.loadEquipment(for: pondId)) ?? []
        zones     = (try? await pondService.loadZones(for: pondId)) ?? []
        rebuildHealthSnapshot()
    }

    private func rebuildHealthSnapshot() {
        healthSnapshot = PondHealthEngine.score(
            readings: waterQuality.latestReadings,
            populations: fishService.populations,
            equipment: equipment,
            activeAlerts: waterQuality.activeAlerts,
            lastFeedingAt: feeding.lastFeedingTime(for: pond.id)
        )
    }
}

// MARK: - PondHealthOrbView (parameterized — same visual language as PropertyHomeView)

struct PondHealthOrbView: View {
    let score: Int
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.6), color.opacity(0.2)],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 28
                    )
                )
                .frame(width: 56, height: 56)
                .scaleEffect(pulse ? 1.06 : 1.0)
                .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 1))

            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("HP")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Supporting Components

private struct SectionHeader: View {
    let title: String
    let icon: String
    var action: (String, () -> Void)? = nil

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if let (label, handler) = action {
                Button(label, action: handler)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#0A84FF"))
            }
        }
    }
}

private struct ModuleLinkButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: Circle())

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

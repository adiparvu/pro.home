import SwiftUI

// MARK: - PlantsView

struct PlantsView: View {
    @Environment(PlantService.self) private var plantService
    @Environment(PropertyService.self) private var propertyService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(AppRouter.self) private var router

    @State private var showAddPlant = false
    @State private var selectedPlant: Plant? = nil
    @State private var showSearch = false
    @State private var searchText = ""

    private var filteredNeedingWater: [Plant] {
        plantService.plantsNeedingWater.filter(matchesSearch)
    }

    private var filteredHealthy: [Plant] {
        plantService.healthyPlants.filter(matchesSearch)
    }

    private func matchesSearch(_ plant: Plant) -> Bool {
        plant.name.matchesSearch(searchText)
            || (plant.species ?? "").matchesSearch(searchText)
            || (plant.notes ?? "").matchesSearch(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "Plants", subtitleKey: "PROPERTY")

            if propertyService.primary == nil {
                noPropertyState
            } else if plantService.isLoading && plantService.plants.isEmpty {
                loadingState
            } else if plantService.plants.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    SearchIconButton(isActive: $showSearch)
                    Button {
                        showAddPlant = true
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: "plus")
                            .font(AppFont.title3)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Add plant")
                }
            }
        }
        .sheet(isPresented: $showAddPlant) {
            AddPlantSheet()
                .environment(plantService)
                .environment(propertyService)
        }
        .sheet(item: $selectedPlant) { plant in
            PlantDetailSheet(plant: plant)
                .environment(plantService)
        }
        .alert("Error", isPresented: Binding(
            get: { plantService.error != nil },
            set: { if !$0 { plantService.error = nil } }
        )) {
            Button("OK") { plantService.error = nil }
        } message: {
            Text(LocalizedStringKey(plantService.error ?? ""))
        }
        .task {
            if let id = propertyService.primary?.id {
                await plantService.load(propertyId: id)
            }
        }
        // Deep link: a garden notification / Spotlight / prvio://plants/<id> opens
        // this sheet and asks for a specific plant — resolve once loaded.
        .onChange(of: showSearch) { _, on in
            if !on { searchText = "" }
        }
        .onChange(of: router.deepLinkPlantId) { resolvePlantDeepLink() }
        .task(id: plantService.plants.count) { resolvePlantDeepLink() }
        .refreshable {
            if let id = propertyService.primary?.id {
                await plantService.load(propertyId: id)
            }
        }
        .userActivity("com.prvio.plants") { activity in
            activity.title = String(localized: "Plants — PRVIO")
            activity.userInfo = ["tab": "plants"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
    }

    private func resolvePlantDeepLink() {
        guard let id = router.deepLinkPlantId,
              let plant = plantService.plants.first(where: { $0.id == id }) else { return }
        selectedPlant = plant
        router.deepLinkPlantId = nil
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if showSearch {
                    PageSearchField(text: $searchText)
                }
                summaryRow
                plantsGrid
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("plantsScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "plantsScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            tabBarVis.scrollOffset = y
        }
    }

    // MARK: - Summary row

    private var summaryRow: some View {
        GlassCard(padding: 18) {
            HStack(spacing: 0) {
                statCell(
                    value: "\(plantService.plants.count)",
                    label: "Total",
                    color: .primary
                )
                Divider().frame(height: 32).opacity(0.3)
                statCell(
                    value: "\(plantService.plantsNeedingWater.count)",
                    label: "Needs water",
                    color: plantService.plantsNeedingWater.isEmpty
                        ? .primary
                        : Color(red: 1.0, green: 0.62, blue: 0.1)
                )
                Divider().frame(height: 32).opacity(0.3)
                statCell(
                    value: "\(plantService.healthyPlants.count)",
                    label: "Healthy",
                    color: plantService.healthyPlants.isEmpty
                        ? .primary
                        : Color(red: 0.15, green: 0.80, blue: 0.4)
                )
            }
        }
    }

    private func statCell(value: String, label: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Plants grid

    private var plantsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !filteredNeedingWater.isEmpty {
                sectionBlock(
                    title: "NEEDS WATER",
                    icon: "drop.fill",
                    iconColor: Color(red: 1.0, green: 0.62, blue: 0.1),
                    plants: filteredNeedingWater
                )
            }

            if !filteredHealthy.isEmpty {
                sectionBlock(
                    title: "HEALTHY",
                    icon: "leaf.fill",
                    iconColor: Color(red: 0.15, green: 0.80, blue: 0.4),
                    plants: filteredHealthy
                )
            }
        }
    }

    private func sectionBlock(title: LocalizedStringKey, icon: String, iconColor: Color, plants: [Plant]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppFont.label)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, AppSpacing.xxs)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(plants) { plant in
                    PlantCard(plant: plant) {
                        selectedPlant = plant
                    }
                    .environment(plantService)
                }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🪴")
                .font(.system(size: 60))
            Text("No plants added")
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Add plants to track\nwatering and their health status.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
            Button { showAddPlant = true } label: {
                Label("Add first plant", systemImage: "plus")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noPropertyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "house.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No property added")
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PlantCard

struct PlantCard: View {
    @Environment(PlantService.self) private var plantService
    let plant: Plant
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticFeedback.impact(.light)
            onTap()
        }) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                plant.healthColor.opacity(0.18),
                                plant.healthColor.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 80)

                        Text(plant.emoji)
                            .font(.system(size: 44))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plant.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let species = plant.species, !species.isEmpty {
                            Text(species)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(LocalizedStringKey(plant.wateringLabel))
                            .font(AppFont.caption)
                            .foregroundStyle(
                                plant.needsWatering
                                    ? Color(red: 1.0, green: 0.62, blue: 0.1)
                                    : Color(red: 0.15, green: 0.80, blue: 0.4)
                            )
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.primary.opacity(0.3))
                            Text(LocalizedStringKey(plant.lastWateredDisplay))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                HapticFeedback.success()
                Task { await plantService.markWatered(plant) }
            } label: {
                Label("Watered!", systemImage: "drop.fill")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await plantService.delete(plant) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                HapticFeedback.success()
                Task { await plantService.markWatered(plant) }
            } label: {
                Label("Mark as watered", systemImage: "drop.fill")
            }

            Button {
                HapticFeedback.impact(.light)
                onTap()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await plantService.delete(plant) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

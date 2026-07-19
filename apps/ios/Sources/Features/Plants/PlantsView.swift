import SwiftUI

// MARK: - PlantsView

struct PlantsView: View {
    @Environment(PlantService.self) private var plantService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppRouter.self) private var router

    @State private var showAddPlant = false
    @State private var selectedPlant: Plant? = nil
    @State private var searchText = ""

    private var filteredNeedingWater: [Plant] {
        plantService.plantsNeedingWater.filter(matchesSearch)
    }

    private var filteredHealthy: [Plant] {
        plantService.healthyPlants.filter(matchesSearch)
    }

    private func matchesSearch(_ plant: Plant) -> Bool {
        let haystack: [String] = [
            plant.name,
            plant.species ?? "",
            plant.notes ?? "",
            plant.wateringLabel,
            plant.lastWateredDisplay,
            plant.healthScore.map(String.init) ?? ""
        ]
        return haystack.contains { $0.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("Plants")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddPlant = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add plant")
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
            // Siri Suggestions may propose reopening this screen at the
            // habitual moment — prediction learns from these publishes.
            activity.isEligibleForPrediction = true
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
                summaryRow
                plantsGrid
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
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
                .font(AppFont.scaled(22, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            // Explicit token color, never hierarchical `.secondary` inside
            // glass — the vibrancy compositor can eat it entirely
            // (IMG_8652, the same law as the player controls).
            Text(label)
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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

            if !searchText.isEmpty && filteredNeedingWater.isEmpty && filteredHealthy.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "No results")
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
        EmptyStateView(
            icon: "leaf.fill",
            title: "No plants added",
            message: "Add plants to track\nwatering and their health status.",
            actionLabel: "Add first plant",
            action: { showAddPlant = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        EmptyStateView(
            icon: "house.slash",
            title: "No property added"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PlantCard

struct PlantCard: View {
    @Environment(PlantService.self) private var plantService
    let plant: Plant
    let onTap: () -> Void

    private var emojiBanner: some View {
        ZStack {
            LinearGradient(
                colors: [
                    plant.healthColor.opacity(0.18),
                    plant.healthColor.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(plant.emoji)
                .font(AppFont.scaled(44))
        }
        .frame(height: 80)
    }

    var body: some View {
        Button(action: {
            HapticFeedback.impact(.light)
            onTap()
        }) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        // The real hero photo when one exists; the emoji banner
                        // is also the stand-in while it loads or fails.
                        if let urlStr = plant.photoUrl, !urlStr.isEmpty {
                            StorageImage(source: urlStr, targetSize: 180) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    emojiBanner
                                }
                            }
                            .frame(height: 80)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        } else {
                            emojiBanner
                        }
                    }
                    // The persisted Health Score (P6) as a passive badge — the
                    // pipeline stored it on every recompute but no surface read
                    // it back until now. Shown only when a real score exists.
                    .overlay(alignment: .topTrailing) {
                        if let score = plant.healthScore {
                            Text(verbatim: "\(score)")
                                .font(AppFont.scaled(11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(PlantHealthScore.color(for: score).opacity(0.9),
                                            in: Capsule())
                                .padding(6)
                                .accessibilityLabel(Text("plant_score_title"))
                                .accessibilityValue(Text(verbatim: "\(score)"))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plant.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let species = plant.species, !species.isEmpty {
                            Text(species)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                                .font(AppFont.scaled(9))
                                .foregroundStyle(Color.primary.opacity(0.3))
                            Text(LocalizedStringKey(plant.lastWateredDisplay))
                                .font(AppFont.scaled(11))
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
        // Long-press: the PreviewCard as the system-lifted preview, with the
        // existing quick actions beneath.
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
        } preview: {
            PlantPreviewCard(plant: plant)
        }
    }
}

// MARK: - Long-press preview (PreviewCard)
//
// Real data only: the plant's own photo when one exists (emoji disc
// otherwise), name, species as the subtitle (omitted when unset), the next
// watering and last watering, the location when set, and the health status
// as a tinted state chip. All value strings come from the model's existing
// localized computed properties.
struct PlantPreviewCard: View {
    let plant: Plant

    var body: some View {
        PreviewCard(
            title: Text(verbatim: plant.name),
            subtitle: plant.species.flatMap { $0.isEmpty ? nil : Text(verbatim: $0) },
            tint: plant.healthColor,
            details: details,
            chips: [
                PreviewCardChip(icon: plant.healthIcon,
                                text: Text(verbatim: plant.localizedHealthLabel),
                                tint: plant.healthColor)
            ]
        ) {
            photo
        }
    }

    private var details: [PreviewCardDetail] {
        var rows: [PreviewCardDetail] = [
            // "Needs water" / "Water today" / "In N days" — the next watering.
            PreviewCardDetail(icon: "drop.fill",
                              label: Text("Watering"),
                              value: Text(verbatim: plant.wateringLabel)),
            PreviewCardDetail(icon: "clock.arrow.circlepath",
                              label: Text("Last watered"),
                              value: Text(verbatim: plant.lastWateredDisplay)),
        ]
        if let location = plant.location, !location.isEmpty {
            rows.append(PreviewCardDetail(icon: "mappin.and.ellipse",
                                          label: Text("Location"),
                                          value: Text(verbatim: location)))
        }
        return rows
    }

    /// The plant's real photo when one exists; the emoji on a health-tinted
    /// disc otherwise (also the stand-in while the photo loads or fails).
    @ViewBuilder private var photo: some View {
        if let urlStr = plant.photoUrl, !urlStr.isEmpty {
            StorageImage(source: urlStr) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    emojiDisc
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        } else {
            emojiDisc.frame(width: 54, height: 54)
        }
    }

    private var emojiDisc: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(plant.healthColor.opacity(AppOpacity.tintedFill))
            Text(verbatim: plant.emoji)
                .font(AppFont.scaled(30))
        }
    }
}

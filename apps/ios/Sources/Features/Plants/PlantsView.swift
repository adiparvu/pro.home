import SwiftUI

// MARK: - PlantsView

struct PlantsView: View {
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State private var showAddPlant = false
    @State private var selectedPlant: Plant? = nil

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Plante", subtitle: "PROPRIETATE")

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
                Button {
                    showAddPlant = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAddPlant) {
            AddPlantSheet()
                .environmentObject(plantService)
                .environmentObject(propertyService)
        }
        .sheet(item: $selectedPlant) { plant in
            PlantDetailSheet(plant: plant)
                .environmentObject(plantService)
        }
        .alert("Eroare", isPresented: Binding(
            get: { plantService.error != nil },
            set: { if !$0 { plantService.error = nil } }
        )) {
            Button("OK") { plantService.error = nil }
        } message: {
            Text(plantService.error ?? "")
        }
        .task {
            if let id = propertyService.primary?.id {
                await plantService.load(propertyId: id)
            }
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await plantService.load(propertyId: id)
            }
        }
        .userActivity("com.prvio.plants") { activity in
            activity.title = "Plante — PRVIO"
            activity.userInfo = ["tab": "plants"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryRow
                plantsGrid
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
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
            let shouldCollapse = y < -30
            if shouldCollapse != tabBarVis.scrolledDown {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    tabBarVis.scrolledDown = shouldCollapse
                }
            }
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
                    label: "Nevoie de apă",
                    color: plantService.plantsNeedingWater.isEmpty
                        ? .primary
                        : Color(red: 1.0, green: 0.62, blue: 0.1)
                )
                Divider().frame(height: 32).opacity(0.3)
                statCell(
                    value: "\(plantService.healthyPlants.count)",
                    label: "Sănătoase",
                    color: plantService.healthyPlants.isEmpty
                        ? .primary
                        : Color(red: 0.15, green: 0.80, blue: 0.4)
                )
            }
        }
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
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
            if !plantService.plantsNeedingWater.isEmpty {
                sectionBlock(
                    title: "NEVOIE DE APĂ",
                    icon: "drop.fill",
                    iconColor: Color(red: 1.0, green: 0.62, blue: 0.1),
                    plants: plantService.plantsNeedingWater
                )
            }

            if !plantService.healthyPlants.isEmpty {
                sectionBlock(
                    title: "SĂNĂTOASE",
                    icon: "leaf.fill",
                    iconColor: Color(red: 0.15, green: 0.80, blue: 0.4),
                    plants: plantService.healthyPlants
                )
            }
        }
    }

    private func sectionBlock(title: String, icon: String, iconColor: Color, plants: [Plant]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(plants) { plant in
                    PlantCard(plant: plant) {
                        selectedPlant = plant
                    }
                    .environmentObject(plantService)
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
            Text("Nicio plantă adăugată")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Adaugă plante pentru a urmări\nudarea și starea lor de sănătate.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
            Button { showAddPlant = true } label: {
                Label("Adaugă prima plantă", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        Color.blue,
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
            Text("Nicio proprietate adăugată")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PlantCard

struct PlantCard: View {
    @EnvironmentObject private var plantService: PlantService
    let plant: Plant
    let onTap: () -> Void

    @State private var showDetail = false

    var body: some View {
        Button(action: {
            HapticFeedback.impact(.light)
            onTap()
        }) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    // Colored gradient strip with emoji
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

                    // Info area
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plant.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let species = plant.species, !species.isEmpty {
                            Text(species)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(plant.wateringLabel)
                            .font(.system(size: 12, weight: .medium))
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
                            Text(plant.lastWateredDisplay)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                        }
                    }
                    .padding(12)
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
                Label("Udat!", systemImage: "drop.fill")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await plantService.delete(plant) }
            } label: {
                Label("Șterge", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                HapticFeedback.success()
                Task { await plantService.markWatered(plant) }
            } label: {
                Label("Marchează udat", systemImage: "drop.fill")
            }

            Button {
                HapticFeedback.impact(.light)
                onTap()
            } label: {
                Label("Editează", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await plantService.delete(plant) }
            } label: {
                Label("Șterge", systemImage: "trash")
            }
        }
    }
}

// MARK: - PlantDetailSheet

struct PlantDetailSheet: View {
    @EnvironmentObject private var plantService: PlantService
    @Environment(\.dismiss) private var dismiss

    let plant: Plant

    @State private var isEditing = false
    @State private var editedPlant: Plant
    @State private var isSaving = false

    init(plant: Plant) {
        self.plant = plant
        _editedPlant = State(initialValue: plant)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header card
                        headerCard

                        if isEditing {
                            editFields
                        } else {
                            viewFields
                            waterButton
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(plant.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Anulare") {
                            editedPlant = plant
                            withAnimation { isEditing = false }
                        }
                    } else {
                        Button("Închide") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button {
                            save()
                        } label: {
                            if isSaving {
                                ProgressView().tint(.blue)
                            } else {
                                Text("Salvează")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .disabled(editedPlant.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    } else {
                        Button {
                            withAnimation { isEditing = true }
                        } label: {
                            Text("Editează")
                                .font(.system(size: 15))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: Header card

    private var headerCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [
                            plant.healthColor.opacity(0.2),
                            plant.healthColor.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 100)

                    Text(isEditing ? editedPlant.emoji : plant.emoji)
                        .font(.system(size: 56))
                }

                VStack(spacing: 4) {
                    Text(isEditing ? editedPlant.name : plant.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    if let species = (isEditing ? editedPlant.species : plant.species), !species.isEmpty {
                        Text(species)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: View fields

    private var viewFields: some View {
        VStack(spacing: 12) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    detailRow(
                        icon: plant.healthIcon,
                        iconColor: plant.healthColor,
                        label: "Sănătate",
                        value: Plant.healthOptions.first { $0.id == plant.healthStatus }?.label ?? plant.healthStatus
                    )
                    rowDivider
                    detailRow(
                        icon: "drop.fill",
                        iconColor: .blue,
                        label: "Ultima udare",
                        value: plant.lastWateredDisplay
                    )
                    rowDivider
                    detailRow(
                        icon: "clock.fill",
                        iconColor: .purple,
                        label: "Interval udare",
                        value: "La fiecare \(plant.wateringIntervalDays) zile"
                    )
                    rowDivider
                    detailRow(
                        icon: "drop.triangle.fill",
                        iconColor: plant.needsWatering
                            ? Color(red: 1.0, green: 0.62, blue: 0.1)
                            : Color(red: 0.15, green: 0.80, blue: 0.4),
                        label: "Status udare",
                        value: plant.wateringLabel
                    )
                    if let location = plant.location, !location.isEmpty {
                        rowDivider
                        detailRow(
                            icon: "mappin.circle.fill",
                            iconColor: .red,
                            label: "Locație",
                            value: location
                        )
                    }
                }
            }

            if let notes = plant.notes, !notes.isEmpty {
                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Note", systemImage: "note.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func detailRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.5))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    // MARK: Water button

    private var waterButton: some View {
        Button {
            HapticFeedback.success()
            Task { await plantService.markWatered(plant) }
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Marchează udat")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Edit fields

    private var editFields: some View {
        VStack(spacing: 20) {
            // Emoji picker
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("EMOJI")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(Plant.emojiOptions, id: \.self) { emoji in
                        Button {
                            editedPlant.emoji = emoji
                            HapticFeedback.selection()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(width: 40, height: 40)
                                .background(
                                    editedPlant.emoji == emoji
                                        ? Color.blue.opacity(0.18)
                                        : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            editedPlant.emoji == emoji ? Color.blue : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Name
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("DENUMIRE *")
                TextField("Numele plantei", text: $editedPlant.name)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .tint(.blue)
                    .padding(14)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }

            // Species
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("SPECIE (OPȚIONAL)")
                TextField("ex. Monstera deliciosa", text: Binding(
                    get: { editedPlant.species ?? "" },
                    set: { editedPlant.species = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            // Location
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("LOCAȚIE (OPȚIONAL)")
                TextField("ex. Living, Balcon, Bucătărie", text: Binding(
                    get: { editedPlant.location ?? "" },
                    set: { editedPlant.location = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            // Health status
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("STARE SĂNĂTATE")
                HStack(spacing: 8) {
                    ForEach(Plant.healthOptions, id: \.id) { opt in
                        Button {
                            editedPlant.healthStatus = opt.id
                            HapticFeedback.selection()
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 12, weight: editedPlant.healthStatus == opt.id ? .semibold : .regular))
                                .foregroundStyle(
                                    editedPlant.healthStatus == opt.id ? .white : Color.primary.opacity(0.65)
                                )
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    editedPlant.healthStatus == opt.id
                                        ? plantHealthColor(opt.id)
                                        : Color.primary.opacity(0.07),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Watering interval
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("INTERVAL UDARE")
                HStack {
                    Text("La fiecare \(editedPlant.wateringIntervalDays) \(editedPlant.wateringIntervalDays == 1 ? "zi" : "zile")")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Stepper("", value: $editedPlant.wateringIntervalDays, in: 1...30)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("NOTE (OPȚIONAL)")
                TextField("Notițe despre această plantă…", text: Binding(
                    get: { editedPlant.notes ?? "" },
                    set: { editedPlant.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .lineLimit(3...6)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func plantHealthColor(_ id: String) -> Color {
        switch id {
        case "great":       return Color(red: 0.15, green: 0.80, blue: 0.4)
        case "good":        return Color(red: 0.25, green: 0.72, blue: 0.35)
        case "needs_water": return Color(red: 1.0,  green: 0.62, blue: 0.1)
        case "critical":    return .red
        default:            return .gray
        }
    }

    // MARK: Save

    private func save() {
        let trimmed = editedPlant.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        var toSave = editedPlant
        toSave.name = trimmed
        Task {
            await plantService.update(toSave)
            HapticFeedback.success()
            isSaving = false
            withAnimation { isEditing = false }
        }
    }
}

// MARK: - AddPlantSheet

struct AddPlantSheet: View {
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var species = ""
    @State private var location = ""
    @State private var selectedEmoji = Plant.emojiOptions.first ?? "🪴"
    @State private var healthStatus = "good"
    @State private var wateringIntervalDays = 7
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        emojiPickerSection
                        nameField
                        speciesField
                        locationField
                        healthPickerSection
                        wateringIntervalSection
                        notesField
                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Plantă nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulare") { dismiss() }
                }
            }
        }
    }

    // MARK: Emoji picker

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("EMOJI")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Plant.emojiOptions, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            HapticFeedback.selection()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 52, height: 52)
                                .background(
                                    selectedEmoji == emoji
                                        ? Color.blue.opacity(0.15)
                                        : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            selectedEmoji == emoji ? Color.blue : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Text fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("DENUMIRE *")
            TextField("Numele plantei", text: $name)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.blue)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var speciesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("SPECIE (OPȚIONAL)")
            TextField("ex. Monstera deliciosa", text: $species)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("LOCAȚIE (OPȚIONAL)")
            TextField("ex. Living, Balcon, Bucătărie", text: $location)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTE (OPȚIONAL)")
            TextField("Notițe despre această plantă…", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .lineLimit(3...5)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    // MARK: Health picker

    private var healthPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("STARE SĂNĂTATE")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Plant.healthOptions, id: \.id) { opt in
                    Button {
                        healthStatus = opt.id
                        HapticFeedback.selection()
                    } label: {
                        Text(opt.label)
                            .font(.system(size: 13, weight: healthStatus == opt.id ? .semibold : .regular))
                            .foregroundStyle(
                                healthStatus == opt.id ? .white : Color.primary.opacity(0.65)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                healthStatus == opt.id
                                    ? healthColorFor(opt.id)
                                    : Color.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Watering interval

    private var wateringIntervalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("INTERVAL UDARE")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("La fiecare \(wateringIntervalDays) \(wateringIntervalDays == 1 ? "zi" : "zile")")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text("Vei fi notificat când e timpul să udați")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("", value: $wateringIntervalDays, in: 1...30)
                    .labelsHidden()
            }
            .padding(14)
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    // MARK: Save button

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Adaugă planta")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                canSave ? Color.blue : Color.primary.opacity(0.2),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(
                canSave ? Color.white : Color.primary.opacity(0.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func healthColorFor(_ id: String) -> Color {
        switch id {
        case "great":       return Color(red: 0.15, green: 0.80, blue: 0.4)
        case "good":        return Color(red: 0.25, green: 0.72, blue: 0.35)
        case "needs_water": return Color(red: 1.0,  green: 0.62, blue: 0.1)
        case "critical":    return .red
        default:            return .gray
        }
    }

    private func save() {
        guard let propId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        error = nil
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewPlantPayload(
            propertyId: propId,
            ownerId: ownerId,
            name: trimmedName,
            species: species.trimmingCharacters(in: .whitespaces).isEmpty ? nil : species.trimmingCharacters(in: .whitespaces),
            location: location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location.trimmingCharacters(in: .whitespaces),
            wateringIntervalDays: wateringIntervalDays,
            healthStatus: healthStatus,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces),
            emoji: selectedEmoji,
            createdAt: now,
            updatedAt: now
        )
        Task {
            do {
                _ = try await plantService.add(payload)
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

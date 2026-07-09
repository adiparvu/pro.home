import SwiftUI
import PhotosUI

// MARK: - PlantDetailSheet sections

extension PlantDetailSheet {

    // MARK: Header card

    var headerCard: some View {
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
                        .font(AppFont.scaled(56))
                }

                VStack(spacing: 4) {
                    Text(isEditing ? editedPlant.name : plant.name)
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)

                    if let species = (isEditing ? editedPlant.species : plant.species), !species.isEmpty {
                        Text(species)
                            .font(AppFont.scaled(14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, AppSpacing.base)
            }
        }
    }

    // MARK: View fields

    var viewFields: some View {
        VStack(spacing: 12) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    detailRow(
                        icon: plant.healthIcon,
                        iconColor: plant.healthColor,
                        label: "Health",
                        value: plant.localizedHealthLabel
                    )
                    rowDivider
                    detailRow(
                        icon: "drop.fill",
                        iconColor: .blue,
                        label: "Last watered",
                        value: plant.lastWateredDisplay
                    )
                    rowDivider
                    detailRow(
                        icon: "clock.fill",
                        iconColor: .purple,
                        label: "Watering interval",
                        value: "Every \(plant.wateringIntervalDays) days"
                    )
                    rowDivider
                    detailRow(
                        icon: "drop.triangle.fill",
                        iconColor: plant.needsWatering
                            ? Color(red: 1.0, green: 0.62, blue: 0.1)
                            : Color(red: 0.15, green: 0.80, blue: 0.4),
                        label: "Watering status",
                        value: plant.wateringLabel
                    )
                    if let location = plant.location, !location.isEmpty {
                        rowDivider
                        detailRow(
                            icon: "mappin.circle.fill",
                            iconColor: .red,
                            label: "Location",
                            value: location
                        )
                    }
                }
            }

            if let notes = plant.notes, !notes.isEmpty {
                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func detailRow(icon: String, iconColor: Color, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .glassRoundedRect(AppRadius.sm)
            Text(label)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    // MARK: Water button

    var waterButton: some View {
        Button {
            HapticFeedback.success()
            Task { await plantService.markWatered(plant) }
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(AppFont.headline)
                Text("Mark as watered")
                    .font(AppFont.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color(red: 0.1, green: 0.4, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Edit fields

    var editFields: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("EMOJI")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(Plant.emojiOptions, id: \.self) { emoji in
                        Button {
                            editedPlant.emoji = emoji
                            HapticFeedback.selection()
                        } label: {
                            Text(emoji)
                                .font(AppFont.scaled(26))
                                .frame(width: 40, height: 40)
                                .background(
                                    editedPlant.emoji == emoji
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.primary.opacity(AppOpacity.hairline),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            editedPlant.emoji == emoji ? Color.accentColor : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("NAME *")
                TextField("Plant name", text: $editedPlant.name)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .padding(AppSpacing.base)
                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("SPECIES (OPTIONAL)")
                TextField("e.g. Monstera deliciosa", text: Binding(
                    get: { editedPlant.species ?? "" },
                    set: { editedPlant.species = $0.isEmpty ? nil : $0 }
                ))
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("LOCATION (OPTIONAL)")
                TextField("e.g. Living room, Balcony, Kitchen", text: Binding(
                    get: { editedPlant.location ?? "" },
                    set: { editedPlant.location = $0.isEmpty ? nil : $0 }
                ))
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("HEALTH STATUS")
                HStack(spacing: 8) {
                    ForEach(Plant.healthOptions, id: \.id) { opt in
                        Button {
                            editedPlant.healthStatus = opt.id
                            HapticFeedback.selection()
                        } label: {
                            Text(LocalizedStringKey(opt.label))
                                .font(AppFont.scaled(12, weight: editedPlant.healthStatus == opt.id ? .semibold : .regular))
                                .foregroundStyle(
                                    editedPlant.healthStatus == opt.id ? .white : Color.primary.opacity(0.65)
                                )
                                .padding(.horizontal, 11)
                                .padding(.vertical, AppSpacing.sm)
                                .background(
                                    editedPlant.healthStatus == opt.id
                                        ? plantHealthColor(opt.id)
                                        : Color.primary.opacity(AppOpacity.subtleFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("WATERING INTERVAL")
                HStack {
                    Text(editedPlant.wateringIntervalDays == 1 ? "Every \(editedPlant.wateringIntervalDays) day" : "Every \(editedPlant.wateringIntervalDays) days")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Stepper("", value: $editedPlant.wateringIntervalDays, in: 1...30)
                        .labelsHidden()
                }
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("NOTES (OPTIONAL)")
                TextField("Notes about this plant…", text: Binding(
                    get: { editedPlant.notes ?? "" },
                    set: { editedPlant.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(3...6)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
        }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.label)
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

    func save() {
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

    // MARK: General information card (P1, view mode)

    @ViewBuilder
    var generalInfoCard: some View {
        let rows: [(LocalizedStringKey, String)] = [
            ("plant_gi_nickname", plant.nickname ?? ""),
            ("plant_gi_latin", plant.latinName ?? ""),
            ("plant_gi_family", plant.botanicalFamily ?? ""),
            ("plant_gi_genus", plant.genus ?? ""),
            ("plant_gi_cultivar", plant.cultivar ?? ""),
            ("plant_gi_origin", plant.origin ?? ""),
            ("plant_gi_climate", plant.climateZone ?? ""),
        ].filter { !$0.1.isEmpty }
        let toxicity = plant.toxicitySummary
        let hasAny = !rows.isEmpty || plant.placementLabel != nil || !toxicity.isEmpty

        if hasAny {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("plant_gi_title", systemImage: "leaf.arrow.triangle.circlepath")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(AppFont.scaled(14)).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(AppFont.scaled(14)).foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let place = plant.placementLabel {
                        HStack {
                            Text("plant_gi_placement").font(AppFont.scaled(14)).foregroundStyle(.secondary)
                            Spacer()
                            Text(place).font(AppFont.scaled(14)).foregroundStyle(.primary)
                        }
                    }
                    if !toxicity.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(AppFont.scaled(11)).foregroundStyle(.orange)
                            Text(String(format: String(localized: "plant_tox_fmt"),
                                        toxicity.joined(separator: ", ")))
                                .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Botanical profile (P2, view mode)
    //
    // Links a plant to its encyclopedia entry. The linked id is read back from
    // `plantService` (not the immutable `plant` snapshot) so linking/unlinking
    // updates the card live; the catalog itself comes from the locally loaded
    // `speciesService`.

    @ViewBuilder
    var botanicalProfileCard: some View {
        let currentId = plantService.plants.first(where: { $0.id == plant.id })?.speciesId ?? plant.speciesId
        let entry = speciesService.species(id: currentId)

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("plant_bot_title", systemImage: "book.closed")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    Spacer()
                    if currentId != nil {
                        Menu {
                            Button { showSpeciesPicker = true } label: {
                                Label("plant_bot_change", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                Task { await plantService.linkSpecies(nil, for: plant) }
                            } label: {
                                Label("plant_bot_unlink", systemImage: "link.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(AppFont.scaled(18)).foregroundStyle(.secondary)
                        }
                    }
                }

                if let entry {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.displayName)
                            .font(AppFont.scaled(16, weight: .semibold)).foregroundStyle(.primary)
                        if let latin = entry.latinName, !latin.isEmpty, latin != entry.displayName {
                            Text(latin).font(AppFont.caption).italic().foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    NavigationLink {
                        PlantEncyclopediaView(entry: entry)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "book.pages")
                            Text("plant_bot_view_enc")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                        }
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                    }
                } else if currentId != nil {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("plant_bot_loading").font(AppFont.scaled(13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("plant_bot_none")
                        .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { showSpeciesPicker = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("plant_bot_link")
                        }
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Health — ailments & guided diagnosis (P4, view mode)
    //
    // A gateway card into the health surface: guided symptom diagnosis over the
    // offline ailments knowledge base plus a browsable reference. Passes the
    // plant's linked species (read live from plantService, like the botanical
    // card) so diagnosis can weight the species' known susceptibilities.

    @ViewBuilder
    var healthCard: some View {
        let currentId = plantService.plants.first(where: { $0.id == plant.id })?.speciesId ?? plant.speciesId
        let riskCount = ailmentService.susceptibilities(forSpecies: currentId).count

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("plant_health_title", systemImage: "cross.case")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)

                Text("plant_health_card_sub")
                    .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if riskCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield")
                            .font(AppFont.scaled(11)).foregroundStyle(.orange)
                        Text(String(format: String(localized: "plant_health_card_risks_fmt"), riskCount))
                            .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.75))
                    }
                }

                NavigationLink {
                    PlantHealthView(service: ailmentService,
                                    speciesId: currentId,
                                    speciesName: plant.name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stethoscope")
                        Text("plant_health_card_open")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                    }
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Photo album (P1, view mode)

    var photoAlbumCard: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("plant_album_title", systemImage: "photo.stack")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    Spacer()
                    if isUploadingPhoto { ProgressView().scaleEffect(0.7) }
                    Menu {
                        Button { showAlbumCamera = true } label: { Label("Camera", systemImage: "camera.fill") }
                        PhotosPicker(selection: $albumPickerItem, matching: .images) {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(AppFont.scaled(20)).foregroundStyle(Color.accentColor)
                    }
                }
                if photoService.photos.isEmpty {
                    Text("plant_album_empty")
                        .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photoService.photos) { photo in
                                PlantAlbumThumb(photo: photo) {
                                    Task { await photoService.delete(photo) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: General information edit fields (P1)

    var generalInfoEditFields: some View {
        VStack(spacing: 16) {
            giEditField("plant_gi_nickname", get: { editedPlant.nickname }, set: { editedPlant.nickname = $0 })
            giEditField("plant_gi_latin", get: { editedPlant.latinName }, set: { editedPlant.latinName = $0 })
            giEditField("plant_gi_family", get: { editedPlant.botanicalFamily }, set: { editedPlant.botanicalFamily = $0 })
            giEditField("plant_gi_genus", get: { editedPlant.genus }, set: { editedPlant.genus = $0 })
            giEditField("plant_gi_cultivar", get: { editedPlant.cultivar }, set: { editedPlant.cultivar = $0 })
            giEditField("plant_gi_origin", get: { editedPlant.origin }, set: { editedPlant.origin = $0 })
            giEditField("plant_gi_climate", get: { editedPlant.climateZone }, set: { editedPlant.climateZone = $0 })

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("plant_gi_placement")
                Picker("", selection: Binding(get: { editedPlant.placement ?? "" },
                                              set: { editedPlant.placement = $0.isEmpty ? nil : $0 })) {
                    Text("plant_place_unset").tag("")
                    Text("plant_place_indoor").tag("indoor")
                    Text("plant_place_outdoor").tag("outdoor")
                    Text("plant_place_both").tag("both")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("plant_gi_toxicity")
                Toggle("plant_tox_cats", isOn: $editedPlant.toxicCats).font(AppFont.scaled(14))
                Toggle("plant_tox_dogs", isOn: $editedPlant.toxicDogs).font(AppFont.scaled(14))
                Toggle("plant_tox_kids", isOn: $editedPlant.toxicKids).font(AppFont.scaled(14))
            }
            .tint(.accentColor)
        }
    }

    private func giEditField(_ label: LocalizedStringKey,
                             get: @escaping () -> String?, set: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            TextField("", text: Binding(get: { get() ?? "" }, set: { set($0.isEmpty ? nil : $0) }))
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .autocorrectionDisabled()
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                           in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }
}

// MARK: - Album thumbnail (signed-URL resolved)

private struct PlantAlbumThumb: View {
    let photo: PlantPhoto
    let onDelete: () -> Void
    @State private var url: URL?

    var body: some View {
        VStack(spacing: 4) {
            StorageImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(Color.primary.opacity(0.06)).overlay(ProgressView().scaleEffect(0.6))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16)).foregroundStyle(.white, .black.opacity(0.4))
                }
                .padding(4)
            }
            Text(photo.takenDisplay).font(AppFont.scaled(10)).foregroundStyle(.secondary)
        }
        .task(id: photo.url) { url = await PlantPhotoService.resolve(photo.url) }
    }
}

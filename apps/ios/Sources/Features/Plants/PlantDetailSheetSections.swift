import SwiftUI
import PhotosUI
import UIKit

// MARK: - PlantDetailSheet sections

extension PlantDetailSheet {

    // MARK: Plant QR label (IMG_8718 request)
    //
    // Same universal-link family as the inventory labels: scanning
    // https://xparvu.com/p/<uuid> opens the app straight on the scan
    // landing sheet (web shows a generic "open in PRVIO" fallback —
    // plants are private, so the page carries no data).

    var plantQRContent: String {
        "https://xparvu.com/p/\(plant.id.uuidString.lowercased())"
    }

    var plantQRCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                Label("plant_qr_title", systemImage: "qrcode")
                    .onAppear {
                        // Showing the label IS the opt-in: mirror the
                        // plant's public card so ANY phone that scans it
                        // sees the details (migration 174, IMG_8728).
                        PublicPlantMirror.sync(plant)
                    }
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                QRCodeImage(content: plantQRContent, size: 160)
                    .frame(maxWidth: .infinity)
                Text("plant_qr_caption")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .multilineTextAlignment(.center)
                // Three equal icon actions (IMG_8779): share the label,
                // print it directly, and preview the public page a scanner
                // would land on.
                HStack(spacing: 10) {
                    qrActionButton("square.and.arrow.up", a11y: "Share") {
                        sharePlantQR()
                    }
                    qrActionButton("printer", a11y: "Print") {
                        printPlantQR()
                    }
                    qrActionButton("safari", a11y: "plant_qr_view_page") {
                        if let url = URL(string: plantQRContent) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func qrActionButton(_ icon: String, a11y: LocalizedStringKey,
                                action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(15, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(.blue.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(Text(a11y))
    }

    /// The same print-resolution label, straight to AirPrint.
    func printPlantQR() {
        let renderer = ImageRenderer(content: QRCodeImage(content: plantQRContent, size: 300))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        SystemActions.print(image: image)
    }

    /// Renders the label at print resolution and hands it to the share
    /// sheet as a PNG file (AirPrint, Save to Files, Messages…).
    func sharePlantQR() {
        let renderer = ImageRenderer(content: QRCodeImage(content: plantQRContent, size: 300))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        let name = plant.name.isEmpty ? "plant" : plant.name
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QR-\(name).png")
        guard (try? data.write(to: url)) != nil else { return }
        exportURL = ShareURL(url: url)
    }

    // MARK: Header card (v2 — IMG_8730/8731 "alt gen")
    //
    // Item-Detail-v2 family look: one immersive hero — deep health-tinted
    // gradient, big breathing emoji, name INSIDE the hero, species as its
    // subtitle, and honest chips (location, health) — instead of the old
    // pale strip + separate 4-row table.

    var headerCard: some View {
        GlassCard(padding: 0) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [plant.healthColor.opacity(0.42),
                             plant.healthColor.opacity(0.10)],
                    startPoint: .top, endPoint: .bottom)
                VStack(spacing: 8) {
                    Text(isEditing ? editedPlant.emoji : plant.emoji)
                        .font(AppFont.scaled(64))
                        .padding(.top, AppSpacing.lg)
                    Text(isEditing ? editedPlant.name : plant.name)
                        .font(AppFont.scaled(24, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    if let species = (isEditing ? editedPlant.species : plant.species), !species.isEmpty {
                        Text(species)
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .italic()
                    }
                    HStack(spacing: 8) {
                        heroChip(plant.localizedHealthLabel, icon: plant.healthIcon,
                                 tint: plant.healthColor)
                        if let location = plant.location, !location.isEmpty {
                            heroChip(location, icon: "mappin.circle.fill", tint: .red)
                        }
                    }
                    .padding(.bottom, AppSpacing.lg)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func heroChip(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(AppFont.scaled(11)).foregroundStyle(tint)
            Text(text).font(AppFont.scaled(12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    // MARK: Quick actions (v2) — the everyday verbs as one glass row.

    var plantQuickActions: some View {
        HStack(spacing: 10) {
            Group {
                GlassActionButton(icon: "drop.fill", label: "plant_qa_water") {
                    HapticFeedback.success()
                    Task { await plantService.markWatered(plant) }
                }
                GlassActionButton(icon: "camera.fill", label: "plant_qa_photo") {
                    HapticFeedback.impact(.light)
                    showAlbumCamera = true
                }
                GlassActionButton(icon: "qrcode", label: "plant_qa_qr") {
                    HapticFeedback.impact(.light)
                    sharePlantQR()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: View fields

    var viewFields: some View {
        VStack(spacing: 12) {
            plantQuickActions

            // Watering as ONE living gauge (v2): the bar fills as the plant
            // drinks through its interval — thirst is visible at a glance,
            // instead of four detached table rows saying the same thing.
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Watering status", systemImage: "drop.fill")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.secondaryTextColor)
                        Spacer()
                        Text(plant.wateringLabel)
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(plant.needsWatering
                                ? Color.brandWarning : Color.brandSuccess)
                    }
                    GeometryReader { geo in
                        let interval = max(plant.wateringIntervalDays, 1)
                        let elapsed = plant.lastWateredAtDate.map {
                            Date().timeIntervalSince($0) / 86_400
                        } ?? Double(interval)
                        let f = min(max(elapsed / Double(interval), 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color.brandSkyBlue,
                                             f > 0.85 ? Color.brandWarning : Color.brandSkyBlue],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(geo.size.width * f, 8))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(String(format: String(localized: "plant_care_last_fmt"),
                                    plant.lastWateredDisplay))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                        Text(Plant.wateringIntervalDisplay(plant.wateringIntervalDays))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                }
            }

            if let notes = plant.notes, !notes.isEmpty {
                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.secondaryTextColor)
                        Text(notes)
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }


    // MARK: Edit fields

    var editFields: some View {
        VStack(spacing: 20) {
            // IDENTITY first (IMG_8730 "regândește"): the name is the field
            // people actually came to type; the emoji browse follows it.
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("NAME *")
                TextField("Plant name", text: $editedPlant.name)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .padding(AppSpacing.base)
                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            // The shared searchable picker (Components/EmojiPickerField):
            // same favorites strip as the add form, plus RO/EN search and
            // the full sectioned nature catalog.
            EmojiPickerField(selection: $editedPlant.emoji, favorites: Plant.emojiOptions)

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
                    Text(Plant.wateringIntervalDisplay(editedPlant.wateringIntervalDays))
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
            .foregroundStyle(Color.secondaryTextColor)
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
            withAnimation(AppMotion.state) { isEditing = false }
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
                        .font(AppFont.captionStrong).foregroundStyle(Color.secondaryTextColor)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(AppFont.scaled(14)).foregroundStyle(Color.secondaryTextColor)
                            Spacer()
                            Text(r.1).font(AppFont.scaled(14)).foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let place = plant.placementLabel {
                        HStack {
                            Text("plant_gi_placement").font(AppFont.scaled(14)).foregroundStyle(Color.secondaryTextColor)
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
                        .font(AppFont.captionStrong).foregroundStyle(Color.secondaryTextColor)
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
                                .font(AppFont.scaled(18)).foregroundStyle(Color.secondaryTextColor)
                        }
                        .accessibilityLabel("More")
                    }
                }

                if let entry {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.displayName)
                            .font(AppFont.scaled(16, weight: .semibold)).foregroundStyle(.primary)
                        if let latin = entry.latinName, !latin.isEmpty, latin != entry.displayName {
                            Text(latin).font(AppFont.caption).italic().foregroundStyle(Color.secondaryTextColor)
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
                        Text("plant_bot_loading").font(AppFont.scaled(13)).foregroundStyle(Color.secondaryTextColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("plant_bot_none")
                        .font(AppFont.scaled(13)).foregroundStyle(Color.secondaryTextColor)
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
                    .font(AppFont.captionStrong).foregroundStyle(Color.secondaryTextColor)

                Text("plant_health_card_sub")
                    .font(AppFont.scaled(13)).foregroundStyle(Color.secondaryTextColor)
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
                        .font(AppFont.captionStrong).foregroundStyle(Color.secondaryTextColor)
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
                    .accessibilityLabel("Add photo")
                }
                if photoService.photos.isEmpty {
                    Text("plant_album_empty")
                        .font(AppFont.scaled(13)).foregroundStyle(Color.secondaryTextColor)
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
                .accessibilityLabel("Delete photo")
            }
            Text(photo.takenDisplay).font(AppFont.scaled(10)).foregroundStyle(Color.secondaryTextColor)
        }
        .task(id: photo.url) { url = await PlantPhotoService.resolve(photo.url) }
    }
}

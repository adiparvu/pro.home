import SwiftUI
import PhotosUI

// MARK: - AddPlantSheet

struct AddPlantSheet: View {
    @Environment(PlantService.self) private var plantService
    @Environment(PropertyService.self) private var propertyService
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
    @State private var selectedImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showPhotoMenu = false
    @State private var showLibrary = false
    @State private var showSpeciesCatalog = false
    @State private var pickedSpecies: PlantSpecies?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        catalogSection
                        emojiPickerSection
                        plantPhotoSection
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
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle("New Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    selectedImageData = image.jpegData(compressionQuality: 0.85)
                }
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .jpeg, .png, .heic]
            ) { result in
                if case .success(let url) = result {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    selectedImageData = try? Data(contentsOf: url)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                    }
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $selectedPhotoItem, matching: .images)
            .sheet(isPresented: $showSpeciesCatalog) {
                PlantSpeciesPicker { picked in
                    apply(picked)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: Species catalog

    /// One tap prefills name + species (Latin) + emoji + watering interval
    /// from the built-in horticultural catalog; everything stays editable.
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button { showSpeciesCatalog = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    Text("plant_catalog_row")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(AppSpacing.base)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                Color.primary.opacity(AppOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            )

            if let picked = pickedSpecies {
                HStack(spacing: AppSpacing.xs) {
                    Text(picked.emoji)
                        .font(AppFont.caption)
                    Text(picked.name)
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(picked.latin)
                        .font(AppFont.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: picked.light.symbol)
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(LocalizedStringKey(picked.light.titleKey)))
                }
                .padding(.horizontal, AppSpacing.xxs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.25), value: pickedSpecies)
    }

    private func apply(_ picked: PlantSpecies) {
        pickedSpecies = picked
        name = picked.name
        species = picked.latin
        selectedEmoji = picked.emoji
        wateringIntervalDays = picked.wateringDays
    }

    // MARK: Emoji picker

    /// A catalog pick may carry an emoji outside the preset strip (🍅, 🍎…);
    /// surface it as the first, selected option instead of losing it.
    private var emojiChoices: [String] {
        Plant.emojiOptions.contains(selectedEmoji)
            ? Plant.emojiOptions
            : [selectedEmoji] + Plant.emojiOptions
    }

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("EMOJI")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(emojiChoices, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            HapticFeedback.selection()
                        } label: {
                            Text(emoji)
                                .font(AppFont.scaled(30))
                                .frame(width: 52, height: 52)
                                .background(
                                    selectedEmoji == emoji
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.primary.opacity(AppOpacity.hairline),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .strokeBorder(
                                            selectedEmoji == emoji ? Color.accentColor : Color.clear,
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

    // MARK: Plant photo

    private var plantPhotoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("FOTOGRAFIE (OPȚIONAL)")
            Button { showPhotoMenu = true } label: {
                ZStack {
                    if let data = selectedImageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 150)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(maxWidth: .infinity).frame(height: 150)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(AppFont.scaled(24))
                                        .foregroundStyle(Color.accentColor.opacity(0.7))
                                    Text("Adaugă fotografie")
                                        .font(AppFont.scaled(13, weight: .medium))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                }
                            )
                    }
                    if selectedImageData != nil {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    selectedImageData = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(AppFont.scaled(22))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo")
                                .padding(10)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(
                        selectedImageData != nil ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
                        lineWidth: selectedImageData != nil ? 1.5 : 0.5
                    )
            )
            .confirmationDialog("Fotografie plantă", isPresented: $showPhotoMenu) {
                Button("Cameră") { showCamera = true }
                Button("Bibliotecă") { showLibrary = true }
                Button("Fișiere") { showFileImporter = true }
                Button("Anulează", role: .cancel) {}
            }
        }
    }

    // MARK: Text fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NAME *")
            TextField("Plant name", text: $name)
                .font(AppFont.scaled(16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    private var speciesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("SPECIES (OPTIONAL)")
            TextField("e.g. Monstera deliciosa", text: $species)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("LOCATION (OPTIONAL)")
            TextField("e.g. Living room, Balcony, Kitchen", text: $location)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES (OPTIONAL)")
            TextField("Notes about this plant…", text: $notes, axis: .vertical)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(3...5)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    // MARK: Health picker

    private var healthPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("HEALTH STATUS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Plant.healthOptions, id: \.id) { opt in
                    Button {
                        healthStatus = opt.id
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 5) {
                            if healthStatus == opt.id {
                                Image(systemName: "checkmark")
                                    .font(AppFont.label)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            Text(LocalizedStringKey(opt.label))
                                .font(AppFont.scaled(13, weight: healthStatus == opt.id ? .semibold : .regular))
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .mediaGlass(in: Capsule(), interactive: true)
                        .overlay(
                            Capsule().strokeBorder(
                                healthStatus == opt.id ? Color.primary.opacity(0.35) : Color.clear,
                                lineWidth: 1.5
                            )
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
            fieldLabel("WATERING INTERVAL")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wateringIntervalDays == 1 ? "Every \(wateringIntervalDays) day" : "Every \(wateringIntervalDays) days")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text("You'll be notified when it's time to water")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("", value: $wateringIntervalDays, in: 1...30)
                    .labelsHidden()
            }
            .padding(AppSpacing.base)
            .background(
                Color.primary.opacity(AppOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            )
        }
    }

    // MARK: Save button

    private var saveButton: some View {
        GlassWideButton(label: "Add plant", isBusy: isSaving) {
            save()
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
    }

    // MARK: Helpers

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
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
                let plant = try await plantService.add(payload)
                if let data = selectedImageData {
                    PlantImageStore.save(data, for: plant.id)
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Local image store for plants

enum PlantImageStore {
    private static func url(for id: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plant_\(id.uuidString).jpg")
    }

    static func save(_ data: Data, for id: UUID) {
        let compressed: Data
        if let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.75) {
            compressed = jpg
        } else {
            compressed = data
        }
        try? compressed.write(to: url(for: id))
    }

    static func load(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}

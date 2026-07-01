import SwiftUI
import PhotosUI

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
    @State private var selectedImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showPhotoMenu = false
    @State private var showLibrary = false

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
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.primary.opacity(AppOpacity.hairline),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color.accentColor.opacity(0.7))
                                    Text("Adaugă fotografie")
                                        .font(.system(size: 13, weight: .medium))
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
                                        .font(.system(size: 22))
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var speciesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("SPECIES (OPTIONAL)")
            TextField("e.g. Monstera deliciosa", text: $species)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("LOCATION (OPTIONAL)")
            TextField("e.g. Living room, Balcony, Kitchen", text: $location)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES (OPTIONAL)")
            TextField("Notes about this plant…", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(3...5)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                        Text(LocalizedStringKey(opt.label))
                            .font(.system(size: 13, weight: healthStatus == opt.id ? .semibold : .regular))
                            .foregroundStyle(
                                healthStatus == opt.id ? .white : Color.primary.opacity(0.65)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                healthStatus == opt.id
                                    ? healthColorFor(opt.id)
                                    : Color.primary.opacity(AppOpacity.subtleFill),
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
            fieldLabel("WATERING INTERVAL")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wateringIntervalDays == 1 ? "Every \(wateringIntervalDays) day" : "Every \(wateringIntervalDays) days")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text("You'll be notified when it's time to water")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("", value: $wateringIntervalDays, in: 1...30)
                    .labelsHidden()
            }
            .padding(AppSpacing.base)
            .background(
                Color.primary.opacity(AppOpacity.subtleFill),
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
                    Text("Add plant")
                        .font(AppFont.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                canSave ? Color.accentColor : Color.primary.opacity(0.2),
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

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.label)
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

import SwiftUI

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
            .navigationTitle("New Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.primary.opacity(0.06),
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

    // MARK: Text fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NAME *")
            TextField("Plant name", text: $name)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
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
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
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
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
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
            fieldLabel("HEALTH STATUS")
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
            fieldLabel("WATERING INTERVAL")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every \(wateringIntervalDays) \(wateringIntervalDays == 1 ? "day" : "days")")
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
                    Text("Add plant")
                        .font(.system(size: 16, weight: .semibold))
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

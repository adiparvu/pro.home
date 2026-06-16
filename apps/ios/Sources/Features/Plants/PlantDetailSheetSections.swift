import SwiftUI

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

    var viewFields: some View {
        VStack(spacing: 12) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    detailRow(
                        icon: plant.healthIcon,
                        iconColor: plant.healthColor,
                        label: "Health",
                        value: Plant.healthOptions.first { $0.id == plant.healthStatus }?.label ?? plant.healthStatus
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

    var waterButton: some View {
        Button {
            HapticFeedback.success()
            Task { await plantService.markWatered(plant) }
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Mark as watered")
                    .font(.system(size: 16, weight: .semibold))
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
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                                .font(.system(size: 26))
                                .frame(width: 40, height: 40)
                                .background(
                                    editedPlant.emoji == emoji
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.primary.opacity(0.06),
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
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .padding(14)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("SPECIES (OPTIONAL)")
                TextField("e.g. Monstera deliciosa", text: Binding(
                    get: { editedPlant.species ?? "" },
                    set: { editedPlant.species = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("LOCATION (OPTIONAL)")
                TextField("e.g. Living room, Balcony, Kitchen", text: Binding(
                    get: { editedPlant.location ?? "" },
                    set: { editedPlant.location = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("HEALTH STATUS")
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

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("WATERING INTERVAL")
                HStack {
                    Text("Every \(editedPlant.wateringIntervalDays) \(editedPlant.wateringIntervalDays == 1 ? "day" : "days")")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Stepper("", value: $editedPlant.wateringIntervalDays, in: 1...30)
                        .labelsHidden()
                }
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("NOTES (OPTIONAL)")
                TextField("Notes about this plant…", text: Binding(
                    get: { editedPlant.notes ?? "" },
                    set: { editedPlant.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(3...6)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
}

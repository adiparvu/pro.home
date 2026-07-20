import SwiftUI

// MARK: - Add supply list sheet

struct AddSupplyListSheet: View {
    @Environment(SupplyService.self) private var supplyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "cart.fill"
    @State private var selectedColor = "007AFF"
    @State private var note = ""
    @State private var isSaving = false
    @State private var error: String?

    private let iconOptions = ["cart.fill","fork.knife","sparkles","leaf.fill","hammer.fill",
                               "lightbulb.fill","pawprint.fill","drop.fill","house.fill","bag.fill"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        previewCard
                        nameField
                        iconPicker
                        colorPicker
                        noteField
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var previewCard: some View {
        let color = SupplyList.colorOptions.first { $0.hex == selectedColor }.flatMap {
            Color(hex: $0.hex)
        } ?? .blue
        return GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [color.opacity(0.7), color.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 72)
                    Image(systemName: selectedIcon)
                        .font(AppFont.scaled(28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(AppSpacing.base)
                }
                Group {
                    if name.isEmpty { Text("List name") } else { Text(name) }
                }
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(name.isEmpty ? Color.primary.opacity(0.3) : .primary)
                .padding(.horizontal, AppSpacing.md).padding(.vertical, 10)
            }
        }
        .frame(width: 150)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(AppFont.label).foregroundStyle(.secondary)
            TextField("e.g. Supermarket, Garden, Bathroom…", text: $name)
                .font(AppFont.scaled(16)).foregroundStyle(.primary).tint(.accentColor)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE (OPTIONAL)")
                .font(AppFont.label).foregroundStyle(.secondary)
            TextField("Note about this list…", text: $note, axis: .vertical)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .lineLimit(2...4).padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon")
                .font(AppFont.label).foregroundStyle(.secondary)
            let color = Color(hex: selectedColor) ?? .blue
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button { selectedIcon = icon; HapticFeedback.selection() } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(selectedIcon == icon ? color.opacity(0.18) : Color.primary.opacity(AppOpacity.subtleFill))
                                .frame(height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .strokeBorder(selectedIcon == icon ? color : Color.clear, lineWidth: 2)
                                )
                            Image(systemName: icon)
                                .font(AppFont.scaled(22, weight: .medium))
                                .foregroundStyle(selectedIcon == icon ? color : Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(AppFont.label).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(SupplyList.colorOptions, id: \.hex) { opt in
                    let c = Color(hex: opt.hex) ?? .blue
                    Button { selectedColor = opt.hex; HapticFeedback.selection() } label: {
                        ZStack {
                            Circle().fill(c).frame(width: 32, height: 32)
                            if selectedColor == opt.hex {
                                Image(systemName: "checkmark")
                                    .font(AppFont.scaled(13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Custom hex color picker
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 32, height: 32)
                    if !SupplyList.colorOptions.map(\.hex).contains(selectedColor) {
                        Image(systemName: "checkmark")
                            .font(AppFont.scaled(13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: selectedColor) ?? .blue },
                        set: { newColor in
                            selectedColor = newColor.hexString()
                            HapticFeedback.selection()
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.015)
                    .scaleEffect(2.2)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                Spacer()
            }
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving { ProgressView().tint(.primary) }
                else {
                    Text("Create list")
                        .font(AppFont.headline)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.2)
                : Color.primary,
                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.4)
                : Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
    }

    private func save() {
        guard let propId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        isSaving = true
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewSupplyListPayload(propertyId: propId, ownerId: ownerId,
                                           name: n, icon: selectedIcon, color: selectedColor,
                                           note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                                           createdAt: now, updatedAt: now)
        Task {
            do {
                _ = try await supplyService.addList(payload)
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
            }
            isSaving = false
        }
    }
}

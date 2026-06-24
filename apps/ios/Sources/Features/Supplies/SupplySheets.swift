import SwiftUI

// MARK: - Add supply list sheet

struct AddSupplyListSheet: View {
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var propertyService: PropertyService
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
                    .padding(.horizontal, 20).padding(.top, 16)
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
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(14)
                }
                Group {
                    if name.isEmpty { Text("List name") } else { Text(name) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(name.isEmpty ? Color.primary.opacity(0.3) : .primary)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(width: 150)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("e.g. Supermarket, Garden, Bathroom…", text: $name)
                .font(.system(size: 16)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE (OPTIONAL)")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Note about this list…", text: $note, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .lineLimit(2...4).padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ICON")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            let color = Color(hex: selectedColor) ?? .blue
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button { selectedIcon = icon; HapticFeedback.selection() } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedIcon == icon ? color.opacity(0.18) : Color.primary.opacity(0.07))
                                .frame(height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(selectedIcon == icon ? color : Color.clear, lineWidth: 2)
                                )
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(selectedIcon == icon ? color : Color.primary.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLOR")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(SupplyList.colorOptions, id: \.hex) { opt in
                    let c = Color(hex: opt.hex) ?? .blue
                    Button { selectedColor = opt.hex; HapticFeedback.selection() } label: {
                        ZStack {
                            Circle().fill(c).frame(width: 32, height: 32)
                            if selectedColor == opt.hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
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
                            .font(.system(size: 13, weight: .bold))
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
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.2)
                : Color.primary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

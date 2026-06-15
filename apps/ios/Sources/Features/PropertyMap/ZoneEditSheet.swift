import SwiftUI

/// Edit a zone's metadata — name, colour, icon and layer. Native form,
/// Liquid Glass styling. Used both after drawing a new zone and to edit one.
struct ZoneEditSheet: View {
    let zone: PropertyZone
    var onSave: (PropertyZone) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var icon: String
    @State private var layer: PropertyLayer
    @State private var showDeleteConfirm = false

    init(zone: PropertyZone, onSave: @escaping (PropertyZone) -> Void, onDelete: @escaping () -> Void) {
        self.zone = zone
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: zone.name)
        _colorHex = State(initialValue: zone.colorHex)
        _icon = State(initialValue: zone.icon)
        _layer = State(initialValue: zone.layer)
    }

    private static let palette = [
        "#34C759", "#30D158", "#0A84FF", "#5AC8FA", "#64D2FF",
        "#FF9500", "#FFD60A", "#FF375F", "#FF6482", "#BF5AF2"
    ]
    private static let icons = [
        "square.dashed", "house.fill", "leaf.fill", "tree.fill", "car.fill",
        "sun.max.fill", "drop.fill", "bolt.fill", "camera.fill",
        "figure.pool.swim", "cube.box.fill", "building.2.fill"
    ]

    private var tint: Color { Color(hex: colorHex) ?? .blue }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    field("NAME") {
                        TextField("Zone name", text: $name)
                            .font(.system(size: 16))
                            .padding(14)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    field("COLOR") { paletteRow }
                    field("ICON") { iconGrid }
                    field("LAYER") { layerRow }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete zone", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Edit zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this zone?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete(); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var preview: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(tint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "Zone name" : name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(name.isEmpty ? Color.primary.opacity(0.4) : .primary)
                Text(layer.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private var paletteRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Self.palette, id: \.self) { hex in
                    let c = Color(hex: hex) ?? .blue
                    Circle()
                        .fill(c)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 3 : 0))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .scaleEffect(colorHex == hex ? 1.12 : 1.0)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25)) { colorHex = hex }
                            HapticFeedback.selection()
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(Self.icons, id: \.self) { sym in
                Image(systemName: sym)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(icon == sym ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(icon == sym ? tint : Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) { icon = sym }
                        HapticFeedback.selection()
                    }
            }
        }
    }

    private var layerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PropertyLayer.allCases, id: \.self) { l in
                    let active = layer == l
                    HStack(spacing: 5) {
                        Image(systemName: l.icon).font(.system(size: 11, weight: .semibold))
                        Text(l.displayName).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(active ? .white : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(active ? l.color : Color.primary.opacity(0.06), in: Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) { layer = l }
                        HapticFeedback.selection()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func save() {
        var updated = zone
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.colorHex = colorHex
        updated.icon = icon
        updated.layer = layer
        onSave(updated)
        dismiss()
    }
}

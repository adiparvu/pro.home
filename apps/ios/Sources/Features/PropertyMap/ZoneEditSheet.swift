import SwiftUI
import PhotosUI
import Supabase

/// Edit a zone's metadata — name, colour, icon, layer and cover photo.
struct ZoneEditSheet: View {
    let zone: PropertyZone
    var onSave: (PropertyZone) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var icon: String
    @State private var layer: PropertyLayer
    @State private var photoUrl: String?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pendingPhotoData: Data? = nil
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    init(zone: PropertyZone, onSave: @escaping (PropertyZone) -> Void, onDelete: @escaping () -> Void) {
        self.zone = zone
        self.onSave = onSave
        self.onDelete = onDelete
        _name     = State(initialValue: zone.name)
        _colorHex = State(initialValue: zone.colorHex)
        _icon     = State(initialValue: zone.icon)
        _layer    = State(initialValue: zone.layer)
        _photoUrl = State(initialValue: zone.photoUrl)
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
                            .padding(AppSpacing.base)
                            .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    field("PHOTO") { photoPickerSection }
                    field("COLOR") { paletteRow }
                    field("ICON") { iconGrid }
                    field("LAYER") { layerRow }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete zone", systemImage: "trash")
                            .font(AppFont.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.base)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, AppSpacing.xxs)
                }
                .padding(AppSpacing.xl)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Edit zone")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        pendingPhotoData = data
                        photoUrl = nil
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("Delete this zone?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete(); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    // MARK: - Photo picker

    @ViewBuilder
    private var photoPickerSection: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = pendingPhotoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if let urlStr = photoUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Color.primary.opacity(AppOpacity.hairline) }
                } else {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 26, weight: .light))
                            Text("Add cover photo")
                                .font(AppFont.caption)
                        }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: pendingPhotoData != nil || photoUrl != nil ? 110 : 90)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if pendingPhotoData != nil || photoUrl != nil {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(AppSpacing.sm)
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(tint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if name.isEmpty {
                        Text(LocalizedStringKey("Zone name"))
                    } else {
                        Text(LocalizedStringKey(name))
                    }
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(name.isEmpty ? Color.primary.opacity(0.4) : .primary)
                Text(LocalizedStringKey(layer.displayName))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppFont.captionStrong).foregroundStyle(.secondary)
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
                ZStack {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            center: .center
                        ))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(.white, lineWidth: Self.palette.contains(colorHex) ? 0 : 3))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: colorHex) ?? .blue },
                        set: { newColor in
                            withAnimation(.spring(response: 0.25)) { colorHex = newColor.hexString() }
                            HapticFeedback.selection()
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.015)
                    .scaleEffect(2.2)
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .scaleEffect(Self.palette.contains(colorHex) ? 1.0 : 1.12)
            }
            .padding(.vertical, AppSpacing.xxs)
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(Self.icons, id: \.self) { sym in
                Image(systemName: sym)
                    .font(AppFont.headline)
                    .foregroundStyle(icon == sym ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(icon == sym ? tint : Color.primary.opacity(AppOpacity.hairline),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
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
                        Image(systemName: l.icon).font(AppFont.label)
                        Text(LocalizedStringKey(l.displayName)).font(AppFont.captionEmphasis)
                    }
                    .foregroundStyle(active ? .white : .primary)
                    .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
                    .background(active ? l.color : Color.primary.opacity(AppOpacity.hairline), in: Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) { layer = l }
                        HapticFeedback.selection()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = zone
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.colorHex = colorHex
        updated.icon = icon
        updated.layer = layer
        updated.photoUrl = photoUrl

        if let data = pendingPhotoData {
            let path = "zones/\(zone.id.uuidString)/cover.jpg"
            let compressed = UIImage(data: data).flatMap { $0.jpegData(compressionQuality: 0.82) } ?? data
            do {
                try await supabase.storage
                    .from("photos")
                    .upload(path, data: compressed,
                            options: FileOptions(contentType: "image/jpeg", upsert: true))
                updated.photoUrl = try supabase.storage
                    .from("photos")
                    .getPublicURL(path: path)
                    .absoluteString
            } catch {
                #if DEBUG
                print("[ZoneEditSheet] photo upload error: \(error)")
                #endif
            }
        }

        onSave(updated)
        dismiss()
    }
}

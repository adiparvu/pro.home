import SwiftUI
import PhotosUI

// MARK: - "New color" sheet
//
// Rebuilt around a live hero swatch: the big card at the top IS the color
// being saved. Three paths feed the same hex state — the built-in RAL
// catalog, the system color picker (with its native eyedropper), and a raw
// hex field — so the hero always shows exactly what will be stored. Surface
// and finish are localized glass chips; the persisted values stay the exact
// strings the table has always stored (walls/ceiling/… and the PaintFinish
// raw values). An optional photo (the painted wall or the tin label)
// uploads through the same public `documents` bucket pattern as the photo
// journal.

struct AddPaintColorSheet: View {
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var roomName = ""
    @State private var useCustomRoom = false
    @State private var surface = "walls"
    @State private var colorName = ""
    @State private var brand = ""
    @State private var code = ""
    @State private var finish: PaintFinish = .eggshell
    @State private var hexColor = ""
    @State private var notes = ""

    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var showCatalog = false
    @State private var showEyedropper = false
    @State private var showHexInput = false
    @FocusState private var hexFieldFocused: Bool

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil

    /// Chip labels are localized; the persisted `value` strings are exactly
    /// what the `paint_colors.surface` column has always stored.
    private struct SurfaceOption: Identifiable {
        let value: String
        let key: String
        let icon: String
        var id: String { value }
    }

    private static let surfaceOptions: [SurfaceOption] = [
        SurfaceOption(value: "walls",   key: "paint_surface_walls",   icon: "square.split.bottomrightquarter"),
        SurfaceOption(value: "ceiling", key: "paint_surface_ceiling", icon: "light.recessed"),
        SurfaceOption(value: "trim",    key: "paint_surface_trim",    icon: "rectangle.bottomthird.inset.filled"),
        SurfaceOption(value: "door",    key: "paint_surface_door",    icon: "door.left.hand.closed"),
        SurfaceOption(value: "floor",   key: "paint_surface_floor",   icon: "square.bottomhalf.filled"),
        SurfaceOption(value: "other",   key: "paint_surface_other",   icon: "ellipsis.circle"),
    ]

    private var canSave: Bool {
        !colorName.trimmingCharacters(in: .whitespaces).isEmpty
            && !roomName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        FormScaffold(title: "paint_new_title",
                     canSave: canSave,
                     isSaving: isSaving,
                     error: $saveError,
                     onSave: { Task { await save() } }) {
            heroCard
            sourceRow
            if showHexInput { hexGroup }
            chipSection(title: "Surface") { surfaceChips }
            chipSection(title: "paint_finish_title") { finishChips }

            FormGroup(title: "Room") {
                if paintColorService.roomNames.isEmpty {
                    fieldRow("house.fill", "Room Name (e.g. Living Room)", $roomName)
                } else {
                    roomPickerOrCustom
                }
            }

            FormGroup(title: "Color Details") {
                fieldRow("paintbrush.fill", "Color Name (required)", $colorName)
                divider
                brandRow
                divider
                fieldRow("number.circle.fill", "Color Code", $code)
            }

            photoGroup

            FormGroup(title: "Notes") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .padding(.top, 2)
                    TextField("Additional notes…", text: $notes, axis: .vertical)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(3...6)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 13)
            }
        }
        .sheet(isPresented: $showCatalog) {
            PaintCatalogPicker { entry in
                colorName = entry.name
                code = entry.code
                hexColor = entry.hex
            }
        }
        .sheet(isPresented: $showEyedropper) {
            SystemColorPickerSheet(initial: currentColor.map { UIColor($0) }) { picked in
                hexColor = picked.paintHex
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    withAnimation(.snappy(duration: 0.25)) { photoImage = image }
                }
            }
        }
    }

    // MARK: - Hero swatch

    /// The stored hex normalized to 6 uppercase digits (no '#'), or nil.
    private var normalizedHex: String? {
        var raw = hexColor.trimmingCharacters(in: .whitespaces).uppercased()
        if raw.hasPrefix("#") { raw = String(raw.dropFirst()) }
        guard raw.count == 6, UInt64(raw, radix: 16) != nil else { return nil }
        return raw
    }

    private var currentColor: Color? {
        normalizedHex.flatMap { Color(hex: $0) }
    }

    /// A whisper of top-light on the swatch so the chosen finish reads on
    /// screen: strong for gloss, none for matte.
    private var sheenStrength: Double {
        switch finish {
        case .gloss:     return 0.26
        case .semiGloss: return 0.16
        case .satin:     return 0.09
        case .eggshell:  return 0.04
        case .matte:     return 0
        }
    }

    private var heroMeta: String {
        [brand, code]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var heroCard: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
        let color = currentColor
        // Rec. 601 luminance via Color.isLight: dark ink on light paint,
        // white on dark — the label never drowns in the swatch.
        let ink: Color = color?.readableText ?? .primary

        return ZStack(alignment: .bottomLeading) {
            shape.fill(color ?? Color.primary.opacity(AppOpacity.subtleFill))
            if color != nil, sheenStrength > 0 {
                LinearGradient(colors: [Color.white.opacity(sheenStrength), .clear],
                               startPoint: .topLeading, endPoint: .bottom)
                    .clipShape(shape)
            }
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if colorName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("paint_hero_placeholder")
                    } else {
                        Text(verbatim: colorName)
                    }
                }
                .font(AppFont.title2)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

                if !heroMeta.isEmpty {
                    Text(verbatim: heroMeta)
                        .font(AppFont.caption)
                        .foregroundStyle(ink.opacity(0.75))
                        .lineLimit(1)
                } else if colorName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("paint_hero_hint")
                        .font(AppFont.caption)
                        .foregroundStyle(ink.opacity(0.6))
                }
            }
            .padding(AppSpacing.lg)
        }
        .frame(height: 148)
        .overlay(alignment: .topTrailing) {
            if let hex = normalizedHex {
                Text(verbatim: "#\(hex)")
                    .font(AppFont.caption2)
                    .monospaced()
                    .foregroundStyle(ink.opacity(0.75))
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background((color?.isLight == true ? Color.black : Color.white).opacity(0.12),
                                in: Capsule())
                    .padding(AppSpacing.md)
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7))
        .animation(.smooth(duration: 0.3), value: hexColor)
        .animation(.smooth(duration: 0.3), value: finish)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Three paths to the same color

    private var sourceRow: some View {
        HStack(spacing: AppSpacing.sm) {
            sourceButton(icon: "swatchpalette.fill", title: "paint_source_catalog") {
                showCatalog = true
            }
            sourceButton(icon: "eyedropper.halffull", title: "paint_source_eyedropper") {
                showEyedropper = true
            }
            sourceButton(icon: "number", title: "paint_source_hex", isActive: showHexInput) {
                withAnimation(.snappy(duration: 0.3)) { showHexInput.toggle() }
            }
        }
    }

    private func sourceButton(icon: String,
                              title: LocalizedStringKey,
                              isActive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(AppFont.scaled(16, weight: .medium))
                Text(title)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(AppOpacity.emphasis))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassRoundedRect(AppRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isActive ? 0.5 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var hexGroup: some View {
        FormGroup {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(currentColor ?? Color.primary.opacity(0.2))
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.7)
                    )
                    .frame(width: 28)
                    .animation(.smooth(duration: 0.2), value: hexColor)
                Text(verbatim: "#")
                    .font(AppFont.body)
                    .foregroundStyle(Color.primary.opacity(0.4))
                TextField("Hex Color (e.g. F5E6D0)", text: $hexColor)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.asciiCapable)
                    .focused($hexFieldFocused)
                    .onAppear { hexFieldFocused = true }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Surface & finish chips

    private func chipSection<Content: View>(title: LocalizedStringKey,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .textCase(.uppercase)
                .padding(.leading, AppSpacing.xxs)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var surfaceChips: some View {
        ForEach(Self.surfaceOptions) { option in
            GlassFilterChip(label: String(localized: String.LocalizationValue(option.key)),
                            systemImage: option.icon,
                            isSelected: surface == option.value) {
                surface = option.value
            }
        }
    }

    private var finishChips: some View {
        ForEach(PaintFinish.allCases, id: \.self) { f in
            GlassFilterChip(label: f.displayName, isSelected: finish == f) {
                finish = f
            }
        }
    }

    // MARK: - Room

    private var roomPickerOrCustom: some View {
        VStack(spacing: 0) {
            if useCustomRoom {
                fieldRow("house.fill", "Room Name", $roomName)
                divider
                Button {
                    useCustomRoom = false
                    roomName = paintColorService.roomNames.first ?? ""
                } label: {
                    HStack {
                        Text("Choose existing room")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    Picker("Room", selection: $roomName) {
                        ForEach(paintColorService.roomNames, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                    .tint(.accentColor)
                    .font(AppFont.scaled(15))
                    .onAppear {
                        if roomName.isEmpty { roomName = paintColorService.roomNames.first ?? "" }
                    }
                    Spacer(minLength: 0)
                    Button {
                        useCustomRoom = true
                        roomName = ""
                    } label: {
                        Text("Add new room")
                            .font(AppFont.scaled(13, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Brand

    // Free text, with the brands sold in Romania and Belgium one tap away.
    private var brandRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField("Brand (e.g. Farrow & Ball)", text: $brand)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
            Menu {
                Section("paint_brands_ro") {
                    ForEach(PaintCatalog.brandsRomania, id: \.self) { b in
                        Button(b) { brand = b }
                    }
                }
                Section("paint_brands_be") {
                    ForEach(PaintCatalog.brandsBelgium, id: \.self) { b in
                        Button(b) { brand = b }
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("paint_brand_pick"))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    // MARK: - Photo (optional — the wall or the tin label)

    private var photoGroup: some View {
        FormGroup(title: "Photo") {
            if let image = photoImage {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    Text("paint_photo_hint")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.secondaryTextColor)
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            photoImage = nil
                            photoItem = nil
                        }
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.scaled(20))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove photo")
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 10)
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add photo")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(Color.accentColor)
                            Text("paint_photo_hint")
                                .font(AppFont.caption)
                                .foregroundStyle(Color.secondaryTextColor)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Shared row helpers

    private func fieldRow(_ icon: String, _ placeholder: LocalizedStringKey, _ binding: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    // MARK: - Save

    private func save() async {
        guard let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        isSaving = true
        defer { isSaving = false }

        // Optional photo first — same pattern as the photo journal: resized
        // JPEG into the public `documents` bucket, public URL into the row.
        var photoUrl: String? = nil
        if let image = photoImage, let data = image.uploadJPEG(quality: 0.8) {
            do {
                // Legacy fully-lowercased layout — path stays byte-identical.
                let path = "\(ownerId.uuidString.lowercased())/paint/\(propertyId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                photoUrl = try await SignedStorage.uploadPublicImage(data, path: path)
            } catch {
                saveError = String(format: String(localized: "Upload failed: %@"),
                                   error.localizedDescription)
                HapticFeedback.warning()
                return
            }
        }

        let payload = NewPaintColorPayload(
            propertyId: propertyId,
            ownerId: ownerId,
            roomName: roomName.trimmingCharacters(in: .whitespaces),
            surface: surface,
            colorName: colorName.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand,
            code: code.isEmpty ? nil : code,
            finish: finish.rawValue,
            hexColor: normalizedHex,
            notes: notes.isEmpty ? nil : notes,
            photoUrl: photoUrl,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        await paintColorService.add(payload)
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - System color picker (with the native eyedropper)

/// `UIColorPickerViewController` presented as a sheet — the system palette
/// whose grid, sliders and eyedropper all feed the same hex state as the
/// catalog and the manual field. Presented via a plain Button so the whole
/// chip is genuinely tappable (SwiftUI's `ColorPicker` well can't be opened
/// programmatically).
private struct SystemColorPickerSheet: UIViewControllerRepresentable {
    let initial: UIColor?
    let onPick: (UIColor) -> Void

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        if let initial { picker.selectedColor = initial }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIColorPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let onPick: (UIColor) -> Void
        init(onPick: @escaping (UIColor) -> Void) { self.onPick = onPick }

        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIColor, continuously: Bool) {
            onPick(color)
        }
    }
}

private extension UIColor {
    /// 6-digit uppercase hex (no '#'), clamped to sRGB — the format the
    /// paint form has always stored.
    var paintHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> Int { min(255, max(0, Int((v * 255).rounded()))) }
        return String(format: "%02X%02X%02X", channel(r), channel(g), channel(b))
    }
}

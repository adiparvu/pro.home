import SwiftUI

struct AddPaintColorSheet: View {
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var roomName = ""
    @State private var surface = "walls"
    @State private var colorName = ""
    @State private var brand = ""
    @State private var code = ""
    @State private var finish: PaintFinish = .eggshell
    @State private var hexColor = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var showCatalog = false

    private let surfaces = ["walls", "ceiling", "trim", "door", "floor", "other"]

    var body: some View {
        FormScaffold(title: "Add Paint Color",
                     canSave: !colorName.trimmingCharacters(in: .whitespaces).isEmpty && !roomName.trimmingCharacters(in: .whitespaces).isEmpty,
                     isSaving: isSaving,
                     error: .constant(nil),
                     onSave: { Task { await save() } }) {
            FormGroup(title: "Room") {
                if paintColorService.roomNames.isEmpty {
                    fieldRow("house.fill", "Room Name (e.g. Living Room)", $roomName)
                } else {
                    roomPickerOrCustom
                }
                divider
                surfacePicker
            }

            FormGroup(title: "Color Details") {
                catalogRow
                divider
                fieldRow("paintbrush.fill", "Color Name (required)", $colorName)
                divider
                brandRow
                divider
                fieldRow("number.circle.fill", "Color Code", $code)
                divider
                finishPickerRow
                divider
                hexColorRow
            }

            FormGroup(title: "Notes") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .padding(.top, 2)
                    TextField("Additional notes…", text: $notes, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(3...6)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 13)
            }
        }
    }

    @State private var useCustomRoom = false

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
                            .font(.system(size: 14))
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
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    Picker("Room", selection: $roomName) {
                        ForEach(paintColorService.roomNames, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                    .tint(.accentColor)
                    .font(.system(size: 15))
                    .onAppear {
                        if roomName.isEmpty { roomName = paintColorService.roomNames.first ?? "" }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 10)
                divider
                Button {
                    useCustomRoom = true
                    roomName = ""
                } label: {
                    HStack {
                        Text("Add new room")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var surfacePicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Picker("Surface", selection: $surface) {
                ForEach(surfaces, id: \.self) { s in
                    Text(LocalizedStringKey(s.capitalized)).tag(s)
                }
            }
            .tint(.accentColor)
            .font(.system(size: 15))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
    }

    private var finishPickerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Picker("Finish", selection: $finish) {
                ForEach(PaintFinish.allCases, id: \.self) { f in
                    Text(LocalizedStringKey(f.rawValue.capitalized)).tag(f)
                }
            }
            .tint(.accentColor)
            .font(.system(size: 15))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
    }

    // One tap fills name + code + hex from the built-in RAL catalog — the
    // code every Belgian and Romanian paint shop mixes against.
    private var catalogRow: some View {
        Button { showCatalog = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "swatchpalette.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                Text("paint_catalog_pick")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCatalog) {
            PaintCatalogPicker { entry in
                colorName = entry.name
                code = entry.code
                hexColor = entry.hex
            }
        }
    }

    // Free text, with the brands sold in Romania and Belgium one tap away.
    private var brandRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField("Brand (e.g. Farrow & Ball)", text: $brand)
                .font(.system(size: 15))
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

    private var hexColorRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hexPreviewColor)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.7)
                )
                .frame(width: 28)
                .animation(.smooth(duration: 0.2), value: hexColor)
            Text("#")
                .font(AppFont.body)
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Hex Color (e.g. F5E6D0)", text: $hexColor)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    private var hexPreviewColor: Color {
        let raw = hexColor.trimmingCharacters(in: .whitespaces)
        guard raw.count == 6, let hex = UInt64(raw, radix: 16) else { return Color.primary.opacity(0.2) }
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func fieldRow(_ icon: String, _ placeholder: LocalizedStringKey, _ binding: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(.system(size: 15))
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

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        let payload = NewPaintColorPayload(
            propertyId: propertyId,
            ownerId: ownerId,
            roomName: roomName.trimmingCharacters(in: .whitespaces),
            surface: surface,
            colorName: colorName.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand,
            code: code.isEmpty ? nil : code,
            finish: finish.rawValue,
            hexColor: hexColor.isEmpty ? nil : hexColor,
            notes: notes.isEmpty ? nil : notes,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        await paintColorService.add(payload)
        HapticFeedback.success()
        dismiss()
    }
}

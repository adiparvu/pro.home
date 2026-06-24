import SwiftUI

struct AddPaintColorSheet: View {
    @EnvironmentObject private var paintColorService: PaintColorService
    @EnvironmentObject private var propertyService: PropertyService
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

    private let surfaces = ["walls", "ceiling", "trim", "door", "floor", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        formSection("Room") {
                            if paintColorService.roomNames.isEmpty {
                                fieldRow("house.fill", "Room Name (e.g. Living Room)", $roomName)
                            } else {
                                roomPickerOrCustom
                            }
                            divider
                            surfacePicker
                        }

                        formSection("Color Details") {
                            fieldRow("paintbrush.fill", "Color Name (required)", $colorName)
                            divider
                            fieldRow("building.2.fill", "Brand (e.g. Farrow & Ball)", $brand)
                            divider
                            fieldRow("number.circle.fill", "Color Code", $code)
                            divider
                            finishPickerRow
                            divider
                            hexColorRow
                        }

                        formSection("Notes") {
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add Paint Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.accentColor)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .disabled(colorName.trimmingCharacters(in: .whitespaces).isEmpty || roomName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
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
                    .padding(.horizontal, 16)
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
                .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
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
                    Text(s.capitalized).tag(s)
                }
            }
            .tint(.accentColor)
            .font(.system(size: 15))
        }
        .padding(.horizontal, 16)
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
                    Text(f.rawValue.capitalized).tag(f)
                }
            }
            .tint(.accentColor)
            .font(.system(size: 15))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var hexColorRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(hexPreviewColor)
                .frame(width: 28)
            Text("#")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Hex Color (e.g. F5E6D0)", text: $hexColor)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, 16)
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

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func formSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
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

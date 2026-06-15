import SwiftUI

// MARK: - PaintColorsView

struct PaintColorsView: View {
    @EnvironmentObject private var paintColorService: PaintColorService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var showAdd = false
    @State private var selectedRoom: String? = nil
    @State private var colorToDelete: PaintColor? = nil

    private var filteredByRoom: [String: [PaintColor]] {
        if let room = selectedRoom {
            return [room: paintColorService.byRoom[room] ?? []]
        }
        return paintColorService.byRoom
    }

    private var sortedRooms: [String] {
        filteredByRoom.keys.sorted()
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if paintColorService.colors.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Paint Colors")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPaintColorSheet()
                .environmentObject(paintColorService)
                .environmentObject(propertyService)
        }
        .confirmationDialog(
            "Delete \"\(colorToDelete?.colorName ?? "")\"?",
            isPresented: Binding(get: { colorToDelete != nil }, set: { if !$0 { colorToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let c = colorToDelete {
                    Task { await paintColorService.delete(c) }
                    colorToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { colorToDelete = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .task {
            if let id = propertyService.primary?.id {
                await paintColorService.load(propertyId: id)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                roomFilterChips
                roomsContent
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await paintColorService.load(propertyId: id)
            }
        }
    }

    // MARK: - Room Filters

    private var roomFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: selectedRoom == nil) {
                    selectedRoom = nil
                }
                ForEach(paintColorService.roomNames, id: \.self) { room in
                    filterChip(label: room, isSelected: selectedRoom == room) {
                        selectedRoom = selectedRoom == room ? nil : room
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            HapticFeedback.impact(.light)
        }) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rooms Content

    private var roomsContent: some View {
        LazyVStack(spacing: 24, pinnedViews: []) {
            ForEach(sortedRooms, id: \.self) { room in
                roomSection(room: room, colors: filteredByRoom[room] ?? [])
            }
        }
    }

    private func roomSection(room: String, colors: [PaintColor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(room)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(colors.count) color\(colors.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(colors) { color in
                        PaintSwatch(paintColor: color)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                colorToDelete = color
                                HapticFeedback.warning()
                            }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("No colors saved yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Save paint colors for each room so you can easily reorder or touch up later.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add first color", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - PaintSwatch

private struct PaintSwatch: View {
    let paintColor: PaintColor

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paintColor.swatchColor)
                .frame(width: 70, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
                .shadow(color: paintColor.swatchColor.opacity(0.4), radius: 8, y: 3)

            Text(paintColor.colorName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 70)

            if !paintColor.code.isEmpty {
                Text(paintColor.code)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 70)
            }

            Text(paintColor.finishDisplay)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(width: 70)
        }
    }
}

// MARK: - AddPaintColorSheet

private struct AddPaintColorSheet: View {
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

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
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

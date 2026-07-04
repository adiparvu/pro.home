import SwiftUI

// MARK: - PaintColorsView

struct PaintColorsView: View {
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PropertyService.self) private var propertyService

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
                HStack(spacing: 2) {
                    if !paintColorService.colors.isEmpty {
                        SharePrintMenu(jobName: String(localized: "paint_print_job"),
                                       render: renderSpecSheet) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 34, height: 32)
                        }
                        .accessibilityLabel(String(localized: "paint_share_print"))
                    }
                    Button {
                        showAdd = true
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 32)
                    }
                    .accessibilityLabel("Add paint color")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPaintColorSheet()
                .environment(paintColorService)
                .environment(propertyService)
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
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
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
                    filterChip(label: LocalizedStringKey(room), isSelected: selectedRoom == room) {
                        selectedRoom = selectedRoom == room ? nil : room
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(label: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            HapticFeedback.impact(.light)
        }) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.primary.opacity(AppOpacity.emphasis))
                .padding(.horizontal, AppSpacing.base)
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
                    .font(AppFont.title3)
                    .foregroundStyle(.primary)
                Spacer()
                Text(colors.count == 1 ? "\(colors.count) color" : "\(colors.count) colors")
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
                .padding(.bottom, AppSpacing.xxs)
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
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Save paint colors for each room so you can easily reorder or touch up later.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add first color", systemImage: "plus")
                    .font(AppFont.subheadline)
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

    // MARK: - Share / Print

    /// Renders the full paint list (all rooms, ignoring the on-screen room filter)
    /// into a clean, light-mode document image suitable for AirPrint or sharing —
    /// the spec sheet you take to the paint store.
    private func renderSpecSheet() -> UIImage? {
        let rooms = paintColorService.byRoom.keys.sorted()
            .map { ($0, paintColorService.byRoom[$0] ?? []) }
            .filter { !$0.1.isEmpty }
        let sheet = PaintColorsSpecSheet(propertyName: propertyService.primary?.name ?? "",
                                         rooms: rooms)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3.0
        return renderer.uiImage
    }
}

// MARK: - Printable spec sheet
//
// A fixed-width, always-light document (independent of the app theme) so the
// print/share output is legible on paper. Rendered off-screen via ImageRenderer.

private struct PaintColorsSpecSheet: View {
    let propertyName: String
    let rooms: [(String, [PaintColor])]

    private let width: CGFloat = 560
    private let ink = Color(white: 0.08)
    private let faint = Color(white: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            ForEach(rooms, id: \.0) { room, colors in
                VStack(alignment: .leading, spacing: 10) {
                    Text(room)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ink)
                    ForEach(colors) { color in row(color) }
                }
            }
            footer
        }
        .padding(28)
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.62))
                Text(String(localized: "paint_print_title"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(ink)
            }
            if !propertyName.isEmpty {
                Text(propertyName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(faint)
            }
            Rectangle().fill(Color(white: 0.9)).frame(height: 1).padding(.top, 6)
        }
    }

    private func row(_ color: PaintColor) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.swatchColor)
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(white: 0.85), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(color.colorName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                HStack(spacing: 8) {
                    if let brand = color.brand, !brand.isEmpty { tag(brand) }
                    if let code = color.code, !code.isEmpty { tag(code) }
                    tag(color.finishDisplay)
                    if let hex = color.hexColor, !hex.isEmpty {
                        tag(hex.hasPrefix("#") ? hex.uppercased() : "#\(hex.uppercased())")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(faint)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("PRVIO")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color(white: 0.75))
            Spacer()
        }
        .padding(.top, 6)
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
                .font(AppFont.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 70)

            if let code = paintColor.code, !code.isEmpty {
                Text(code)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 70)
            }

            Text(LocalizedStringKey(paintColor.finishDisplay))
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .frame(width: 70)
        }
    }
}

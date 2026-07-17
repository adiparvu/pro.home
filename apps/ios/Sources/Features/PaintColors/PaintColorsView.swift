import SwiftUI

// MARK: - PaintColorsView

struct PaintColorsView: View {
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false
    @State private var selectedRoom: String? = nil
    @State private var colorToDelete: PaintColor? = nil
    @State private var photoPreview: PaintColor? = nil
    @State private var searchText = ""

    private var filteredByRoom: [String: [PaintColor]] {
        let base: [String: [PaintColor]]
        if let room = selectedRoom {
            base = [room: paintColorService.byRoom[room] ?? []]
        } else {
            base = paintColorService.byRoom
        }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.compactMapValues { colors in
            let matched = colors.filter(matchesSearch)
            return matched.isEmpty ? nil : matched
        }
    }

    private func matchesSearch(_ color: PaintColor) -> Bool {
        color.colorName.matchesSearch(searchText)
            || (color.brand ?? "").matchesSearch(searchText)
            || (color.code ?? "").matchesSearch(searchText)
            || color.roomName.matchesSearch(searchText)
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
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            // One circle for everything (IMG_8544/8546): the room
            // filter that used to sit as a permanent capsule plus
            // share/print, in a single aggregated popover.
            if !paintColorService.colors.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    filterButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add paint color")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPaintColorSheet()
                .environment(paintColorService)
                .environment(propertyService)
        }
        .sheet(item: $photoPreview) { color in
            PaintPhotoSheet(color: color)
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
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && sortedRooms.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                } else {
                    roomsContent
                }
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

    // MARK: - Filter + actions (one toolbar circle)

    private var filterButton: some View {
        GlassFilterButton(isActive: selectedRoom != nil, inToolbar: true) {
            GlassFilterSection(
                title: "Room",
                options: [GlassPickerOption<String?>(value: nil,
                                                     title: String(localized: "All"))]
                    + paintColorService.roomNames.map {
                        GlassPickerOption<String?>(value: $0,
                                                   title: String(localized: String.LocalizationValue($0)))
                    },
                selection: $selectedRoom)
            GlassFilterSectionDivider()
            GlassFilterActionRow(icon: "square.and.arrow.up",
                                 title: String(localized: "paint_share")) {
                if let image = renderSpecSheet() { SystemActions.share([image]) }
            }
            GlassFilterActionRow(icon: "printer",
                                 title: String(localized: "paint_print")) {
                if let image = renderSpecSheet() {
                    SystemActions.print(image: image,
                                        jobName: String(localized: "paint_colors_title"))
                }
            }
        }
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
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(colors) { color in
                        PaintSwatch(paintColor: color)
                            .onTapGesture {
                                // Only entries saved with a photo respond —
                                // the badge on the swatch is the affordance.
                                guard color.photoUrl?.isEmpty == false else { return }
                                photoPreview = color
                                HapticFeedback.impact(.light)
                            }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                colorToDelete = color
                                HapticFeedback.warning()
                            }
                            .accessibilityHint(color.photoUrl?.isEmpty == false
                                               ? Text("paint_photo_view") : Text(verbatim: ""))
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, AppSpacing.xxs)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "paintpalette.fill",
            title: "No colors saved yet",
            message: "Save paint colors for each room so you can easily reorder or touch up later.",
            actionLabel: "Add first color",
            action: { showAdd = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .font(AppFont.scaled(17, weight: .bold))
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
                    .font(AppFont.scaled(18))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.62))
                Text("paint_colors_title")
                    .font(AppFont.scaled(22, weight: .heavy))
                    .foregroundStyle(ink)
            }
            if !propertyName.isEmpty {
                Text(propertyName)
                    .font(AppFont.footnote)
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
                    .font(AppFont.subheadline)
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
            .font(AppFont.caption2)
            .foregroundStyle(faint)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("PRVIO")
                .font(AppFont.scaled(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color(white: 0.75))
            Spacer()
        }
        .padding(.top, 6)
    }
}

// MARK: - Photo preview
//
// The optional photo saved with a color (the painted wall or the tin
// label), shown full-size over the app background. Opened by tapping a
// swatch that carries the photo badge.

private struct PaintPhotoSheet: View {
    let color: PaintColor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if let url = color.photoUrl.flatMap({ URL(string: $0) }) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                                .padding(AppSpacing.lg)
                        case .failure:
                            Image(systemName: "photo")
                                .font(AppFont.scaled(34))
                                .foregroundStyle(Color.secondaryTextColor)
                        default:
                            ProgressView()
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: color.colorName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
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
                .overlay(alignment: .topTrailing) {
                    // Entries saved with a photo carry a badge — tap to view.
                    if paintColor.photoUrl?.isEmpty == false {
                        Image(systemName: "photo.fill")
                            .font(AppFont.scaled(8, weight: .semibold))
                            .foregroundStyle(paintColor.swatchColor.readableText.opacity(0.85))
                            .padding(5)
                    }
                }
                .shadow(color: paintColor.swatchColor.opacity(0.4), radius: 8, y: 3)

            Text(paintColor.colorName)
                .font(AppFont.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 70)

            if let code = paintColor.code, !code.isEmpty {
                Text(code)
                    .font(AppFont.scaled(10))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 70)
            }

            Text(LocalizedStringKey(paintColor.finishDisplay))
                .font(AppFont.scaled(10))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .frame(width: 70)
        }
    }
}

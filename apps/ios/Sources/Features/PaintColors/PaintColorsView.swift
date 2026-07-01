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
                .accessibilityLabel("Add paint color")
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

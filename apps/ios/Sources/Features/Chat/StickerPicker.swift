import SwiftUI

// MARK: - Sticker Picker (bottom sheet)

struct StickerPicker: View {
    @EnvironmentObject private var stickerService: StickerService
    let onSelect: (Sticker) -> Void

    @State private var selectedCategoryId: String = "recent"
    @Environment(\.dismiss) private var dismiss

    private struct SpecialTab {
        let id: String; let icon: String; let color: Color
    }
    private let specials: [SpecialTab] = [
        SpecialTab(id: "recent",    icon: "clock.fill",   color: .blue),
        SpecialTab(id: "favorites", icon: "heart.fill",   color: .pink),
        SpecialTab(id: "mostused",  icon: "flame.fill",   color: .orange),
    ]

    private var displayedStickers: [Sticker] {
        switch selectedCategoryId {
        case "recent":    return stickerService.recents
        case "favorites": return stickerService.favoriteStickers
        case "mostused":  return stickerService.mostUsed
        default:
            return StickerCatalog.categories.first { $0.id == selectedCategoryId }?.stickers ?? []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            header

            categoryTabs

            Divider()
                .background(Color.primary.opacity(0.06))

            if displayedStickers.isEmpty {
                emptyState
            } else {
                stickerGrid
            }
        }
        .background(appBackground.ignoresSafeArea())
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 10)
    }

    private var header: some View {
        HStack {
            Text("PRVIO Stickers")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(specials, id: \.id) { tab in
                    categoryButton(id: tab.id, icon: tab.icon, color: tab.color)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)

                ForEach(StickerCatalog.categories) { cat in
                    categoryButton(id: cat.id, icon: cat.icon, color: cat.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func categoryButton(id: String, icon: String, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategoryId = id }
            HapticFeedback.selection()
        } label: {
            let selected = selectedCategoryId == id
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? color.opacity(0.16) : Color.primary.opacity(0.06))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? color : Color.primary.opacity(0.4))
            }
            .frame(width: 38, height: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? color.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var stickerGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(displayedStickers) { sticker in
                    StickerCell(
                        sticker: sticker,
                        isFavorite: stickerService.isFavorite(sticker)
                    ) {
                        stickerService.use(sticker)
                        HapticFeedback.impact(.light)
                        onSelect(sticker)
                        dismiss()
                    } onFavorite: {
                        stickerService.toggleFavorite(sticker)
                        HapticFeedback.selection()
                    }
                }
            }
            .padding(12)
            .padding(.bottom, 24)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: selectedCategoryId)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: selectedCategoryId == "favorites" ? "heart.fill"
                  : selectedCategoryId == "recent" ? "clock.fill" : "face.smiling")
                .font(.system(size: 44))
                .foregroundStyle(Color.primary.opacity(0.14))
            Text(selectedCategoryId == "favorites" ? "No favorites yet"
                 : selectedCategoryId == "recent"   ? "No stickers used yet"
                 : selectedCategoryId == "mostused" ? "No stickers"
                 : "No stickers")
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(0.38))
            Spacer()
        }
        .frame(height: 200)
    }
}

// MARK: - Sticker Cell

struct StickerCell: View {
    let sticker: Sticker
    let isFavorite: Bool
    let onTap: () -> Void
    let onFavorite: () -> Void

    @State private var pressed = false

    var body: some View {
        Button { onTap() } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Text(sticker.emoji)
                        .font(.system(size: 44))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            Color.primary.opacity(pressed ? 0.10 : 0.04),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.pink)
                            .padding(4)
                    }
                }

                Text(sticker.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        .contextMenu {
            Button {
                onFavorite()
            } label: {
                Label(
                    isFavorite ? "Remove from favorites" : "Add to favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart.fill"
                )
            }
        }
    }
}

// MARK: - Sticker Bubble (rendered inside MessageBubble)

struct StickerBubble: View {
    let stickerId: String
    @State private var appeared = false

    private var sticker: Sticker? { StickerCatalog.sticker(id: stickerId) }

    var body: some View {
        VStack(spacing: 5) {
            Text(sticker?.emoji ?? "🏠")
                .font(.system(size: 84))
                .frame(width: 110, height: 100)
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0.0)
            if let label = sticker?.label {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .opacity(appeared ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }
}

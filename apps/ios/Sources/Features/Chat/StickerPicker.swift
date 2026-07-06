import SwiftUI

// MARK: - Sticker Picker (bottom sheet)

struct StickerPicker: View {
    @Environment(StickerService.self) private var stickerService
    let onSelect: (Sticker) -> Void
    /// When set, an "iOS" segment lets the user send Memoji/emoji-keyboard
    /// stickers as images.
    var onMemoji: ((UIImage) -> Void)? = nil

    @State private var selectedCategoryId: String = "recent"
    @State private var source: Source = .prvio
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable {
        case prvio, ios
    }

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

            if onMemoji != nil {
                sourcePicker
            }

            if source == .ios {
                memojiPane
            } else {
                categoryTabs

                Divider()
                    .background(Color.primary.opacity(AppOpacity.hairline))

                if displayedStickers.isEmpty {
                    emptyState
                } else {
                    stickerGrid
                }
            }
        }
        .background(appBackground.ignoresSafeArea())
    }

    private var sourcePicker: some View {
        HStack(spacing: 6) {
            ForEach(Source.allCases, id: \.self) { s in
                let selected = source == s
                Button {
                    HapticFeedback.selection()
                    withAnimation(.snappy(duration: 0.2)) { source = s }
                } label: {
                    Text(s == .prvio ? "PRVIO" : "iOS")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(selected ? .white : Color.primary.opacity(AppOpacity.mediumText))
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(selected ? AnyShapeStyle(Color.accentColor)
                                             : AnyShapeStyle(Color.primary.opacity(0.05)),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, AppSpacing.sm)
    }

    private var memojiPane: some View {
        VStack(spacing: 14) {
            Text("Open the emoji keyboard and tap a sticker — it sends as an image.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)

            MemojiStickerField { image in
                HapticFeedback.impact(.light)
                onMemoji?(image)
                dismiss()
            }
            .frame(height: 120)
            .padding(.horizontal, AppSpacing.md)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
            .padding(.horizontal, AppSpacing.lg)

            HStack(spacing: 6) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 13))
                Text("Memoji, animals, hands — everything from your sticker drawer works.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            .padding(.horizontal, AppSpacing.xl)

            Spacer(minLength: 20)
        }
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
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, AppSpacing.sm)
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
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm)
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
                    .fill(selected ? color.opacity(0.16) : Color.primary.opacity(AppOpacity.hairline))
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
            .padding(AppSpacing.md)
            .padding(.bottom, AppSpacing.xxl)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: selectedCategoryId)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: selectedCategoryId == "favorites" ? "heart.fill"
                  : selectedCategoryId == "recent" ? "clock.fill" : "face.smiling",
            title: selectedCategoryId == "favorites" ? "No favorites yet"
                   : selectedCategoryId == "recent" ? "No stickers used yet" : "No stickers"
        )
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
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        )

                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.pink)
                            .padding(AppSpacing.xxs)
                    }
                }

                Text(LocalizedStringKey(sticker.label))
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
                Text(LocalizedStringKey(label))
                    .font(AppFont.caption2)
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

import SwiftUI
import PhotosUI

// MARK: - Item photo gallery
//
// Additional photos for an inventory item, stored locally and separate from
// the cover/avatar photo: a horizontal strip with add (camera roll),
// fullscreen viewing and long-press delete.

struct InventoryPhotosCard: View {
    let itemId: UUID

    private struct GalleryPhoto: Identifiable {
        let url: URL
        var id: String { url.lastPathComponent }
    }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var refresh = 0
    @State private var fullscreen: GalleryPhoto? = nil
    @Namespace private var zoomNamespace

    var body: some View {
        let _ = refresh
        let photos = InventoryImageStore.galleryURLs(for: itemId).map(GalleryPhoto.init)

        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    if !photos.isEmpty {
                        Text("\(photos.count)")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(photos) { photo in
                            thumb(photo)
                        }
                        addTile
                    }
                }
            }
        }
        .fullScreenCover(item: $fullscreen) { photo in
            galleryViewer(photo)
                // Photos-style hero: the image grows out of its thumbnail
                // (iOS 18); older systems keep the plain cover.
                .zoomTransition(sourceID: photo.id, in: zoomNamespace)
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        InventoryImageStore.addGalleryImage(data, for: itemId)
                    }
                }
                pickerItems = []
                refresh += 1
                HapticFeedback.success()
            }
        }
    }

    @ViewBuilder
    private func thumb(_ photo: GalleryPhoto) -> some View {
        if let img = UIImage(contentsOfFile: photo.url.path) {
            Button { fullscreen = photo } label: {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .zoomTransitionSource(id: photo.id, in: zoomNamespace)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    InventoryImageStore.removeGalleryImage(at: photo.url)
                    refresh += 1
                    HapticFeedback.warning()
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
            }
        }
    }

    private var addTile: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.primary.opacity(AppOpacity.subtleFill))
                .frame(width: 84, height: 84)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.3),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        }
        .accessibilityLabel("Add photos")
    }

    private func galleryViewer(_ initial: GalleryPhoto) -> some View {
        GalleryPager(
            photos: InventoryImageStore.galleryURLs(for: itemId).map(GalleryPhoto.init),
            initialId: initial.id
        ) { fullscreen = nil }
    }

    // MARK: Fullscreen pager

    private struct GalleryPager: View {
        let photos: [GalleryPhoto]
        let onClose: () -> Void
        @State private var selection: String

        init(photos: [GalleryPhoto], initialId: String, onClose: @escaping () -> Void) {
            self.photos = photos
            self.onClose = onClose
            _selection = State(initialValue: initialId)
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                TabView(selection: $selection) {
                    ForEach(photos) { photo in
                        Group {
                            if let img = UIImage(contentsOfFile: photo.url.path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                        .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(AppFont.headline)
                        .foregroundStyle(.white)
                        .padding(AppSpacing.md)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(AppSpacing.xl)
                .accessibilityLabel("Close")
            }
        }
    }
}

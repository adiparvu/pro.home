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
                        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await InventoryImageStore.addGalleryImage(data, for: itemId)
                    }
                }
                pickerItems = []
                refresh += 1
                HapticFeedback.success()
            }
        }
    }

    private func thumb(_ photo: GalleryPhoto) -> some View {
        Button { fullscreen = photo } label: {
            GalleryAsyncImage(url: photo.url, contentMode: .fill)
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

    private var addTile: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.primary.opacity(AppOpacity.subtleFill))
                .frame(width: 84, height: 84)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(20, weight: .medium))
                        Text("Add")
                            .font(AppFont.caption2)
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

    // MARK: Async gallery image
    //
    // The strip and the pager used to hit `UIImage(contentsOfFile:)` — a
    // synchronous main-thread JPEG decode — on every body pass. Decodes now
    // happen once, off the main actor, and are memoized per file path.

    private static let decodeCache = NSCache<NSString, UIImage>()

    private struct GalleryAsyncImage: View {
        let url: URL
        let contentMode: ContentMode
        @State private var loaded: UIImage?

        private var cached: UIImage? {
            InventoryPhotosCard.decodeCache.object(forKey: url.path as NSString)
        }

        var body: some View {
            Group {
                if let img = loaded ?? cached {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Color.primary.opacity(AppOpacity.subtleFill)
                }
            }
            .task(id: url) {
                guard cached == nil else { return }
                loaded = nil
                let path = url.path
                let img = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: path)
                }.value
                if let img {
                    InventoryPhotosCard.decodeCache.setObject(img, forKey: path as NSString)
                    loaded = img
                }
            }
        }
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
                        GalleryAsyncImage(url: photo.url, contentMode: .fit)
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

import SwiftUI
import Supabase
import ImageIO
import UIKit

// MARK: - Signed access to the `documents` bucket
//
// Family documents, avatars and property photos live in the `documents`
// bucket, and the app has historically persisted *public* object URLs in
// database rows. Public URLs bypass RLS: anyone holding the link can fetch
// a passport scan. The exit path is staged so nothing breaks for clients
// already in the field:
//
//   1. (this change) iOS stops trusting public URLs for display and asks
//      Storage for a short-lived signed URL instead — signing works while
//      the bucket is still public, so this is a no-op visually.
//   2. The web app does the same.
//   3. Once both clients are deployed, the bucket is flipped private and
//      the public endpoint stops serving family documents. Old clients
//      keep working right up until that flip.
//
// Rows keep storing the canonical public-form URL (the stable identifier
// old builds and the web understand); only *display* goes through signing.

enum SignedStorage {
    private static let bucketMarker = "/storage/v1/object/public/documents/"
    /// Signed URLs live 1h; refresh after 50min so a URL never expires
    /// while a view is still holding it.
    private static let signedTTL: TimeInterval = 3600
    private static let refreshAfter: TimeInterval = 50 * 60

    private struct CacheEntry {
        let url: URL
        let created: Date
    }
    @MainActor private static var cache: [String: CacheEntry] = [:]

    /// Extracts the object path when the string is a public URL into the
    /// `documents` bucket; nil for anything else (external images, other
    /// buckets, already-signed URLs).
    static func documentsPath(from urlString: String) -> String? {
        guard let range = urlString.range(of: bucketMarker) else { return nil }
        let path = String(urlString[range.upperBound...])
        guard !path.isEmpty else { return nil }
        // Object paths are stored percent-encoded in the URL.
        return path.removingPercentEncoding ?? path
    }

    /// Resolves any stored image reference for display. Public `documents`
    /// URLs come back signed (and cached); everything else passes through
    /// untouched. On signing failure it falls back to the original URL so
    /// the UI degrades to today's behavior instead of a broken image.
    @MainActor
    static func resolve(_ urlString: String?) async -> URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        guard let path = documentsPath(from: urlString) else {
            return URL(string: urlString)
        }
        if let hit = cache[path], Date().timeIntervalSince(hit.created) < refreshAfter {
            return hit.url
        }
        do {
            let signed = try await supabase.storage.from("documents")
                .createSignedURL(path: path, expiresIn: Int(signedTTL))
            cache[path] = CacheEntry(url: signed, created: Date())
            return signed
        } catch {
            return URL(string: urlString)
        }
    }

    @MainActor
    static func clearCache() {
        cache.removeAll()
    }

    // MARK: - Uploads into the public `documents` bucket

    /// The single upload path for property imagery (element photos, note
    /// photos, paint swatches, …): writes the object under the canonical
    /// "{auth-uid}/{folder}/{uuid}.{ext}" layout and returns the public-form
    /// URL that database rows persist (display goes back through `resolve`,
    /// which signs it).
    static func uploadPublicImage(_ data: Data, folder: String,
                                  ext: String = "jpg") async throws -> String {
        let uid = supabase.auth.currentSession?.user.id.uuidString ?? "anon"
        return try await uploadPublicImage(
            data, path: "\(uid)/\(folder)/\(UUID().uuidString).\(ext)")
    }

    /// Path-explicit variant for objects that predate the
    /// "{auth-uid}/{folder}/{uuid}" convention (zone covers at a fixed,
    /// upserted path; lowercased legacy layouts) — same bucket, same
    /// public-URL contract, caller-controlled object path.
    static func uploadPublicImage(_ data: Data, path: String,
                                  contentType: String = "image/jpeg",
                                  upsert: Bool = false) async throws -> String {
        try await supabase.storage.from("documents")
            .upload(path, data: data,
                    options: FileOptions(contentType: contentType, upsert: upsert))
        return try supabase.storage.from("documents")
            .getPublicURL(path: path).absoluteString
    }
}

// MARK: - Decoded-image cache

/// Fully-decoded (and, when requested, downsampled) `UIImage`s, keyed by the
/// canonical *source* string plus the requested pixel size — signed URLs
/// rotate every 50 minutes, so the resolved URL would defeat the cache.
/// Costs are the decoded bitmap size; the cache stays under ~60 MB.
private enum StorageImageCache {
    static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    /// Cache key: the source with the target pixel size appended as a
    /// fragment, so the same object at different sizes never collides.
    static func key(source: String, maxPixel: CGFloat) -> NSURL {
        NSURL(string: "\(source)#maxpx=\(Int(maxPixel))")
            ?? NSURL(fileURLWithPath: "\(source.hashValue)-\(Int(maxPixel))")
    }

    static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}

// MARK: - StorageImage — AsyncImage over signed storage

/// Drop-in replacement for `AsyncImage` wherever the source may be a
/// `documents`-bucket object. Resolves the signed URL first, then renders
/// through `AsyncImage`, so call sites keep their phase-based styling.
///
/// Pass `targetSize` (the view's larger dimension, in points) to opt into the
/// fast path: the bytes are fetched through `URLSession`, downsampled with
/// `CGImageSourceCreateThumbnailAtIndex` off the main actor, and the decoded
/// result is kept in an app-wide `NSCache` — so a thumbnail grid never holds
/// full-size decodes and never re-decodes on scroll. Without `targetSize` the
/// behavior is exactly the previous `AsyncImage` pipeline.
struct StorageImage<Content: View>: View {
    let source: String?
    /// Larger display dimension in points; nil = legacy AsyncImage path.
    var targetSize: CGFloat? = nil
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var resolved: URL?
    @State private var phase: AsyncImagePhase = .empty

    init(source: String?, targetSize: CGFloat? = nil,
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.source = source
        self.targetSize = targetSize
        self.content = content
    }

    init(url: URL?, targetSize: CGFloat? = nil,
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.source = url?.absoluteString
        self.targetSize = targetSize
        self.content = content
    }

    var body: some View {
        if let targetSize {
            content(currentPhase(maxPixel: targetSize * displayScale))
                .task(id: source) {
                    await loadDownsampled(maxPixel: targetSize * displayScale)
                }
        } else {
            AsyncImage(url: resolved) { phase in
                content(phase)
            }
            .task(id: source) {
                resolved = await SignedStorage.resolve(source)
            }
        }
    }

    /// A synchronous cache hit renders on the very first body pass — no
    /// placeholder flash when a cell scrolls back on screen.
    private func currentPhase(maxPixel: CGFloat) -> AsyncImagePhase {
        if case .empty = phase, let source,
           let hit = StorageImageCache.images.object(
               forKey: StorageImageCache.key(source: source, maxPixel: maxPixel)) {
            return .success(Image(uiImage: hit))
        }
        return phase
    }

    private func loadDownsampled(maxPixel: CGFloat) async {
        guard let source, !source.isEmpty else {
            phase = .empty
            return
        }
        let key = StorageImageCache.key(source: source, maxPixel: maxPixel)
        if let hit = StorageImageCache.images.object(forKey: key) {
            phase = .success(Image(uiImage: hit))
            return
        }
        // Cold load (or the reused view got a new source): show the
        // placeholder while fetching, mirroring AsyncImage's semantics.
        phase = .empty
        guard let url = await SignedStorage.resolve(source) else {
            phase = .failure(URLError(.badURL))
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            // Decode + downsample off the main actor; only publish comes back.
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                ]
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
                else { return nil }
                return UIImage(cgImage: cg)
            }.value
            guard !Task.isCancelled else { return }
            if let image {
                StorageImageCache.images.setObject(image, forKey: key,
                                                   cost: StorageImageCache.cost(of: image))
                phase = .success(Image(uiImage: image))
            } else {
                phase = .failure(URLError(.cannotDecodeContentData))
            }
        } catch is CancellationError {
            // View went away mid-flight — leave the phase alone.
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}

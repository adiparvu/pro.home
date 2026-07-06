import SwiftUI
import Supabase

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
}

// MARK: - StorageImage — AsyncImage over signed storage

/// Drop-in replacement for `AsyncImage` wherever the source may be a
/// `documents`-bucket object. Resolves the signed URL first, then renders
/// through `AsyncImage`, so call sites keep their phase-based styling.
struct StorageImage<Content: View>: View {
    let source: String?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var resolved: URL?

    init(source: String?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.source = source
        self.content = content
    }

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.source = url?.absoluteString
        self.content = content
    }

    var body: some View {
        AsyncImage(url: resolved) { phase in
            content(phase)
        }
        .task(id: source) {
            resolved = await SignedStorage.resolve(source)
        }
    }
}

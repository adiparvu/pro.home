import Foundation
import Supabase

// MARK: - Private chat media (Phase 4 / S4) — signed-URL access
//
// Chat attachments now upload to the private `chat-media` bucket (migration 085)
// and are persisted as a storage PATH rather than a permanent public URL. At
// display time resolve(_:) turns the path into a short-lived signed URL. Legacy
// values that are already full public URLs pass through unchanged, so existing
// media keeps working while new media is no longer permanently public.

enum ChatMedia {
    static let bucket = "chat-media"

    /// Uploads data to the private bucket under `{propertyId}/{subdir}/{uuid}.{ext}`
    /// and returns the stored path (nil on failure). Persist this in attachment_url.
    static func upload(_ data: Data, propertyId: UUID, subdir: String,
                       ext: String, contentType: String) async -> String? {
        let path = "\(propertyId.uuidString)/\(subdir)/\(UUID().uuidString).\(ext)"
        do {
            try await supabase.storage.from(bucket)
                .upload(path, data: data, options: FileOptions(contentType: contentType, upsert: false))
            return path
        } catch {
            return nil
        }
    }

    /// Resolves a stored attachment value to a displayable URL. Legacy public
    /// URLs (http…) pass through; chat-media paths get a signed URL, cached so
    /// repeated resolves for the same path (re-renders, LazyVStack recycling
    /// scrolling a bubble on/off screen) return the SAME URL instead of minting a
    /// new one each time. That also keeps AsyncImage's own cache effective —
    /// every fresh signature would otherwise be a different URL string, forcing
    /// a re-download on every scroll.
    static func resolve(_ stored: String) async -> URL? {
        if stored.hasPrefix("http") { return URL(string: stored) }
        if let cached = await SignedURLCache.shared.get(stored) { return cached }
        guard let url = try? await supabase.storage.from(bucket)
            .createSignedURL(path: stored, expiresIn: 3600) else { return nil }
        await SignedURLCache.shared.set(stored, url: url)
        return url
    }
}

/// In-memory cache of resolved signed URLs, keyed by storage path. Entries are
/// kept for less than the 1-hour signing window so a URL is never served after
/// it could have expired.
private actor SignedURLCache {
    static let shared = SignedURLCache()
    private var entries: [String: (url: URL, expiresAt: Date)] = [:]
    private let ttl: TimeInterval = 50 * 60

    func get(_ key: String) -> URL? {
        guard let e = entries[key], e.expiresAt > Date() else { return nil }
        return e.url
    }

    func set(_ key: String, url: URL) {
        entries[key] = (url, Date().addingTimeInterval(ttl))
    }
}

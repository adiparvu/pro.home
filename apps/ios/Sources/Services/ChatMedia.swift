import Foundation
import Supabase

// MARK: - Private chat media (Phase 4 / S4) — signed-URL access
//
// Chat attachments now upload to the private `chat-media` bucket (migration 085)
// and are persisted as a storage PATH rather than a permanent public URL. At
// display time resolve(_:) turns the path into a short-lived signed URL. Legacy
// values that are already full public URLs pass through unchanged, so existing
// media keeps working while new media is no longer permanently public.

/// What a DM `body` actually carries. DMs have no attachment columns — media
/// is a bare storage path (`{property}/dm…/{uuid}.ext`, private bucket) or, in
/// legacy rows, a full public URL.
enum DMBodyKind { case text, image, audio, video }

enum ChatMedia {
    static let bucket = "chat-media"

    /// Single source of truth for classifying a DM body. The old checks were
    /// copy-pasted across six views and required "supabase" in the value, so a
    /// private-bucket PATH (which contains no host at all) fell through and
    /// rendered as raw text.
    static func dmBodyKind(_ body: String) -> DMBodyKind {
        let lower = body.lowercased()
        // Prose contains whitespace; a path or URL never does. This also stops
        // a sentence that merely ends in ".jpg" from rendering as media.
        guard !lower.contains(" "), !lower.contains("\n") else { return .text }
        if lower.contains("/dm-audio/") || lower.hasSuffix(".m4a") { return .audio }
        if lower.contains("/dm-video/") || lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") { return .video }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".png") || lower.hasSuffix(".webp") {
            // Storage path (new), Live Photo still (dm-live), legacy
            // dm-images path, or legacy public URL. Live stills ride the
            // image pipeline everywhere; `isDMLive` adds badge + playback.
            if lower.contains("/dm/") || lower.contains("/dm-live/")
                || lower.contains("/dm-images/") || lower.hasPrefix("http") { return .image }
        }
        return .text
    }

    /// True when a DM image body is a Live Photo still (its motion pair
    /// lives beside it under the same stem — see `liveVideoPath(for:)`).
    static func isDMLive(_ body: String) -> Bool {
        body.lowercased().contains("/dm-live/")
    }

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

    /// Uploads a Live Photo pair under the SAME uuid stem —
    /// `{propertyId}/{subdir}/{uuid}.jpg` + `{uuid}.mov` — and returns the
    /// STILL's path (the attachment_url for type "live"). The motion path is
    /// always derived via `liveVideoPath(for:)`, so no schema change rides.
    static func uploadLivePair(still: Data, video: Data, propertyId: UUID,
                               subdir: String) async -> String? {
        let stem = "\(propertyId.uuidString)/\(subdir)/\(UUID().uuidString)"
        do {
            try await supabase.storage.from(bucket)
                .upload(stem + ".jpg", data: still,
                        options: FileOptions(contentType: "image/jpeg", upsert: false))
            try await supabase.storage.from(bucket)
                .upload(stem + ".mov", data: video,
                        options: FileOptions(contentType: "video/quicktime", upsert: false))
            return stem + ".jpg"
        } catch {
            return nil
        }
    }

    /// The paired-motion path for a "live" attachment's still path.
    static func liveVideoPath(for stillPath: String) -> String {
        (stillPath as NSString).deletingPathExtension + ".mov"
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

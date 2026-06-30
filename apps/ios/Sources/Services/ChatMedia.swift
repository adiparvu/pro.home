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
    /// URLs (http…) pass through; chat-media paths get a fresh 1-hour signed URL.
    static func resolve(_ stored: String) async -> URL? {
        if stored.hasPrefix("http") { return URL(string: stored) }
        return try? await supabase.storage.from(bucket).createSignedURL(path: stored, expiresIn: 3600)
    }
}

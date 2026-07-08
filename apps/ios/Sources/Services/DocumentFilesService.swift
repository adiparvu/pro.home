import Foundation
import Observation
import Supabase
import UIKit

// MARK: - Document files (Document Intelligence D2)
//
// The multi-file layer for one document: photos, PDFs, scans and Files-app
// imports attach as additional files alongside the primary one. Storage reuses
// the private `documents` bucket under {userId}/{documentId}/{uuid}-{name}, so
// the existing owner-based delete policy applies; reads resolve short-lived
// signed URLs (the same pattern chat and plant media use).

@MainActor
@Observable
final class DocumentFilesService {
    private(set) var files: [DocumentFile] = []
    var isLoading = false
    var isUploading = false

    private static let bucket = "documents"

    func load(documentId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        files = (try? await supabase.from("document_files")
            .select()
            .eq("document_id", value: documentId.uuidString)
            .order("created_at", ascending: false)
            .execute().value) ?? []
    }

    /// Uploads one attachment and records it. Returns false on failure.
    @discardableResult
    func add(documentId: UUID, data: Data, name: String, mimeType: String,
             kind: String, pageCount: Int? = nil) async -> Bool {
        guard let userId = supabase.auth.currentSession?.user.id else { return false }
        isUploading = true
        defer { isUploading = false }
        let safeName = name.isEmpty ? "file" : name
        let path = "\(userId.uuidString)/\(documentId.uuidString)/\(UUID().uuidString)-\(safeName)"
        do {
            try await supabase.storage.from(Self.bucket)
                .upload(path, data: data, options: FileOptions(contentType: mimeType, upsert: false))
            struct Payload: Encodable {
                let document_id: String, url: String, name: String, kind: String
                let mime_type: String, size: Int64, page_count: Int?
            }
            let row: DocumentFile = try await supabase.from("document_files")
                .insert(Payload(document_id: documentId.uuidString, url: path, name: safeName,
                                kind: kind, mime_type: mimeType, size: Int64(data.count),
                                page_count: pageCount))
                .select().single().execute().value
            files.insert(row, at: 0)
            // History (D5): a file was attached. Best-effort.
            await DocumentEventsService.log(documentId: documentId, kind: .fileAdded,
                                            details: ["name": safeName])
            return true
        } catch {
            return false
        }
    }

    func delete(_ file: DocumentFile) async {
        do {
            try? await supabase.storage.from(Self.bucket).remove(paths: [file.url])
            try await supabase.from("document_files").delete()
                .eq("id", value: file.id.uuidString).execute()
            files.removeAll { $0.id == file.id }
            // History (D5): a file was removed. Best-effort.
            await DocumentEventsService.log(documentId: file.documentId, kind: .fileRemoved,
                                            details: ["name": file.name])
        } catch { /* best-effort */ }
    }

    /// Resolves a stored path to a displayable signed URL (legacy full URLs
    /// pass through), cached under the signing window.
    static func resolve(_ stored: String) async -> URL? {
        if stored.hasPrefix("http") { return URL(string: stored) }
        if let cached = await DocumentURLCache.shared.get(stored) { return cached }
        guard let url = try? await supabase.storage.from(bucket)
            .createSignedURL(path: stored, expiresIn: 3600) else { return nil }
        await DocumentURLCache.shared.set(stored, url: url)
        return url
    }

    /// Downloads the file's bytes to a temp URL for QuickLook/share.
    static func localCopy(of file: DocumentFile) async -> URL? {
        guard let remote = await resolve(file.url), let data = try? Data(contentsOf: remote) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        try? data.write(to: tmp)
        return tmp
    }
}

private actor DocumentURLCache {
    static let shared = DocumentURLCache()
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

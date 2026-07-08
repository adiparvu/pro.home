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
    /// Current (non-superseded) attachments — the top-level rows the section
    /// shows, newest first. History lives in `allFiles` and is exposed per
    /// group on demand via `priorVersions(of:)`.
    private(set) var files: [DocumentFile] = []
    /// Every row for the document, current and superseded. One fetch backs both
    /// the visible list and history, so opening a version costs no round-trip.
    private var allFiles: [DocumentFile] = []
    var isLoading = false
    var isUploading = false

    private static let bucket = "documents"

    func load(documentId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        let rows: [DocumentFile] = (try? await supabase.from("document_files")
            .select()
            .eq("document_id", value: documentId.uuidString)
            .order("created_at", ascending: false)
            .execute().value) ?? []
        allFiles = rows
        files = rows.filter { !$0.isSuperseded }
    }

    /// Older versions of a file's slot, newest superseded first. Empty when the
    /// file has no history — the disclosure only appears when this is non-empty.
    func priorVersions(of file: DocumentFile) -> [DocumentFile] {
        allFiles
            .filter { $0.id != file.id && $0.groupId == file.groupId }
            .sorted { $0.version > $1.version }
    }

    /// True when the file has at least one earlier version to reveal.
    func hasHistory(_ file: DocumentFile) -> Bool {
        allFiles.contains { $0.id != file.id && $0.groupId == file.groupId }
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
            allFiles.insert(row, at: 0)
            // History (D5): a file was attached. Best-effort.
            await DocumentEventsService.log(documentId: documentId, kind: .fileAdded,
                                            details: ["name": safeName])
            return true
        } catch {
            return false
        }
    }

    /// Replaces `old` with a newly uploaded file (D5): the new file lands as a
    /// fresh row in the same version group with `version + 1`, and `old` is
    /// marked superseded (kept, never deleted) so its history stays openable.
    /// Returns false on failure; the old file is left untouched if anything
    /// along the way fails, so a partial replace can never lose the original.
    @discardableResult
    func replace(_ old: DocumentFile, with data: Data, name: String,
                 mimeType: String, kind: String, pageCount: Int? = nil) async -> Bool {
        guard let userId = supabase.auth.currentSession?.user.id else { return false }
        isUploading = true
        defer { isUploading = false }
        let safeName = name.isEmpty ? "file" : name
        let path = "\(userId.uuidString)/\(old.documentId.uuidString)/\(UUID().uuidString)-\(safeName)"
        do {
            try await supabase.storage.from(Self.bucket)
                .upload(path, data: data, options: FileOptions(contentType: mimeType, upsert: false))

            struct Payload: Encodable {
                let document_id: String, url: String, name: String, kind: String
                let mime_type: String, size: Int64, page_count: Int?
                let version: Int, version_group: String
            }
            let newRow: DocumentFile = try await supabase.from("document_files")
                .insert(Payload(document_id: old.documentId.uuidString, url: path, name: safeName,
                                kind: kind, mime_type: mimeType, size: Int64(data.count),
                                page_count: pageCount, version: old.version + 1,
                                version_group: old.groupId.uuidString))
                .select().single().execute().value

            // Mark the old row superseded by the new one. Timestamp is sent as
            // an ISO string; timestamptz parses it.
            struct Supersede: Encodable { let superseded_at: String; let superseded_by: String }
            let stamp = ISO8601DateFormatter().string(from: Date())
            try await supabase.from("document_files")
                .update(Supersede(superseded_at: stamp, superseded_by: newRow.id.uuidString))
                .eq("id", value: old.id.uuidString)
                .execute()

            // Reflect locally: swap the old head for the new one, keep the old
            // in history with its superseded markers set.
            if let idx = allFiles.firstIndex(where: { $0.id == old.id }) {
                allFiles[idx].supersededAt = stamp
                allFiles[idx].supersededBy = newRow.id
            }
            allFiles.insert(newRow, at: 0)
            files = allFiles.filter { !$0.isSuperseded }

            await DocumentEventsService.log(documentId: old.documentId, kind: .replaced,
                                            details: ["name": safeName, "version": String(newRow.version)])
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
            allFiles.removeAll { $0.id == file.id }
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

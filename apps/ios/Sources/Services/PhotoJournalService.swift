import Foundation
import Observation
import UIKit
import Supabase

@MainActor
@Observable
final class PhotoJournalService {
    var entries: [PhotoJournalEntry] = []
    var isLoading = false
    var error: String?

    var entriesByZone: [UUID?: [PhotoJournalEntry]] {
        Dictionary(grouping: entries, by: { $0.zoneId })
    }

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if entries.isEmpty, let cached = ServiceCache.load([PhotoJournalEntry].self, entity: "journal", propertyId: propertyId) {
            entries = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await PropertyRepo.fetch(table: "photo_journal_entries", propertyId: propertyId,
                                                   scope: .strict, order: "taken_at", limit: 600)
            ServiceCache.save(entries, entity: "journal", propertyId: propertyId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func add(_ payload: NewPhotoJournalPayload) async throws -> PhotoJournalEntry {
        let inserted: PhotoJournalEntry = try await supabase
            .from("photo_journal_entries")
            .insert(payload)
            .select().single().execute().value
        entries.insert(inserted, at: 0)
        entries.sort { ($0.takenDate ?? .distantPast) > ($1.takenDate ?? .distantPast) }
        return inserted
    }

    /// Uploads one image to storage and records it as a journal entry —
    /// the property page's gallery add-path (photos separate from the cover).
    @discardableResult
    func upload(imageData: Data, propertyId: UUID, title: String? = nil) async throws -> PhotoJournalEntry? {
        guard let ownerId = supabase.auth.currentSession?.user.id else { return nil }
        let compressed = UIImage(data: imageData)
            .flatMap { $0.uploadJPEG(quality: 0.8) } ?? imageData
        let path = "\(ownerId.uuidString.lowercased())/journal/\(propertyId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await supabase.storage
            .from("documents")
            .upload(path, data: compressed,
                    options: FileOptions(contentType: "image/jpeg", upsert: false))
        let publicURL = try supabase.storage.from("documents").getPublicURL(path: path)
        let now = ISO8601DateFormatter().string(from: Date())
        return try await add(NewPhotoJournalPayload(
            propertyId: propertyId,
            ownerId: ownerId,
            zoneId: nil,
            title: title ?? Date().formatted(date: .abbreviated, time: .omitted),
            caption: nil,
            photoUrl: publicURL.absoluteString,
            takenAt: now,
            tags: nil,
            createdAt: now
        ))
    }

    func delete(_ entry: PhotoJournalEntry) async {
        entries.removeAll { $0.id == entry.id }
        do {
            try await supabase
                .from("photo_journal_entries").delete()
                .eq("id", value: entry.id.uuidString).execute()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

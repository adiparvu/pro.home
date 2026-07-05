import Foundation
import Observation

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
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await supabase
                .from("photo_journal_entries")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("taken_at", ascending: false)
                .execute().value
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

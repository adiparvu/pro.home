import Foundation
import Observation
import Supabase

// MARK: - Plant care history (Plant OS P5)
//
// The append-only event log for one plant. Mirrors PlantPhotoService: loaded
// lazily and locally by the plant page, newest-first. Insert/delete keep the
// local array in sync so the timeline updates without a round-trip refetch.

@MainActor
@Observable
final class PlantEventService {
    private(set) var events: [PlantEvent] = []
    var isLoading = false

    func load(plantId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        events = (try? await supabase.from("plant_events")
            .select()
            .eq("plant_id", value: plantId.uuidString)
            .order("at", ascending: false)
            .execute().value) ?? []
    }

    /// Logs one care event for a plant. `at` defaults to now. Returns the
    /// inserted row (nil on failure) and prepends it to the local timeline.
    @discardableResult
    func log(plantId: UUID,
             propertyId: UUID,
             kind: PlantEventKind,
             details: [String: String]? = nil,
             at: Date = Date()) async -> PlantEvent? {
        struct Payload: Encodable {
            let plant_id: String
            let property_id: String
            let kind: String
            let details: [String: String]?
            let at: String
        }
        let payload = Payload(
            plant_id: plantId.uuidString,
            property_id: propertyId.uuidString,
            kind: kind.rawValue,
            details: details,
            at: ISODate.string(from: at)
        )
        do {
            let row: PlantEvent = try await supabase.from("plant_events")
                .insert(payload)
                .select().single().execute().value
            events.insert(row, at: 0)
            events.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            return row
        } catch {
            return nil
        }
    }

    func delete(_ event: PlantEvent) async {
        events.removeAll { $0.id == event.id }
        do {
            try await supabase.from("plant_events").delete()
                .eq("id", value: event.id.uuidString).execute()
        } catch { /* best-effort; the row is already gone from the local list */ }
    }
}

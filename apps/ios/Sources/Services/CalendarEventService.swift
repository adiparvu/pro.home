import Foundation
import Observation
import Supabase

/// The household's own calendar events (Calendar C2). Property-scoped, backed by
/// the `calendar_events` table; mirrors `PlantService` — cache-painted load via
/// `PropertyRepo` (off-main decode) and direct `supabase.from` writes. Rows are
/// RLS-scoped to household members, so nothing here re-checks membership.
@MainActor
@Observable
final class CalendarEventService {
    private(set) var events: [CalendarEvent] = []
    var isLoading = false
    var error: String?

    // MARK: Load

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if events.isEmpty, let cached = ServiceCache.load([CalendarEvent].self, entity: "calendar_events", propertyId: propertyId) {
            events = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await PropertyRepo.fetch(table: "calendar_events", propertyId: propertyId,
                                                  scope: .strict, order: "starts_at",
                                                  ascending: true, limit: 1000)
            ServiceCache.save(events, entity: "calendar_events", propertyId: propertyId)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    // MARK: CRUD

    private struct NewEvent: Encodable {
        let propertyId: UUID
        let title: String
        let notes: String?
        let startsAt: String
        let endsAt: String?
        let allDay: Bool
        let color: String?
        let location: String?
        enum CodingKeys: String, CodingKey {
            case title, notes, color, location
            case propertyId = "property_id"
            case startsAt   = "starts_at"
            case endsAt     = "ends_at"
            case allDay     = "all_day"
        }
    }

    @discardableResult
    func create(propertyId: UUID, title: String, notes: String?, startsAt: String,
                endsAt: String?, allDay: Bool, color: String?, location: String?) async throws -> CalendarEvent {
        let payload = NewEvent(propertyId: propertyId, title: title, notes: notes,
                               startsAt: startsAt, endsAt: endsAt, allDay: allDay,
                               color: color, location: location)
        let inserted: CalendarEvent = try await supabase
            .from("calendar_events")
            .insert(payload)
            .select().single().execute().value
        // Upsert, not append: a concurrent load() (foreground/world tick) may
        // already have fetched this row — a duplicate id would give SwiftUI
        // two identical ForEach identities in the calendar.
        events.removeAll { $0.id == inserted.id }
        events.append(inserted)
        events.sort { $0.startsAt < $1.startsAt }
        ServiceCache.save(events, entity: "calendar_events", propertyId: propertyId)
        return inserted
    }

    private struct EventUpdate: Encodable {
        let title: String
        let notes: String?
        let startsAt: String
        let endsAt: String?
        let allDay: Bool
        let color: String?
        let location: String?
        let updatedAt: String
        enum CodingKeys: String, CodingKey {
            case title, notes, color, location
            case startsAt   = "starts_at"
            case endsAt     = "ends_at"
            case allDay     = "all_day"
            case updatedAt  = "updated_at"
        }
    }

    func update(_ event: CalendarEvent) async {
        let upd = EventUpdate(title: event.title, notes: event.notes, startsAt: event.startsAt,
                              endsAt: event.endsAt, allDay: event.allDay, color: event.color,
                              location: event.location, updatedAt: ISODate.string(from: Date()))
        do {
            let updated: CalendarEvent = try await supabase
                .from("calendar_events").update(upd)
                .eq("id", value: event.id.uuidString)
                .select().single().execute().value
            if let i = events.firstIndex(where: { $0.id == event.id }) { events[i] = updated }
            events.sort { $0.startsAt < $1.startsAt }
            ServiceCache.save(events, entity: "calendar_events", propertyId: event.propertyId)
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ event: CalendarEvent) async {
        // Optimistic: drop locally first, best-effort network delete.
        events.removeAll { $0.id == event.id }
        ServiceCache.save(events, entity: "calendar_events", propertyId: event.propertyId)
        do {
            try await supabase.from("calendar_events").delete()
                .eq("id", value: event.id.uuidString).execute()
        } catch { /* best-effort; the row is already gone from the local list */ }
    }
}

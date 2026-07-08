import Foundation
import Observation
import Supabase

// MARK: - Document events (Document Intelligence D5)
//
// The per-document history timeline. Events are append-only and written at the
// honest moment an action happens (create, edit, add/remove a file, open for
// viewing). Reads inherit the parent document's RLS (migration 127), so the
// timeline is visible exactly to whoever can see the document itself.
//
// Logging is best-effort by design: history is a nicety, never a blocker, so a
// failed insert is swallowed and can never surface an error into a user flow.

@MainActor
@Observable
final class DocumentEventsService {
    private(set) var events: [DocumentEvent] = []
    var isLoading = false

    func load(documentId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        events = (try? await supabase.from("document_events")
            .select()
            .eq("document_id", value: documentId.uuidString)
            .order("at", ascending: false)
            .execute().value) ?? []
    }

    /// Records one event. Best-effort: never throws into the UI. Instance form
    /// keeps the loaded list fresh when logging from a screen that shows it.
    func log(documentId: UUID, kind: DocumentEvent.Kind, details: [String: String]? = nil) async {
        guard let row = await Self.insert(documentId: documentId, kind: kind, details: details) else { return }
        events.insert(row, at: 0)
    }

    /// Convenience for call sites that only need to fire an event and don't hold
    /// a service instance (services wiring their own actions). Best-effort.
    static func log(documentId: UUID, kind: DocumentEvent.Kind, details: [String: String]? = nil) async {
        _ = await insert(documentId: documentId, kind: kind, details: details)
    }

    /// Shared insert. Returns the created row on success, nil on any failure.
    private static func insert(documentId: UUID, kind: DocumentEvent.Kind,
                               details: [String: String]?) async -> DocumentEvent? {
        struct Payload: Encodable {
            let document_id: String
            let kind: String
            let actor_id: String?
            let details: [String: String]?
        }
        let actor = supabase.auth.currentSession?.user.id
        let payload = Payload(document_id: documentId.uuidString,
                              kind: kind.rawValue,
                              actor_id: actor?.uuidString,
                              details: details)
        return try? await supabase.from("document_events")
            .insert(payload)
            .select().single().execute().value
    }
}

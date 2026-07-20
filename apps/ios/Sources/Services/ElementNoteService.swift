import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class ElementNoteService {
    var notesByElement: [UUID: [ElementNote]] = [:]
    var error: String?

    func notes(for elementId: UUID) -> [ElementNote] {
        notesByElement[elementId] ?? []
    }

    func load(elementId: UUID) async {
        do {
            let loaded: [ElementNote] = try await supabase
                .from("element_notes")
                .select()
                .eq("element_id", value: elementId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            notesByElement[elementId] = loaded
        } catch {
            self.error = error.recordableDescription
        }
    }

    func add(elementId: UUID, propertyId: UUID, body: String, locked: Bool,
             checklist: [ChecklistItem] = [], photoUrls: [String] = []) async {
        let storedBody = locked ? (NoteLockManager.shared.encrypt(body) ?? body) : body
        let payload = NewElementNote(elementId: elementId, propertyId: propertyId, body: storedBody,
                                     isLocked: locked, checklist: checklist, photoUrls: photoUrls)
        do {
            let created: ElementNote = try await supabase
                .from("element_notes")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            notesByElement[elementId, default: []].insert(created, at: 0)
        } catch {
            self.error = error.recordableDescription
        }
    }

    func update(_ note: ElementNote, body: String, locked: Bool,
                checklist: [ChecklistItem]? = nil, photoUrls: [String]? = nil) async {
        let storedBody = locked ? (NoteLockManager.shared.encrypt(body) ?? body) : body
        let payload = ElementNoteUpdate(
            body: storedBody,
            isLocked: locked,
            checklist: checklist ?? note.checklist,
            photoUrls: photoUrls ?? note.photoUrls,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            let updated: ElementNote = try await supabase
                .from("element_notes")
                .update(payload)
                .eq("id", value: note.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if var arr = notesByElement[note.elementId],
               let idx = arr.firstIndex(where: { $0.id == note.id }) {
                arr[idx] = updated
                notesByElement[note.elementId] = arr
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    func delete(_ note: ElementNote) async {
        do {
            try await supabase
                .from("element_notes")
                .delete()
                .eq("id", value: note.id.uuidString)
                .execute()
            notesByElement[note.elementId]?.removeAll { $0.id == note.id }
        } catch {
            self.error = error.recordableDescription
        }
    }

    func toggleChecklistItem(_ note: ElementNote, itemId: UUID) async {
        guard var arr = notesByElement[note.elementId],
              let idx = arr.firstIndex(where: { $0.id == note.id }),
              let ci = arr[idx].checklist.firstIndex(where: { $0.id == itemId }) else { return }
        arr[idx].checklist[ci].done.toggle()
        notesByElement[note.elementId] = arr // optimistic
        let updated = arr[idx]
        await update(updated, body: displayBody(updated), locked: updated.isLocked,
                     checklist: updated.checklist, photoUrls: updated.photoUrls)
    }

    /// Returns the readable body: decrypts locked notes (caller must ensure unlocked).
    func displayBody(_ note: ElementNote) -> String {
        guard note.isLocked else { return note.body }
        return NoteLockManager.shared.decrypt(note.body) ?? ""
    }
}

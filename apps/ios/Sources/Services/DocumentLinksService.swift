import Foundation
import Observation
import Supabase

// MARK: - Document relations (Document Intelligence D4)
//
// One document's two relation sets: the house objects it's attached to
// (document_links) and the documents it chains to (related_documents). Both
// tables inherit the parent document's RLS, so this service only ever sees
// what the user is allowed to. Target/related names are resolved lazily.

@MainActor
@Observable
final class DocumentLinksService {
    private(set) var links: [DocumentLink] = []
    private(set) var childEdges: [RelatedDocument] = []    // this document is the parent
    private(set) var parentEdges: [RelatedDocument] = []   // this document is the child
    var isLoading = false

    func load(documentId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        async let l: [DocumentLink] = (try? await supabase.from("document_links")
            .select().eq("document_id", value: documentId.uuidString)
            .order("created_at", ascending: true).execute().value) ?? []
        async let c: [RelatedDocument] = (try? await supabase.from("related_documents")
            .select().eq("parent_id", value: documentId.uuidString)
            .order("created_at", ascending: true).execute().value) ?? []
        async let p: [RelatedDocument] = (try? await supabase.from("related_documents")
            .select().eq("child_id", value: documentId.uuidString)
            .order("created_at", ascending: true).execute().value) ?? []
        links = await l
        childEdges = await c
        parentEdges = await p
    }

    // MARK: Links to objects

    @discardableResult
    func addLink(documentId: UUID, kind: DocumentTargetKind, targetId: UUID) async -> Bool {
        struct Payload: Encodable { let document_id, target_kind, target_id: String }
        do {
            let row: DocumentLink = try await supabase.from("document_links")
                .insert(Payload(document_id: documentId.uuidString,
                                target_kind: kind.rawValue, target_id: targetId.uuidString))
                .select().single().execute().value
            links.append(row)
            return true
        } catch { return false }
    }

    func removeLink(_ link: DocumentLink) async {
        do {
            try await supabase.from("document_links").delete()
                .eq("id", value: link.id.uuidString).execute()
            links.removeAll { $0.id == link.id }
        } catch { /* best-effort */ }
    }

    // MARK: Document chains

    @discardableResult
    func addRelated(parentId: UUID, childId: UUID, relation: String?) async -> Bool {
        guard parentId != childId else { return false }
        struct Payload: Encodable { let parent_id, child_id: String; let relation: String? }
        do {
            let row: RelatedDocument = try await supabase.from("related_documents")
                .insert(Payload(parent_id: parentId.uuidString, child_id: childId.uuidString, relation: relation))
                .select().single().execute().value
            childEdges.append(row)
            return true
        } catch { return false }
    }

    func removeRelated(_ edge: RelatedDocument) async {
        do {
            try await supabase.from("related_documents").delete()
                .eq("id", value: edge.id.uuidString).execute()
            childEdges.removeAll { $0.id == edge.id }
            parentEdges.removeAll { $0.id == edge.id }
        } catch { /* best-effort */ }
    }

    // MARK: Reverse lookup (for a target object's page)

    /// The document ids linked to a given object — the query a target page runs
    /// to show "papers attached to me". RLS still applies, so it returns only
    /// links whose document the caller may see.
    static func documentIds(forTarget kind: DocumentTargetKind, targetId: UUID) async -> [UUID] {
        struct Row: Decodable { let document_id: UUID }
        let rows: [Row] = (try? await supabase.from("document_links")
            .select("document_id")
            .eq("target_kind", value: kind.rawValue)
            .eq("target_id", value: targetId.uuidString)
            .execute().value) ?? []
        return rows.map(\.document_id)
    }

    /// Resolves a linked object's display name (best-effort; nil if gone).
    static func targetName(kind: DocumentTargetKind, targetId: UUID) async -> String? {
        struct Row: Decodable { let name: String? }
        let row: Row? = try? await supabase.from(kind.table)
            .select("name").eq("id", value: targetId.uuidString)
            .single().execute().value
        return row?.name
    }
}

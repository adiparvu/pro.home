import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class DocumentService {
    var documents: [DocumentModel] = []
    var isLoading = false
    var isSaving = false
    var error: String?

    var criticalDocs: [DocumentModel] { documents.filter { $0.isCritical } }
    var expiringDocs: [DocumentModel] { documents.filter { $0.isExpiringSoon } }

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if documents.isEmpty, let cached = ServiceCache.load([DocumentModel].self, entity: "documents", propertyId: pid) {
            documents = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var query = supabase.from("documents").select()
            if let pid {
                // Scope to the selected home; legacy rows without a property
                // stay visible rather than silently disappearing.
                query = query.or("property_id.eq.\(pid.uuidString),property_id.is.null")
            }
            documents = try await query
                .order("created_at", ascending: false)
                .execute()
                .value
            ServiceCache.save(documents, entity: "documents", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func add(
        propertyId: UUID,
        name: String,
        category: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        expiresAt: String?,
        isCritical: Bool,
        sharedMemberIds: [String] = []
    ) async throws {
        guard let userId = supabase.auth.currentSession?.user.id else {
            throw DocumentError.notAuthenticated
        }

        isSaving = true
        defer { isSaving = false }

        let filePath = "\(userId.uuidString)/\(UUID().uuidString)-\(fileName)"
        try await supabase.storage
            .from("documents")
            .upload(filePath, data: fileData, options: FileOptions(contentType: mimeType, upsert: false))

        let publicURL = try supabase.storage.from("documents").getPublicURL(path: filePath)

        struct DocInsert: Encodable {
            let property_id: String
            let name: String
            let category: String
            let file_url: String
            let file_name: String
            let file_size: Int64
            let mime_type: String
            let expires_at: String?
            let is_critical: Bool
            let tags: [String]
            let shared_member_ids: [String]
        }

        let payload = DocInsert(
            property_id: propertyId.uuidString,
            name: name,
            category: category,
            file_url: publicURL.absoluteString,
            file_name: fileName,
            file_size: Int64(fileData.count),
            mime_type: mimeType,
            expires_at: expiresAt,
            is_critical: isCritical,
            tags: [],
            shared_member_ids: sharedMemberIds
        )

        let newDoc: DocumentModel = try await supabase
            .from("documents")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        documents.insert(newDoc, at: 0)
    }

    func documents(forElement elementId: UUID) -> [DocumentModel] {
        documents.filter { $0.elementId == elementId }
    }

    /// Link (or unlink, with nil) a document to an object.
    func setElement(_ elementId: UUID?, for doc: DocumentModel) async {
        struct ElementLink: Encodable {
            let element_id: String?
        }
        do {
            try await supabase
                .from("documents")
                .update(ElementLink(element_id: elementId?.uuidString))
                .eq("id", value: doc.id.uuidString)
                .execute()
            if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[idx].elementId = elementId
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Update a document's editable metadata (name, category, critical flag,
    /// expiry, description). The file itself is not touched.
    func update(_ doc: DocumentModel) async {
        struct Upd: Encodable {
            let name: String
            let category: String
            let is_critical: Bool
            let expires_at: String?
            let description: String?
        }
        do {
            try await supabase
                .from("documents")
                .update(Upd(name: doc.name, category: doc.category,
                            is_critical: doc.isCritical, expires_at: doc.expiresAt,
                            description: doc.description))
                .eq("id", value: doc.id.uuidString)
                .execute()
            if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[idx] = doc
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ doc: DocumentModel) async {
        do {
            // Remove from storage
            if let url = URL(string: doc.fileUrl),
               url.host?.contains("supabase") == true {
                let components = url.pathComponents
                if let bucketIdx = components.firstIndex(of: "documents"),
                   bucketIdx + 1 < components.count {
                    let storagePath = components[(bucketIdx + 1)...].joined(separator: "/")
                    _ = try? await supabase.storage.from("documents").remove(paths: [storagePath])
                }
            }
            try await supabase
                .from("documents")
                .delete()
                .eq("id", value: doc.id.uuidString)
                .execute()
            documents.removeAll { $0.id == doc.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum DocumentError: LocalizedError {
    case notAuthenticated
    case noProperty

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return String(localized: "You must be signed in to upload documents.")
        case .noProperty: return String(localized: "Please set up your property first.")
        }
    }
}

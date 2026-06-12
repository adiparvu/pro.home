import Foundation
import Supabase

@MainActor
final class DocumentService: ObservableObject {
    @Published var documents: [DocumentModel] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    var criticalDocs: [DocumentModel] { documents.filter { $0.isCritical } }
    var expiringDocs: [DocumentModel] { documents.filter { $0.isExpiringSoon } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await supabase
                .from("documents")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
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
        isCritical: Bool
    ) async throws {
        guard let userId = try? await supabase.auth.session.user.id else {
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
            tags: []
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

    func delete(_ doc: DocumentModel) async {
        do {
            // Remove from storage
            if let url = URL(string: doc.fileUrl),
               url.host?.contains("supabase") == true {
                let components = url.pathComponents
                if let bucketIdx = components.firstIndex(of: "documents"),
                   bucketIdx + 1 < components.count {
                    let storagePath = components[(bucketIdx + 1)...].joined(separator: "/")
                    try? await supabase.storage.from("documents").remove(paths: [storagePath])
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
        case .notAuthenticated: return "You must be signed in to upload documents."
        case .noProperty: return "Please set up your property first."
        }
    }
}

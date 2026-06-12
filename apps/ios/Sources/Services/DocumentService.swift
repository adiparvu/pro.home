import Foundation

@MainActor
final class DocumentService: ObservableObject {
    @Published var documents: [DocumentModel] = []
    @Published var isLoading = false

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
            print("[DocumentService] load error: \(error)")
        }
    }
}

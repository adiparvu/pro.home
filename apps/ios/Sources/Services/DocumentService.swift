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
            documents = try await PropertyRepo.fetch(table: "documents", propertyId: pid, limit: 500)
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
        sharedMemberIds: [String] = [],
        ocrText: String? = nil,
        extra: DocumentExtra = DocumentExtra()
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

        // The full rich record (migration 121). All D1 fields are optional, so
        // a document with none set inserts exactly like the old shape.
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
            let subcategory: String?
            let description: String?
            let priority: String
            let issued_at: String?
            let renew_at: String?
            let notify_at: String?
            let issuer_company: String?
            let issuer_contact: String?
            let issuer_phone: String?
            let issuer_email: String?
            let issuer_website: String?
            let client_number: String?
            let doc_number: String?
            let series: String?
            let contract_code: String?
            let client_code: String?
            let fiscal_code: String?
            let policy_number: String?
            let barcode: String?
            let value: Double?
            let currency: String?
            let vat: Double?
            let recurrence: String?
            // D6: creator (for hide-from-family ownership) + OCR text (search).
            let uploaded_by: String
            let ocr_text: String?
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
            tags: extra.tags,
            shared_member_ids: sharedMemberIds,
            subcategory: extra.subcategory,
            description: extra.description,
            priority: extra.priority,
            issued_at: extra.issuedAt,
            renew_at: extra.renewAt,
            notify_at: extra.notifyAt,
            issuer_company: extra.issuerCompany,
            issuer_contact: extra.issuerContact,
            issuer_phone: extra.issuerPhone,
            issuer_email: extra.issuerEmail,
            issuer_website: extra.issuerWebsite,
            client_number: extra.clientNumber,
            doc_number: extra.docNumber,
            series: extra.series,
            contract_code: extra.contractCode,
            client_code: extra.clientCode,
            fiscal_code: extra.fiscalCode,
            policy_number: extra.policyNumber,
            barcode: extra.barcode,
            value: extra.value,
            currency: extra.currency,
            vat: extra.vat,
            recurrence: extra.recurrence,
            uploaded_by: userId.uuidString,
            ocr_text: ocrText
        )

        let newDoc: DocumentModel = try await supabase
            .from("documents")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        documents.insert(newDoc, at: 0)

        // History (D5): the document was created. Best-effort — never blocks add.
        await DocumentEventsService.log(documentId: newDoc.id, kind: .created,
                                        details: ["name": newDoc.name])
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
            let tags: [String]
            let subcategory: String?
            let priority: String?
            let issued_at: String?
            let renew_at: String?
            let notify_at: String?
            let issuer_company: String?
            let issuer_contact: String?
            let issuer_phone: String?
            let issuer_email: String?
            let issuer_website: String?
            let client_number: String?
            let doc_number: String?
            let series: String?
            let contract_code: String?
            let client_code: String?
            let fiscal_code: String?
            let policy_number: String?
            let barcode: String?
            let value: Double?
            let currency: String?
            let vat: Double?
            let recurrence: String?
        }
        // No-op saves must not touch the network or the history: re-saving the
        // edit sheet without changing anything used to append a fresh
        // "Modificat" event every time, flooding the timeline.
        let old = documents.first(where: { $0.id == doc.id })
        if let old, old == doc { return }
        do {
            try await supabase
                .from("documents")
                .update(Upd(name: doc.name, category: doc.category,
                            is_critical: doc.isCritical, expires_at: doc.expiresAt,
                            description: doc.description, tags: doc.tags,
                            subcategory: doc.subcategory, priority: doc.priority,
                            issued_at: doc.issuedAt, renew_at: doc.renewAt, notify_at: doc.notifyAt,
                            issuer_company: doc.issuerCompany, issuer_contact: doc.issuerContact,
                            issuer_phone: doc.issuerPhone, issuer_email: doc.issuerEmail,
                            issuer_website: doc.issuerWebsite, client_number: doc.clientNumber,
                            doc_number: doc.docNumber, series: doc.series,
                            contract_code: doc.contractCode, client_code: doc.clientCode,
                            fiscal_code: doc.fiscalCode, policy_number: doc.policyNumber,
                            barcode: doc.barcode, value: doc.value, currency: doc.currency,
                            vat: doc.vat, recurrence: doc.recurrence))
                .eq("id", value: doc.id.uuidString)
                .execute()
            if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[idx] = doc
            }
            // History (D5): metadata was edited. Best-effort. The entry carries
            // the real per-field diff (old → new) so the timeline can say WHAT
            // changed, not just that something did; pre-diff rows render as
            // before.
            var details = ["name": doc.name]
            if let old {
                details.merge(DocumentFieldChange.encode(old: old, new: doc)) { _, new in new }
            }
            await DocumentEventsService.log(documentId: doc.id, kind: .edited,
                                            details: details)
            // A distinct "renewed" entry when the expiry moved to a LATER day —
            // the .renewed kind existed with full render support but nothing
            // ever emitted it. Only a real extension counts; shortening or
            // clearing the date stays a plain edit.
            if let oldExp = old?.expiresAt.flatMap(AppDate.day(from:)),
               let newExp = doc.expiresAt.flatMap(AppDate.day(from:)),
               newExp > oldExp {
                await DocumentEventsService.log(documentId: doc.id, kind: .renewed,
                                                details: ["expires_at": doc.expiresAt ?? ""])
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Per-document security (D6)

    /// The signed-in user's id string — used to decide who owns a document
    /// (only the owner may hide it from the family).
    var currentUserId: String? { supabase.auth.currentSession?.user.id.uuidString }

    /// Toggle the read-only lock. Sends ONLY `read_only`, so the DB guard
    /// trigger (migration 132) always permits it even while the row is locked.
    func setReadOnly(_ value: Bool, for doc: DocumentModel) async {
        struct Upd: Encodable { let read_only: Bool }
        do {
            try await supabase
                .from("documents")
                .update(Upd(read_only: value))
                .eq("id", value: doc.id.uuidString)
                .execute()
            if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[idx].readOnly = value
            }
            await DocumentEventsService.log(documentId: doc.id, kind: .edited,
                                            details: ["read_only": value ? "on" : "off"])
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggle owner-only visibility. Enforced by RLS at the database — a hidden
    /// document simply stops appearing for everyone but its creator.
    func setHiddenFromFamily(_ value: Bool, for doc: DocumentModel) async {
        struct Upd: Encodable { let hidden_from_family: Bool }
        do {
            try await supabase
                .from("documents")
                .update(Upd(hidden_from_family: value))
                .eq("id", value: doc.id.uuidString)
                .execute()
            if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[idx].hiddenFromFamily = value
            }
            // Visibility is a sharing event, not a metadata edit — the .shared
            // kind existed with full render support but was never emitted.
            await DocumentEventsService.log(documentId: doc.id, kind: .shared,
                                            details: ["hidden_from_family": value ? "on" : "off"])
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

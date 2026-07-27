import Foundation
import Observation
import Supabase
import UIKit

// MARK: - Insurance claim service ("Asistent de daune")
//
// CRUD over `insurance_claims` plus evidence-photo uploads (same bucket and
// path family as meter photos: compressed JPEGs under the user's folder,
// displayed through StorageImage's signed access). Lazy like MeterService.

@MainActor
@Observable
final class InsuranceClaimService {
    private(set) var claims: [InsuranceClaim] = []
    var isLoading = false
    var error: String?
    private var loadedPropertyId: UUID?

    func loadIfNeeded() async {
        let pid = PropertyService.activePropertyId
        guard loadedPropertyId != pid || claims.isEmpty else { return }
        await load()
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        if claims.isEmpty, let cached = ServiceCache.load([InsuranceClaim].self, entity: "insurance_claims", propertyId: pid) {
            claims = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            claims = try await PropertyRepo.fetch(table: "insurance_claims", propertyId: pid,
                                                  order: "incident_date", limit: 200)
            loadedPropertyId = pid
            ServiceCache.save(claims, entity: "insurance_claims", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    /// Open first (draft → in_review), resolved last, newest incident first
    /// inside each band.
    var sorted: [InsuranceClaim] {
        claims.sorted {
            if ($0.statusKind == .resolved) != ($1.statusKind == .resolved) {
                return $1.statusKind == .resolved
            }
            return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    // MARK: - Mutations

    struct ClaimPayload: Encodable {
        var propertyId: String?
        let title: String
        let description: String?
        let incidentDate: String
        let insurer: String?
        let policyNumber: String?
        let claimedAmount: Double?
        let currency: String
        let photoUrls: [String]
        var updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case title, description, insurer, currency
            case propertyId    = "property_id"
            case incidentDate  = "incident_date"
            case policyNumber  = "policy_number"
            case claimedAmount = "claimed_amount"
            case photoUrls     = "photo_urls"
            case updatedAt     = "updated_at"
        }
    }

    func add(_ payload: ClaimPayload) async throws {
        var p = payload
        p.propertyId = PropertyService.activePropertyId?.uuidString
        try await supabase.from("insurance_claims").insert(p).execute()
        await load()
    }

    func update(_ id: UUID, payload: ClaimPayload) async throws {
        var p = payload
        p.updatedAt = ISODate.string(from: Date())
        try await supabase.from("insurance_claims")
            .update(p).eq("id", value: id.uuidString).execute()
        await load()
    }

    func delete(_ claim: InsuranceClaim) async {
        do {
            try await supabase.from("insurance_claims")
                .delete().eq("id", value: claim.id.uuidString).execute()
            claims.removeAll { $0.id == claim.id }
        } catch { self.error = error.recordableDescription }
    }

    private struct StatusPatch: Encodable {
        let status: String
        let approvedAmount: Double?
        let updatedAt: String
        enum CodingKeys: String, CodingKey {
            case status
            case approvedAmount = "approved_amount"
            case updatedAt      = "updated_at"
        }
    }

    /// Moves the claim along its life. The approved amount only travels with
    /// a resolution — everything before that is still just a request.
    func setStatus(_ claim: InsuranceClaim, to status: ClaimStatus,
                   approvedAmount: Double? = nil) async throws {
        try await supabase.from("insurance_claims")
            .update(StatusPatch(status: status.rawValue,
                                approvedAmount: approvedAmount ?? claim.approvedAmount,
                                updatedAt: ISODate.string(from: Date())))
            .eq("id", value: claim.id.uuidString).execute()
        await load()
    }

    // MARK: - Evidence photos

    /// Uploads a batch of damage photos and returns their storage URLs, in
    /// order. A failed upload throws — a claim never silently loses evidence.
    func uploadPhotos(_ photos: [Data]) async throws -> [String] {
        guard let pid = PropertyService.activePropertyId,
              let uid = supabase.auth.currentSession?.user.id else { return [] }
        var urls: [String] = []
        for data in photos {
            let compressed = UIImage(data: data)
                .flatMap { $0.uploadJPEG(quality: 0.8) } ?? data
            let path = "\(uid.uuidString.lowercased())/claims/\(pid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            try await supabase.storage.from("documents")
                .upload(path, data: compressed,
                        options: FileOptions(contentType: "image/jpeg", upsert: false))
            urls.append(try supabase.storage.from("documents")
                .getPublicURL(path: path).absoluteString)
        }
        return urls
    }
}

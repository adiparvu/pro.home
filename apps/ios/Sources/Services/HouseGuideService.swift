import Foundation
import Observation
import Supabase

// MARK: - House guide service ("Manualul casei")
//
// Calm CRUD over `house_guides`. Loaded lazily on the manual's surfaces —
// a guide changes rarely and is read on demand. Mirrors MeterService.

@MainActor
@Observable
final class HouseGuideService {
    private(set) var guides: [HouseGuide] = []
    var isLoading = false
    var error: String?
    private var loadedPropertyId: UUID?

    func loadIfNeeded() async {
        let pid = PropertyService.activePropertyId
        guard loadedPropertyId != pid || guides.isEmpty else { return }
        await load()
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        if guides.isEmpty, let cached = ServiceCache.load([HouseGuide].self, entity: "house_guides", propertyId: pid) {
            guides = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guides = try await PropertyRepo.fetch(table: "house_guides", propertyId: pid,
                                                  order: "created_at", limit: 200)
            loadedPropertyId = pid
            ServiceCache.save(guides, entity: "house_guides", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    struct GuidePayload: Encodable {
        var propertyId: String?
        let title: String
        let icon: String?
        let content: String
        let zoneId: String?
        let applianceId: String?
        var updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case title, icon, content
            case propertyId  = "property_id"
            case zoneId      = "zone_id"
            case applianceId = "appliance_id"
            case updatedAt   = "updated_at"
        }
    }

    func add(_ payload: GuidePayload) async throws {
        var p = payload
        p.propertyId = PropertyService.activePropertyId?.uuidString
        try await supabase.from("house_guides").insert(p).execute()
        await load()
    }

    func update(_ id: UUID, payload: GuidePayload) async throws {
        var p = payload
        p.updatedAt = ISODate.string(from: Date())
        try await supabase.from("house_guides")
            .update(p).eq("id", value: id.uuidString).execute()
        await load()
    }

    func delete(_ guide: HouseGuide) async {
        do {
            try await supabase.from("house_guides")
                .delete().eq("id", value: guide.id.uuidString).execute()
            guides.removeAll { $0.id == guide.id }
        } catch { self.error = error.recordableDescription }
    }
}

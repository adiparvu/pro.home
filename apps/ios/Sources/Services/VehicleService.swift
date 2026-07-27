import Foundation
import Observation
import Supabase

// MARK: - Vehicle service ("Garajul familiei")
//
// Small, calm CRUD over `vehicles`. Loaded with the world (the agenda and
// net worth need the deadlines/values at launch); no realtime — a family
// edits its cars rarely, and every mutation reloads.

@MainActor
@Observable
final class VehicleService {
    private(set) var vehicles: [Vehicle] = []
    var isLoading = false
    var error: String?

    func load() async {
        let pid = PropertyService.activePropertyId
        if vehicles.isEmpty, let cached = ServiceCache.load([Vehicle].self, entity: "vehicles", propertyId: pid) {
            vehicles = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            vehicles = try await PropertyRepo.fetch(table: "vehicles", propertyId: pid,
                                                    order: "created_at", limit: 50)
            ServiceCache.save(vehicles, entity: "vehicles", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    struct VehiclePayload: Encodable {
        var propertyId: String?
        let name: String
        let make: String?
        let model: String?
        let plate: String?
        let year: Int?
        let fuelType: String?
        let value: Double?
        let currency: String
        let itpExpires: String?
        let insuranceExpires: String?
        let vignetteExpires: String?
        let notes: String?
        var updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case name, make, model, plate, year, value, currency, notes
            case propertyId       = "property_id"
            case fuelType         = "fuel_type"
            case itpExpires       = "itp_expires"
            case insuranceExpires = "insurance_expires"
            case vignetteExpires  = "vignette_expires"
            case updatedAt        = "updated_at"
        }
    }

    func add(_ payload: VehiclePayload) async throws {
        var p = payload
        p.propertyId = PropertyService.activePropertyId?.uuidString
        try await supabase.from("vehicles").insert(p).execute()
        await load()
    }

    func update(_ id: UUID, payload: VehiclePayload) async throws {
        var p = payload
        p.updatedAt = ISODate.string(from: Date())
        try await supabase.from("vehicles")
            .update(p).eq("id", value: id.uuidString).execute()
        await load()
    }

    func delete(_ vehicle: Vehicle) async {
        do {
            try await supabase.from("vehicles")
                .delete().eq("id", value: vehicle.id.uuidString).execute()
            vehicles.removeAll { $0.id == vehicle.id }
        } catch { self.error = error.recordableDescription }
    }
}

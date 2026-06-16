import Foundation
import Supabase

// MARK: - Pond Service
//
// CRUD for ponds and pond zones.
// Follows the exact same pattern as PropertyService / PropertyZoneService.

@MainActor
final class PondService: ObservableObject {

    // MARK: Published

    @Published private(set) var ponds: [Pond] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    // MARK: Supabase client (reuses the singleton from PRVIOApp)

    private let db = SupabaseClient.shared

    // MARK: Load

    func load(for propertyId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result: [Pond] = try await db
                .from("ponds")
                .select()
                .eq("property_id", value: propertyId)
                .order("created_at")
                .execute()
                .value
            ponds = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Create

    @discardableResult
    func create(_ payload: NewPond) async throws -> Pond {
        let created: Pond = try await db
            .from("ponds")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        ponds.append(created)
        return created
    }

    // MARK: Update

    func update(_ pond: Pond) async throws {
        struct UpdatePayload: Codable {
            let name: String
            let type: String
            let volumeLiters: Double?
            let surfaceAreaSqm: Double?
            let maxDepthCm: Double?
            let haInstanceId: String?
            let notes: String?
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case name, type
                case volumeLiters = "volume_liters"
                case surfaceAreaSqm = "surface_area_sqm"
                case maxDepthCm = "max_depth_cm"
                case haInstanceId = "ha_instance_id"
                case notes
                case updatedAt = "updated_at"
            }
        }
        let payload = UpdatePayload(
            name: pond.name,
            type: pond.type.rawValue,
            volumeLiters: pond.volumeLiters,
            surfaceAreaSqm: pond.surfaceAreaSqm,
            maxDepthCm: pond.maxDepthCm,
            haInstanceId: pond.haInstanceId,
            notes: pond.notes,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await db
            .from("ponds")
            .update(payload)
            .eq("id", value: pond.id.uuidString)
            .execute()
        if let idx = ponds.firstIndex(where: { $0.id == pond.id }) {
            ponds[idx] = pond
        }
    }

    // MARK: Delete

    func delete(_ pond: Pond) async throws {
        try await db
            .from("ponds")
            .delete()
            .eq("id", value: pond.id.uuidString)
            .execute()
        ponds.removeAll { $0.id == pond.id }
    }

    // MARK: Equipment

    func loadEquipment(for pondId: UUID) async throws -> [PondEquipment] {
        try await db
            .from("pond_equipment")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .execute()
            .value
    }

    func addEquipment(_ equipment: PondEquipment) async throws {
        struct Payload: Codable {
            let pondId: String
            let name: String
            let type: String
            let brand: String?
            let model: String?
            let positionX: Double
            let positionY: Double
            let isRunning: Bool
            let haEntityId: String?
            let powerWatts: Double?
            let warrantyUntil: String?
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case pondId = "pond_id"
                case name, type, brand, model
                case positionX = "position_x"
                case positionY = "position_y"
                case isRunning = "is_running"
                case haEntityId = "ha_entity_id"
                case powerWatts = "power_watts"
                case warrantyUntil = "warranty_until"
                case notes
            }
        }
        let payload = Payload(
            pondId: equipment.pondId.uuidString,
            name: equipment.name,
            type: equipment.type.rawValue,
            brand: equipment.brand,
            model: equipment.model,
            positionX: equipment.positionX,
            positionY: equipment.positionY,
            isRunning: equipment.isRunning,
            haEntityId: equipment.haEntityId,
            powerWatts: equipment.powerWatts,
            warrantyUntil: equipment.warrantyUntil.map { ISO8601DateFormatter().string(from: $0) },
            notes: equipment.notes
        )
        try await db.from("pond_equipment").insert(payload).execute()
    }

    // MARK: Zones

    func loadZones(for pondId: UUID) async throws -> [PondZone] {
        try await db
            .from("pond_zones")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .execute()
            .value
    }

    func addZone(_ zone: PondZone) async throws {
        struct Payload: Codable {
            let pondId: String
            let name: String
            let zoneType: String
            let positionX: Double
            let positionY: Double
            let radiusPercent: Double
            let colorHex: String
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case pondId = "pond_id"
                case name
                case zoneType = "zone_type"
                case positionX = "position_x"
                case positionY = "position_y"
                case radiusPercent = "radius_percent"
                case colorHex = "color_hex"
                case notes
            }
        }
        let payload = Payload(
            pondId: zone.pondId.uuidString,
            name: zone.name,
            zoneType: zone.zoneType.rawValue,
            positionX: zone.positionX,
            positionY: zone.positionY,
            radiusPercent: zone.radiusPercent,
            colorHex: zone.colorHex,
            notes: zone.notes
        )
        try await db.from("pond_zones").insert(payload).execute()
    }
}

import Foundation
import Observation
import SwiftUI
import CoreLocation

@MainActor
@Observable
final class PropertyZoneService {
    var zones: [PropertyZone] = []
    var isLoading = false
    var error: String?

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            zones = try await supabase
                .from("property_zones")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func add(_ payload: NewPropertyZone) async -> PropertyZone? {
        do {
            let created: PropertyZone = try await supabase
                .from("property_zones")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            zones.append(created)
            return created
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func update(_ zone: PropertyZone) async {
        let payload = NewPropertyZone(
            propertyId: zone.propertyId,
            name: zone.name,
            icon: zone.icon,
            colorHex: zone.colorHex,
            layer: zone.layer.rawValue,
            healthScore: zone.healthScore,
            polygon: zone.polygon,
            imagePolygon: zone.imagePolygon,
            photoUrl: zone.photoUrl,
            sortOrder: zone.sortOrder,
            createdAt: zone.createdAt,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            let updated: PropertyZone = try await supabase
                .from("property_zones")
                .update(payload)
                .eq("id", value: zone.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let idx = zones.firstIndex(where: { $0.id == zone.id }) {
                zones[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ zone: PropertyZone) async {
        do {
            try await supabase
                .from("property_zones")
                .delete()
                .eq("id", value: zone.id.uuidString)
                .execute()
            zones.removeAll { $0.id == zone.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Convenience

    /// Creates a default square zone centred on a coordinate.
    @discardableResult
    func createDefaultZone(
        propertyId: UUID,
        center: CLLocationCoordinate2D,
        name: String = "New zone",
        icon: String = "square.dashed",
        layer: PropertyLayer = .property
    ) async -> PropertyZone? {
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewPropertyZone(
            propertyId: propertyId,
            name: name,
            icon: icon,
            colorHex: layer.color.hexString(),
            layer: layer.rawValue,
            healthScore: 100,
            polygon: PropertyZone.squarePolygon(around: center, metres: 10),
            sortOrder: zones.count,
            createdAt: now,
            updatedAt: now
        )
        return await add(payload)
    }

    func zone(containing coordinate: CLLocationCoordinate2D) -> PropertyZone? {
        zones.first { $0.contains(coordinate) }
    }

    /// Creates a zone defined by a normalized polygon drawn on the aerial photo.
    @discardableResult
    func createImageZone(
        propertyId: UUID,
        imagePolygon: [ImagePoint],
        name: String = "New zone",
        icon: String = "square.dashed",
        layer: PropertyLayer = .property
    ) async -> PropertyZone? {
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewPropertyZone(
            propertyId: propertyId,
            name: name,
            icon: icon,
            colorHex: layer.color.hexString(),
            layer: layer.rawValue,
            healthScore: 100,
            polygon: [],
            imagePolygon: imagePolygon,
            sortOrder: zones.count,
            createdAt: now,
            updatedAt: now
        )
        return await add(payload)
    }
}

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PropertyElementService {
    var elements: [PropertyElement] = []
    var records: [UUID: [ElementRecord]] = [:]
    var isLoading = false
    var error: String?

    // MARK: - Elements CRUD

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            elements = try await supabase
                .from("property_elements")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(_ payload: NewPropertyElement) async {
        do {
            let created: PropertyElement = try await supabase
                .from("property_elements")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            elements.append(created)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(_ element: PropertyElement) async {
        do {
            let payload = NewPropertyElement(
                propertyId: element.propertyId,
                name: element.name,
                elementType: element.elementType.rawValue,
                description: element.description,
                positionX: element.positionX,
                positionY: element.positionY,
                healthScore: element.healthScore,
                technicalCondition: element.technicalCondition.rawValue,
                estimatedValue: element.estimatedValue,
                valueCurrency: element.valueCurrency,
                purchaseDate: element.purchaseDate,
                warrantyUntil: element.warrantyUntil,
                brand: element.brand,
                model: element.model,
                serialNumber: element.serialNumber,
                notes: element.notes,
                layer: element.layer.rawValue,
                latitude: element.latitude,
                longitude: element.longitude,
                zoneId: element.zoneId,
                photoUrls: element.photoUrls,
                coverPhotoUrl: element.coverPhotoUrl,
                isElectric: element.isElectric,
                automationSystem: element.automationSystem,
                isFavorite: element.isFavorite,
                homekitAccessoryId: element.homekitAccessoryId,
                tags: element.tags,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            let updated: PropertyElement = try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: element.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let idx = elements.firstIndex(where: { $0.id == element.id }) {
                elements[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updatePosition(elementId: UUID, x: Double, y: Double) async {
        let payload = ElementPositionUpdate(
            positionX: x,
            positionY: y,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
            if let idx = elements.firstIndex(where: { $0.id == elementId }) {
                elements[idx].positionX = x
                elements[idx].positionY = y
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateCover(elementId: UUID, url: String?) async {
        let payload = ElementCoverUpdate(
            coverPhotoUrl: url,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
            if let idx = elements.firstIndex(where: { $0.id == elementId }) {
                elements[idx].coverPhotoUrl = url
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateHomeKit(elementId: UUID, accessoryId: String?) async {
        struct Payload: Encodable {
            let homekit_accessory_id: String?
            let updated_at: String
        }
        let payload = Payload(homekit_accessory_id: accessoryId,
                              updated_at: ISO8601DateFormatter().string(from: Date()))
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
            if let idx = elements.firstIndex(where: { $0.id == elementId }) {
                elements[idx].homekitAccessoryId = accessoryId
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleFavorite(elementId: UUID) async {
        guard let idx = elements.firstIndex(where: { $0.id == elementId }) else { return }
        let newValue = !elements[idx].isFavorite
        elements[idx].isFavorite = newValue // optimistic
        let payload = ElementFavoriteUpdate(
            isFavorite: newValue,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
        } catch {
            if let i = elements.firstIndex(where: { $0.id == elementId }) {
                elements[i].isFavorite = !newValue // revert
            }
            self.error = error.localizedDescription
        }
    }

    func updateHealth(elementId: UUID, score: Int, condition: TechnicalCondition) async {
        let payload = ElementHealthUpdate(
            healthScore: score,
            technicalCondition: condition.rawValue,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
            if let idx = elements.firstIndex(where: { $0.id == elementId }) {
                elements[idx].healthScore = score
                elements[idx].technicalCondition = condition
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Geo-locate an object on the satellite map (and optionally assign a zone).
    func updateGeo(elementId: UUID, latitude: Double?, longitude: Double?, zoneId: UUID?) async {
        let payload = ElementGeoUpdate(
            latitude: latitude,
            longitude: longitude,
            zoneId: zoneId,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
            if let idx = elements.firstIndex(where: { $0.id == elementId }) {
                elements[idx].latitude = latitude
                elements[idx].longitude = longitude
                elements[idx].zoneId = zoneId
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updatePhotos(elementId: UUID, urls: [String]) async {
        let payload = ElementPhotosUpdate(
            photoUrls: urls,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("property_elements")
                .update(payload)
                .eq("id", value: elementId.uuidString)
                .execute()
            if let idx = elements.firstIndex(where: { $0.id == elementId }) {
                elements[idx].photoUrls = urls
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func elements(inZone zoneId: UUID) -> [PropertyElement] {
        elements.filter { $0.zoneId == zoneId }
    }

    func delete(_ element: PropertyElement) async {
        do {
            try await supabase
                .from("property_elements")
                .delete()
                .eq("id", value: element.id.uuidString)
                .execute()
            elements.removeAll { $0.id == element.id }
            records.removeValue(forKey: element.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Records CRUD

    func loadRecords(elementId: UUID) async {
        do {
            let loaded: [ElementRecord] = try await supabase
                .from("element_records")
                .select()
                .eq("element_id", value: elementId.uuidString)
                .order("record_date", ascending: false)
                .execute()
                .value
            records[elementId] = loaded
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addRecord(_ payload: NewElementRecord) async {
        do {
            let created: ElementRecord = try await supabase
                .from("element_records")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            records[created.elementId, default: []].insert(created, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteRecord(_ record: ElementRecord) async {
        do {
            try await supabase
                .from("element_records")
                .delete()
                .eq("id", value: record.id.uuidString)
                .execute()
            records[record.elementId]?.removeAll { $0.id == record.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Computed

    var overallHealthScore: Int {
        guard !elements.isEmpty else { return 100 }
        return elements.reduce(0) { $0 + $1.healthScore } / elements.count
    }

    var criticalElements: [PropertyElement] {
        elements.filter { $0.healthScore < 50 }.sorted { $0.healthScore < $1.healthScore }
    }

    var elementsNeedingAttention: [PropertyElement] {
        elements.filter { $0.healthScore < 75 }.sorted { $0.healthScore < $1.healthScore }
    }

    func elements(for layer: PropertyLayer?) -> [PropertyElement] {
        guard let layer else { return elements }
        return elements.filter { $0.layer == layer }
    }

    func totalEstimatedValue(currency: String = "EUR") -> Double {
        elements.compactMap { $0.estimatedValue }.reduce(0, +)
    }
}

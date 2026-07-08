import Foundation
import Observation
import Supabase

// MARK: - Plant sensor bindings (Plant OS P3)
//
// Loads and mutates the `plant_sensors` rows for one plant: which real IoT hub
// sensor is attached to each care metric (light / temperature / humidity). The
// live value itself is resolved separately, against IoTService, so this store
// only owns the binding — never a reading. Mirrors the @Observable, load-on-
// task style of PlantPhotoService / PlantSpeciesService.

@MainActor
@Observable
final class PlantSensorService {
    private(set) var bindings: [PlantSensorBinding] = []
    var isLoading = false

    func load(plantId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        bindings = (try? await supabase.from("plant_sensors")
            .select()
            .eq("plant_id", value: plantId.uuidString)
            .execute().value) ?? []
    }

    /// The binding for a metric, if any.
    func binding(for metric: PlantCareMetric) -> PlantSensorBinding? {
        bindings.first { $0.metric == metric.rawValue }
    }

    /// Attaches a sensor to a plant-metric, replacing any existing binding for
    /// that metric (the table's unique(plant_id, metric) makes this an upsert).
    /// Returns false on failure.
    @discardableResult
    func bind(plantId: UUID, propertyId: UUID, sensorRef: String, metric: PlantCareMetric) async -> Bool {
        struct Payload: Encodable {
            let plant_id: String, property_id: String, sensor_ref: String, metric: String
        }
        do {
            let row: PlantSensorBinding = try await supabase.from("plant_sensors")
                .upsert(Payload(plant_id: plantId.uuidString, property_id: propertyId.uuidString,
                                sensor_ref: sensorRef, metric: metric.rawValue),
                        onConflict: "plant_id,metric")
                .select().single().execute().value
            bindings.removeAll { $0.metric == metric.rawValue }
            bindings.append(row)
            return true
        } catch {
            return false
        }
    }

    func unbind(_ binding: PlantSensorBinding) async {
        do {
            try await supabase.from("plant_sensors").delete()
                .eq("id", value: binding.id.uuidString).execute()
            bindings.removeAll { $0.id == binding.id }
        } catch { /* best-effort */ }
    }
}

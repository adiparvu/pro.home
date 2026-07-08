import Foundation
import Observation

@MainActor
@Observable
final class PlantService {
    var plants: [Plant] = []
    var isLoading = false
    var error: String?

    // MARK: Computed

    var plantsNeedingWater: [Plant] { plants.filter { $0.needsWatering } }
    var healthyPlants: [Plant] { plants.filter { !$0.needsWatering } }
    var criticalPlants: [Plant] { plants.filter { $0.healthStatus == "critical" } }

    // MARK: Load

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if plants.isEmpty, let cached = ServiceCache.load([Plant].self, entity: "plants", propertyId: propertyId) {
            plants = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            plants = try await PropertyRepo.fetch(table: "plants", propertyId: propertyId,
                                                  scope: .strict, ascending: true, limit: 500)
            ServiceCache.save(plants, entity: "plants", propertyId: propertyId)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    // MARK: CRUD

    func add(_ payload: NewPlantPayload) async throws -> Plant {
        let inserted: Plant = try await supabase
            .from("plants")
            .insert(payload)
            .select().single().execute().value
        plants.append(inserted)
        return inserted
    }

    func update(_ plant: Plant) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let upd = PlantUpdate(
            name: plant.name, species: plant.species, location: plant.location,
            wateringIntervalDays: plant.wateringIntervalDays,
            healthStatus: plant.healthStatus, notes: plant.notes,
            emoji: plant.emoji, updatedAt: now,
            info: PlantGeneralInfo(from: plant)
        )
        do {
            let updated: Plant = try await supabase
                .from("plants").update(upd)
                .eq("id", value: plant.id.uuidString)
                .select().single().execute().value
            if let i = plants.firstIndex(where: { $0.id == plant.id }) { plants[i] = updated }
        } catch { self.error = error.localizedDescription }
    }

    func markWatered(_ plant: Plant) async {
        let neededWater = plant.needsWatering
        let now = ISO8601DateFormatter().string(from: Date())
        let upd = PlantWateringUpdate(lastWateredAt: now, updatedAt: now)
        if let i = plants.firstIndex(where: { $0.id == plant.id }) {
            plants[i].lastWateredAt = now
            plants[i].updatedAt = now
        }
        // Watering-session Live Activity: progress over the plants that still
        // needed water when the session started.
        if neededWater {
            LiveActivityService.shared.plantWatered(
                name: plant.name, remainingAfter: plantsNeedingWater.count)
        }
        do {
            try await supabase
                .from("plants").update(upd)
                .eq("id", value: plant.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ plant: Plant) async {
        plants.removeAll { $0.id == plant.id }
        do {
            try await supabase
                .from("plants").delete()
                .eq("id", value: plant.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }
}

import Foundation
import Observation
import UIKit

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
            self.error = error.recordableDescription
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
        let now = ISODate.string(from: Date())
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
        } catch { self.error = error.recordableDescription }
    }

    /// Links a plant to (or, with nil, unlinks it from) its `plant_species`
    /// encyclopedia entry. Mirrors `markWatered`: a focused single-column
    /// update that leaves every other field untouched.
    func linkSpecies(_ speciesId: UUID?, for plant: Plant) async {
        let now = ISODate.string(from: Date())
        let upd = PlantSpeciesLink(speciesId: speciesId, updatedAt: now)
        if let i = plants.firstIndex(where: { $0.id == plant.id }) {
            plants[i].speciesId = speciesId
            plants[i].updatedAt = now
        }
        do {
            try await supabase
                .from("plants").update(upd)
                .eq("id", value: plant.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    func markWatered(_ plant: Plant) async {
        let neededWater = plant.needsWatering
        let now = ISODate.string(from: Date())
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
        // The real watering, donated so Siri Suggestions learn the routine.
        SiriDonations.plantWatered(id: plant.id, name: plant.name, emoji: plant.emoji)
        do {
            try await supabase
                .from("plants").update(upd)
                .eq("id", value: plant.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    /// Persists a freshly computed Plant Health Score (P6). Focused single-column
    /// write (mirrors `markWatered`) so no other field is touched; updates the
    /// local array so the widget/watch catalog picks it up on the next snapshot.
    /// A no-op when the score is unchanged, to avoid needless writes on re-open.
    func saveHealthScore(_ score: Int, for plant: Plant) async {
        guard plant.healthScore != score else { return }
        let now = ISODate.string(from: Date())
        if let i = plants.firstIndex(where: { $0.id == plant.id }) {
            plants[i].healthScore = score
            plants[i].healthScoreAt = now
        }
        do {
            try await supabase
                .from("plants").update(PlantHealthScoreUpdate(healthScore: score, healthScoreAt: now))
                .eq("id", value: plant.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    /// Uploads the plant's hero photo through the canonical property-imagery
    /// path (`documents` bucket — the one `StorageImage` on the plant cards
    /// already resolves and signs) and persists it as `photo_url`. Focused
    /// single-column update, like `markWatered`. Best-effort: the plant is
    /// already saved when this runs, so a failed upload only surfaces the
    /// error and leaves the emoji fallback in place.
    func setHeroPhoto(_ image: UIImage, for plantId: UUID) async {
        guard let data = image.uploadJPEG(quality: 0.8, maxDimension: 2048) else { return }
        do {
            let url = try await SignedStorage.uploadPublicImage(data, folder: "plants")
            let now = ISODate.string(from: Date())
            if let i = plants.firstIndex(where: { $0.id == plantId }) {
                plants[i].photoUrl = url
                plants[i].updatedAt = now
            }
            try await supabase
                .from("plants").update(PlantHeroPhotoUpdate(photoUrl: url, updatedAt: now))
                .eq("id", value: plantId.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    func delete(_ plant: Plant) async {
        plants.removeAll { $0.id == plant.id }
        do {
            try await supabase
                .from("plants").delete()
                .eq("id", value: plant.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }
}

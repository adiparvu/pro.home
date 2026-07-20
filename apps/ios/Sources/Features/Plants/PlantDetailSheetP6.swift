import SwiftUI

// MARK: - PlantDetailSheet — Level 6 (automations) + Health Score (Plant OS P6)
//
// Two card gateways on the plant page, added alongside the P1–P5 cards and
// following the same pattern: each reads the plant's already-loaded, locally
// owned services and renders honestly (missing data shrinks, never invents).

extension PlantDetailSheet {

    /// The live plant row (picks up watering / score changes made this session).
    private var livePlant: Plant {
        plantService.plants.first(where: { $0.id == plant.id }) ?? plant
    }

    private var linkedSpeciesId: UUID? {
        plantService.plants.first(where: { $0.id == plant.id })?.speciesId ?? plant.speciesId
    }

    // MARK: Health Score

    /// Live sensor readings for the metrics this plant has bound AND that this
    /// device can actually resolve — never a fabricated reading.
    var resolvedSensorReadings: [PlantCareMetric: Double] {
        var out: [PlantCareMetric: Double] = [:]
        for metric in PlantCareMetric.allCases {
            guard let binding = plantSensorService.binding(for: metric),
                  let sensor = IoTService.shared.sensor(forRef: binding.sensorRef),
                  let value = sensor.value else { continue }
            out[metric] = value
        }
        return out
    }

    var computedHealthScore: PlantHealthScore {
        PlantHealthScore.compute(
            plant: livePlant,
            events: eventService.events,
            photos: photoService.photos,
            species: speciesService.species(id: linkedSpeciesId),
            sensorReadings: resolvedSensorReadings)
    }

    @ViewBuilder
    var healthScoreCard: some View {
        PlantHealthScoreCard(score: computedHealthScore)
    }

    /// A cheap fingerprint of every input the score depends on, so the page can
    /// re-persist the score exactly when (and only when) something changed.
    var healthSignature: String {
        let readings = resolvedSensorReadings
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\(Int($0.value.rounded()))" }
            .joined(separator: ",")
        return [
            livePlant.lastWateredAt ?? "-",
            String(eventService.events.count),
            String(photoService.photos.count),
            linkedSpeciesId?.uuidString ?? "-",
            readings,
        ].joined(separator: "|")
    }

    /// Persists the freshly computed score so widgets and the watch glance can
    /// read it. Off the main render path; a no-op when unchanged.
    func persistHealthScore() {
        let score = computedHealthScore
        guard let value = score.value else { return }
        Task { await plantService.saveHealthScore(value, for: livePlant) }
    }

    // MARK: Automations (Level 6)

    @ViewBuilder
    var automationsCard: some View {
        PlantAutomationsCard(plant: plant,
                             service: automationService,
                             sensorService: plantSensorService)
    }
}

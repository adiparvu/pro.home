import Foundation
import Supabase

// MARK: - Fish Service
//
// Manages fish populations, species catalog, and fish journal.
// Follows the same pattern as PlantService — same persistence layer, same patterns.

@MainActor
final class FishService: ObservableObject {

    // MARK: Published

    @Published private(set) var populations: [FishPopulation] = []
    @Published private(set) var journalEntries: [FishJournalEntry] = []
    @Published private(set) var isLoading = false

    private let db = SupabaseClient.shared

    // MARK: Built-in Species Catalog
    //
    // Bundled species — no network required. Covers common pond fish.
    // Extended via fish_species Supabase table for user-added species.

    let builtInSpecies: [FishSpecies] = [
        FishSpecies(
            id: "cyprinus-carpio-koi",
            commonName: "Koi Carp",
            latinName: "Cyprinus carpio",
            icon: "fish.fill",
            minTempC: 5, maxTempC: 30, idealTempC: 22,
            minPh: 7.0, maxPh: 8.5,
            minDissolvedOxygen: 6.0,
            avgLengthCm: 60, avgWeightKg: 3.5,
            category: .koi,
            notes: "pH 7.0–8.5. Temperature 15–25°C optimal. Sensitive to ammonia."
        ),
        FishSpecies(
            id: "carassius-auratus",
            commonName: "Goldfish",
            latinName: "Carassius auratus",
            icon: "fish.fill",
            minTempC: 4, maxTempC: 28, idealTempC: 20,
            minPh: 6.5, maxPh: 8.5,
            minDissolvedOxygen: 5.0,
            avgLengthCm: 20, avgWeightKg: 0.3,
            category: .goldfish,
            notes: "Hardy. Tolerates wider temperature range than koi."
        ),
        FishSpecies(
            id: "oncorhynchus-mykiss",
            commonName: "Rainbow Trout",
            latinName: "Oncorhynchus mykiss",
            icon: "fish.fill",
            minTempC: 6, maxTempC: 20, idealTempC: 14,
            minPh: 6.5, maxPh: 8.0,
            minDissolvedOxygen: 9.0,
            avgLengthCm: 45, avgWeightKg: 1.5,
            category: .trout,
            notes: "Requires cold, well-oxygenated water. DO must stay above 7 mg/L."
        ),
        FishSpecies(
            id: "oreochromis-niloticus",
            commonName: "Nile Tilapia",
            latinName: "Oreochromis niloticus",
            icon: "fish.fill",
            minTempC: 20, maxTempC: 35, idealTempC: 28,
            minPh: 6.5, maxPh: 8.5,
            minDissolvedOxygen: 4.0,
            avgLengthCm: 35, avgWeightKg: 1.2,
            category: .tilapia,
            notes: "Tropical. Dies below 10°C. High disease resistance."
        ),
        FishSpecies(
            id: "ictalurus-punctatus",
            commonName: "Channel Catfish",
            latinName: "Ictalurus punctatus",
            icon: "fish.fill",
            minTempC: 10, maxTempC: 32, idealTempC: 25,
            minPh: 6.5, maxPh: 8.5,
            minDissolvedOxygen: 4.0,
            avgLengthCm: 55, avgWeightKg: 2.0,
            category: .catfish,
            notes: "Tolerates low DO better than most species."
        ),
        FishSpecies(
            id: "micropterus-salmoides",
            commonName: "Largemouth Bass",
            latinName: "Micropterus salmoides",
            icon: "fish.fill",
            minTempC: 8, maxTempC: 30, idealTempC: 22,
            minPh: 6.5, maxPh: 8.5,
            minDissolvedOxygen: 5.0,
            avgLengthCm: 50, avgWeightKg: 2.5,
            category: .bass,
            notes: "Predatory. Do not stock with small fish."
        ),
        FishSpecies(
            id: "cyprinus-carpio-common",
            commonName: "Common Carp",
            latinName: "Cyprinus carpio",
            icon: "fish.fill",
            minTempC: 3, maxTempC: 32, idealTempC: 22,
            minPh: 6.5, maxPh: 9.0,
            minDissolvedOxygen: 3.0,
            avgLengthCm: 60, avgWeightKg: 4.0,
            category: .carp,
            notes: "Extremely hardy. Can tolerate poor water quality."
        )
    ]

    // MARK: Load

    func loadPopulations(for pondId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            populations = try await db
                .from("fish_populations")
                .select()
                .eq("pond_id", value: pondId.uuidString)
                .order("added_at", ascending: false)
                .execute()
                .value
        } catch {
            // Silent — empty state shown in UI
        }
    }

    func loadJournal(for pondId: UUID, limit: Int = 50) async throws -> [FishJournalEntry] {
        let entries: [FishJournalEntry] = try await db
            .from("fish_journal")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .order("recorded_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        journalEntries = entries
        return entries
    }

    // MARK: Add / Update Population

    func addPopulation(_ population: FishPopulation) async throws {
        struct Payload: Codable {
            let pondId: String
            let speciesId: String
            let estimatedCount: Int
            let averageLengthCm: Double?
            let averageWeightKg: Double?
            let colorVariety: String?
            let sourceNotes: String?
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case pondId = "pond_id"
                case speciesId = "species_id"
                case estimatedCount = "estimated_count"
                case averageLengthCm = "average_length_cm"
                case averageWeightKg = "average_weight_kg"
                case colorVariety = "color_variety"
                case sourceNotes = "source_notes"
                case notes
            }
        }
        let payload = Payload(
            pondId: population.pondId.uuidString,
            speciesId: population.speciesId,
            estimatedCount: population.estimatedCount,
            averageLengthCm: population.averageLengthCm,
            averageWeightKg: population.averageWeightKg,
            colorVariety: population.colorVariety,
            sourceNotes: population.sourceNotes,
            notes: population.notes
        )
        let created: FishPopulation = try await db
            .from("fish_populations")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        populations.append(created)

        // Auto-log stocking event
        try await logEvent(FishJournalEntry(
            pondId: population.pondId,
            event: .stocking,
            count: population.estimatedCount,
            speciesId: population.speciesId,
            notes: population.sourceNotes
        ))
    }

    func updateCount(populationId: UUID, newCount: Int) async throws {
        struct Payload: Codable {
            let estimatedCount: Int
            enum CodingKeys: String, CodingKey {
                case estimatedCount = "estimated_count"
            }
        }
        try await db
            .from("fish_populations")
            .update(Payload(estimatedCount: newCount))
            .eq("id", value: populationId.uuidString)
            .execute()
        if let idx = populations.firstIndex(where: { $0.id == populationId }) {
            populations[idx].estimatedCount = newCount
        }
    }

    func removePopulation(_ population: FishPopulation) async throws {
        try await db
            .from("fish_populations")
            .delete()
            .eq("id", value: population.id.uuidString)
            .execute()
        populations.removeAll { $0.id == population.id }
    }

    // MARK: Journal

    func logEvent(_ entry: FishJournalEntry) async throws {
        struct Payload: Codable {
            let pondId: String
            let event: String
            let count: Int?
            let speciesId: String?
            let notes: String?
            let recordedAt: String

            enum CodingKeys: String, CodingKey {
                case pondId = "pond_id"
                case event, count
                case speciesId = "species_id"
                case notes
                case recordedAt = "recorded_at"
            }
        }
        let payload = Payload(
            pondId: entry.pondId.uuidString,
            event: entry.event.rawValue,
            count: entry.count,
            speciesId: entry.speciesId,
            notes: entry.notes,
            recordedAt: ISO8601DateFormatter().string(from: entry.recordedAt)
        )
        let created: FishJournalEntry = try await db
            .from("fish_journal")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        journalEntries.insert(created, at: 0)
    }

    // MARK: Species Lookup

    func species(id: String) -> FishSpecies? {
        builtInSpecies.first(where: { $0.id == id })
    }

    func species(matching query: String) -> [FishSpecies] {
        guard !query.isEmpty else { return builtInSpecies }
        let q = query.lowercased()
        return builtInSpecies.filter {
            $0.commonName.lowercased().contains(q) ||
            $0.latinName.lowercased().contains(q)
        }
    }

    // MARK: Total Fish Count

    var totalFishCount: Int {
        populations.reduce(0) { $0 + $1.estimatedCount }
    }

    // MARK: Biomass Estimate (kg)

    func estimatedBiomassKg(in populations: [FishPopulation]? = nil) -> Double {
        let pops = populations ?? self.populations
        return pops.reduce(0.0) { sum, pop in
            let weight = species(id: pop.speciesId)?.avgWeightKg ?? 0.5
            return sum + (weight * Double(pop.estimatedCount))
        }
    }
}

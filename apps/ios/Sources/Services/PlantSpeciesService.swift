import Foundation
import Observation
import Supabase

// MARK: - Plant species knowledge base (Plant OS P2)
//
// Loads the shared, read-only `plant_species` encyclopedia. The corpus is a
// global catalog (not property-scoped): every authenticated user reads the
// same rows, so there is no per-property cache key — we simply fetch once and
// keep the list in memory for the session. Mirrors the @Observable, load-on-
// task style of PlantPhotoService / DocumentFilesService.

@MainActor
@Observable
final class PlantSpeciesService {
    private(set) var species: [PlantSpeciesEntry] = []
    var isLoading = false

    /// Fetches the whole catalog ordered by common name. Idempotent and cheap
    /// to call from a view's `.task`; skips the network round-trip once loaded.
    func loadAll() async {
        guard species.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        species = (try? await supabase.from("plant_species")
            .select()
            .order("common_name", ascending: true)
            .execute().value) ?? []
    }

    /// Resolves a plant's linked encyclopedia entry.
    func species(id: UUID?) -> PlantSpeciesEntry? {
        guard let id else { return nil }
        return species.first { $0.id == id }
    }

    /// Case- and diacritic-insensitive search across the common name, Latin
    /// name, synonyms and Romanian common names.
    func search(_ q: String) -> [PlantSpeciesEntry] {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return species }
        return species.filter { entry in
            if entry.displayName.matchesSearch(query) { return true }
            if let latin = entry.latinName, latin.matchesSearch(query) { return true }
            if entry.synonyms?.contains(where: { $0.matchesSearch(query) }) == true { return true }
            if entry.commonNamesRo?.contains(where: { $0.matchesSearch(query) }) == true { return true }
            return false
        }
    }
}

import Foundation
import Observation
import SwiftUI
import Supabase

// MARK: - Plant ailment knowledge base + guided diagnosis (Plant OS P4)
//
// Loads the shared, read-only `plant_ailments` catalog and the
// `plant_species_ailments` susceptibility links. Like PlantSpeciesService this
// is a global corpus (not property-scoped): fetch once, keep in memory for the
// session. Diagnosis is fully offline and deterministic — a transparent
// symptom-coverage score, optionally nudged by the linked species'
// susceptibility. Nothing here fabricates a match or a confidence figure.

@MainActor
@Observable
final class PlantAilmentService {
    private(set) var ailments: [PlantAilment] = []
    private(set) var links: [PlantSpeciesAilmentLink] = []
    var isLoading = false

    /// Fetches the whole catalog + susceptibility links. Idempotent and cheap
    /// to call from a view's `.task`; skips the round-trip once loaded.
    func loadAll() async {
        guard ailments.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        async let ailmentsFetch: [PlantAilment] = (try? await supabase
            .from("plant_ailments")
            .select()
            .order("common_name", ascending: true)
            .execute().value) ?? []
        async let linksFetch: [PlantSpeciesAilmentLink] = (try? await supabase
            .from("plant_species_ailments")
            .select()
            .execute().value) ?? []

        ailments = await ailmentsFetch
        links = await linksFetch
    }

    /// Resolves an ailment by id (e.g. from a susceptibility link).
    func ailment(id: UUID) -> PlantAilment? {
        ailments.first { $0.id == id }
    }

    /// Case- and diacritic-insensitive search across the common and Latin name.
    /// Results are ordered by the localized common name so the reference list
    /// reads alphabetically in the device language, not just the English order
    /// the server sorts by.
    func search(_ q: String) -> [PlantAilment] {
        let query = q.trimmingCharacters(in: .whitespaces)
        let base: [PlantAilment]
        if query.isEmpty {
            base = ailments
        } else {
            base = ailments.filter { a in
                if a.localizedCommonName.matchesSearch(query) { return true }
                if a.commonName.matchesSearch(query) { return true }
                if let latin = a.latinName, latin.matchesSearch(query) { return true }
                return false
            }
        }
        return base.sorted {
            $0.localizedCommonName.localizedCaseInsensitiveCompare($1.localizedCommonName) == .orderedAscending
        }
    }

    // MARK: Susceptibility

    /// Ailment ids the given species is catalogued as susceptible to.
    func susceptibleAilmentIds(forSpecies speciesId: UUID?) -> Set<UUID> {
        guard let speciesId else { return [] }
        return Set(links.filter { $0.speciesId == speciesId }.map(\.ailmentId))
    }

    /// Ailments (with their susceptibility note) linked to a species — powers
    /// the "known risks for this plant" strip on the health page.
    func susceptibilities(forSpecies speciesId: UUID?) -> [(ailment: PlantAilment, note: String?)] {
        guard let speciesId else { return [] }
        return links
            .filter { $0.speciesId == speciesId }
            .compactMap { link in
                guard let a = ailment(id: link.ailmentId) else { return nil }
                return (a, link.localizedNote)
            }
            .sorted { $0.ailment.localizedCommonName < $1.ailment.localizedCommonName }
    }

    // MARK: - Guided diagnosis (offline, deterministic decision tree)

    /// One ranked diagnosis candidate. `matchedTags` is the transparent
    /// evidence: exactly which selected symptoms this ailment explains.
    struct DiagnosisMatch: Identifiable, Hashable {
        let ailment: PlantAilment
        let matchedTags: [String]     // selected tags this ailment covers
        let selectedCount: Int        // how many symptoms the user selected
        let susceptible: Bool         // linked species flagged this ailment

        var id: UUID { ailment.id }

        /// How many of the user's selected symptoms this ailment explains.
        var matchedCount: Int { matchedTags.count }

        /// Fraction of the user's selected symptoms this ailment explains,
        /// 0...1. A transparent, derived figure — not an AI confidence score.
        var coverage: Double {
            guard selectedCount > 0 else { return 0 }
            return Double(matchedCount) / Double(selectedCount)
        }

        /// Ranking score: symptom coverage plus a small susceptibility nudge,
        /// so a well-established species risk breaks ties toward the likelier
        /// culprit without ever manufacturing a match on its own.
        var score: Double {
            Double(matchedCount) + (susceptible ? 0.5 : 0)
        }

        /// Coarse, honest strength band for the UI.
        var strengthKey: LocalizedStringKey {
            switch coverage {
            case 0.75...:    return "plant_health_strength_strong"
            case 0.4..<0.75: return "plant_health_strength_partial"
            default:         return "plant_health_strength_weak"
            }
        }
    }

    /// Ranks ailments by how many of the selected symptom tags each explains,
    /// with a small boost for ailments the plant's linked species is known to
    /// be susceptible to. Only ailments matching at least one selected symptom
    /// are returned. Deterministic and fully offline.
    ///
    /// - Parameters:
    ///   - tags: the symptom tags the user ticked.
    ///   - speciesId: the plant's linked species, if any (for the boost only).
    func diagnose(tags: Set<String>, speciesId: UUID? = nil) -> [DiagnosisMatch] {
        guard !tags.isEmpty else { return [] }
        let susceptibleIds = susceptibleAilmentIds(forSpecies: speciesId)
        let selectedCount = tags.count

        return ailments.compactMap { ailment -> DiagnosisMatch? in
            let matched = ailment.tagSet.intersection(tags)
            guard !matched.isEmpty else { return nil }
            // Preserve catalog order of tags for stable, readable display.
            let orderedMatched = PlantSymptomCatalog.all
                .map(\.tag)
                .filter { matched.contains($0) }
            return DiagnosisMatch(
                ailment: ailment,
                matchedTags: orderedMatched,
                selectedCount: selectedCount,
                susceptible: susceptibleIds.contains(ailment.id)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            // Tie-break: fewer unrelated symptoms (broader match) first, then
            // name for a fully stable, deterministic order.
            if lhs.matchedCount != rhs.matchedCount { return lhs.matchedCount > rhs.matchedCount }
            return lhs.ailment.localizedCommonName < rhs.ailment.localizedCommonName
        }
    }
}

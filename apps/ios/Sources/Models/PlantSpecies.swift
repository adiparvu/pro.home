import Foundation

// MARK: - Plant species (encyclopedia entry, Plant OS P2)
//
// A row of the shared, read-mostly `plant_species` knowledge base. Unlike the
// in-app `PlantSpecies` picker catalog (Features/Plants/PlantSpeciesCatalog),
// which is a lightweight, hand-typed strip used to prefill the Add-Plant form,
// this is the persisted encyclopedia entry a plant links to via `species_id`.
// The two intentionally coexist: the catalog seeds the form, this backs the
// botanical profile page. Named `PlantSpeciesEntry` to avoid colliding with
// that existing catalog struct.
//
// Honesty law: every field is optional. A plant's page renders only the
// sections that are actually populated — missing data never becomes a
// placeholder.

/// One question/answer pair in a species' FAQ (`faq` jsonb column).
struct PlantFAQ: Codable, Hashable {
    let q: String
    let a: String
}

struct PlantSpeciesEntry: Identifiable, Codable, Hashable {
    let id: UUID

    // identification
    var slug: String
    var commonName: String?
    var latinName: String?
    var synonyms: [String]?
    var family: String?
    var genus: String?
    var species: String?
    var commonNamesRo: [String]?

    // natural habitat
    var origin: String?
    var altitude: String?
    var nativeTemp: String?
    var nativeHumidity: String?
    var habitatType: String?

    // characteristics
    var maxHeight: String?
    var maxWidth: String?
    var growthRate: String?
    var lifespan: String?
    var evergreen: Bool?
    var floweringPeriod: String?
    var fruiting: String?
    var fragrance: String?

    // leaves
    var leafSize: String?
    var leafShape: String?
    var leafColour: String?
    var leafTexture: String?
    var variegation: String?
    var gloss: String?

    // roots
    var rootType: String?

    // guides & lore
    var propagation: String?
    var pruning: String?
    var seasonalChecklist: [String]?
    var annualCalendar: [String: String]?
    var faq: [PlantFAQ]?
    var myths: [String]?
    var curiosities: [String]?
    var sources: [String]?

    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, synonyms, family, genus, species, origin, altitude
        case habitatType      = "habitat_type"
        case commonName       = "common_name"
        case latinName        = "latin_name"
        case commonNamesRo    = "common_names_ro"
        case nativeTemp       = "native_temp"
        case nativeHumidity   = "native_humidity"
        case maxHeight        = "max_height"
        case maxWidth         = "max_width"
        case growthRate       = "growth_rate"
        case lifespan, evergreen
        case floweringPeriod  = "flowering_period"
        case fruiting, fragrance
        case leafSize         = "leaf_size"
        case leafShape        = "leaf_shape"
        case leafColour       = "leaf_colour"
        case leafTexture      = "leaf_texture"
        case variegation, gloss
        case rootType         = "root_type"
        case propagation, pruning
        case seasonalChecklist = "seasonal_checklist"
        case annualCalendar   = "annual_calendar"
        case faq, myths, curiosities, sources
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
    }

    /// Best available display label — common name, then Latin, then the slug.
    var displayName: String {
        commonName ?? latinName ?? slug
    }
}

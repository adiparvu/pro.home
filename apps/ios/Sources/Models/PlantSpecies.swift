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

    // care requirements (P3) — numeric bands compared against live sensors.
    // Every field optional: only populated ones render, none are fabricated.
    var lightLuxMin: Int?
    var lightLuxIdeal: Int?
    var lightLuxMax: Int?
    var tempIdealMin: Double?
    var tempIdealMax: Double?
    var tempAcceptedMin: Double?
    var tempAcceptedMax: Double?
    var tempDangerLow: Double?
    var tempDangerHigh: Double?
    var humidityIdealMin: Int?
    var humidityIdealMax: Int?
    var humidityAcceptedMin: Int?
    var humidityAcceptedMax: Int?
    var phMin: Double?
    var phIdeal: Double?
    var phMax: Double?
    var substrateMix: [String: Int]?
    var waterSpring: String?
    var waterSummer: String?
    var waterAutumn: String?
    var waterWinter: String?
    var waterTopCm: Int?
    var fertilizerType: String?
    var fertilizerNpk: String?
    var fertilizerFreq: String?
    var fertilizerMonths: [String]?
    var fertilizerWinterPause: Bool?
    var repotInterval: String?
    var repotPotStepCm: Int?
    var repotPotMaxCm: Int?
    var repotPeriod: String?

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
        case lightLuxMin      = "light_lux_min"
        case lightLuxIdeal    = "light_lux_ideal"
        case lightLuxMax      = "light_lux_max"
        case tempIdealMin     = "temp_ideal_min"
        case tempIdealMax     = "temp_ideal_max"
        case tempAcceptedMin  = "temp_accepted_min"
        case tempAcceptedMax  = "temp_accepted_max"
        case tempDangerLow    = "temp_danger_low"
        case tempDangerHigh   = "temp_danger_high"
        case humidityIdealMin    = "humidity_ideal_min"
        case humidityIdealMax    = "humidity_ideal_max"
        case humidityAcceptedMin = "humidity_accepted_min"
        case humidityAcceptedMax = "humidity_accepted_max"
        case phMin            = "ph_min"
        case phIdeal          = "ph_ideal"
        case phMax            = "ph_max"
        case substrateMix     = "substrate_mix"
        case waterSpring      = "water_spring"
        case waterSummer      = "water_summer"
        case waterAutumn      = "water_autumn"
        case waterWinter      = "water_winter"
        case waterTopCm       = "water_topcm"
        case fertilizerType   = "fertilizer_type"
        case fertilizerNpk    = "fertilizer_npk"
        case fertilizerFreq   = "fertilizer_freq"
        case fertilizerMonths = "fertilizer_months"
        case fertilizerWinterPause = "fertilizer_winter_pause"
        case repotInterval    = "repot_interval"
        case repotPotStepCm   = "repot_pot_step_cm"
        case repotPotMaxCm    = "repot_pot_max_cm"
        case repotPeriod      = "repot_period"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
    }

    /// Best available display label — common name, then Latin, then the slug.
    var displayName: String {
        commonName ?? latinName ?? slug
    }

    // MARK: Care data (P3)

    /// True when the species carries at least one numeric care requirement, so
    /// the care card can show a gentle empty state instead of an empty shell
    /// for species whose care fields are all still NULL.
    var hasCareData: Bool {
        hasLightData || hasTempData || hasHumidityData || hasPhData
            || substrateMix?.isEmpty == false
            || hasWaterData
            || fertilizerType != nil || fertilizerFreq != nil || fertilizerNpk != nil
            || repotInterval != nil || repotPeriod != nil || repotPotStepCm != nil
    }

    /// A light band exists when at least the ideal is known.
    var hasLightData: Bool { lightLuxIdeal != nil || lightLuxMin != nil || lightLuxMax != nil }
    var hasTempData: Bool { tempIdealMin != nil || tempIdealMax != nil || tempDangerLow != nil || tempDangerHigh != nil }
    var hasHumidityData: Bool { humidityIdealMin != nil || humidityIdealMax != nil || humidityAcceptedMin != nil || humidityAcceptedMax != nil }
    var hasPhData: Bool { phMin != nil || phIdeal != nil || phMax != nil }
    var hasWaterData: Bool {
        waterSpring != nil || waterSummer != nil || waterAutumn != nil
            || waterWinter != nil || waterTopCm != nil
    }
}

import SwiftUI

// MARK: - Plant

struct Plant: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var name: String
    var species: String?
    var location: String?
    var lastWateredAt: String?
    var wateringIntervalDays: Int
    var healthStatus: String
    var notes: String?
    var emoji: String
    var photoUrl: String?
    var createdAt: String
    var updatedAt: String

    // ── General information (migration 122, Plant OS P1) ─────────────────────
    var nickname: String?
    var latinName: String?
    var botanicalFamily: String?
    var genus: String?
    var cultivar: String?
    var origin: String?
    var climateZone: String?
    var toxicCats: Bool = false
    var toxicDogs: Bool = false
    var toxicKids: Bool = false
    var placement: String?   // indoor / outdoor / both

    // ── Encyclopedia link (migration 124, Plant OS P2) ───────────────────────
    /// The `plant_species` row this plant links to, if any (its botanical
    /// profile). Set via `PlantService.linkSpecies`, never through the edit
    /// form, so a normal update can't accidentally clear it.
    var speciesId: UUID?

    // ── Plant Health Score (migration 133, Plant OS P6) ──────────────────────
    /// Last computed explainable Health Score (0–100) and when it was computed.
    /// nil = not computed yet (never a fabricated default). Written only by
    /// `PlantService.saveHealthScore` after the plant page computes it from real
    /// inputs, so widgets / the watch glance can read it without recomputing.
    var healthScore: Int?
    var healthScoreAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case name, species, location
        case lastWateredAt        = "last_watered_at"
        case wateringIntervalDays = "watering_interval_days"
        case healthStatus         = "health_status"
        case notes, emoji
        case photoUrl  = "photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case nickname, genus, cultivar, origin, placement
        case latinName        = "latin_name"
        case botanicalFamily  = "botanical_family"
        case climateZone      = "climate_zone"
        case toxicCats        = "toxic_cats"
        case toxicDogs        = "toxic_dogs"
        case toxicKids        = "toxic_kids"
        case speciesId        = "species_id"
        case healthScore      = "health_score"
        case healthScoreAt    = "health_score_at"
    }

    /// The three toxicity flags as an at-a-glance summary.
    var toxicitySummary: [String] {
        var out: [String] = []
        if toxicCats { out.append(String(localized: "plant_tox_cats")) }
        if toxicDogs { out.append(String(localized: "plant_tox_dogs")) }
        if toxicKids { out.append(String(localized: "plant_tox_kids")) }
        return out
    }

    var placementLabel: String? {
        switch placement {
        case "indoor":  return String(localized: "plant_place_indoor")
        case "outdoor": return String(localized: "plant_place_outdoor")
        case "both":    return String(localized: "plant_place_both")
        default:        return nil
        }
    }

    // MARK: Computed

    private func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        return ISODate.date(from: str)
    }

    /// Public parsed last-watered instant (used by the Health Score's watering
    /// discipline factor). nil when the plant has never been watered.
    var lastWateredAtDate: Date? { parseDate(lastWateredAt) }

    var needsWatering: Bool {
        guard let last = parseDate(lastWateredAt) else { return true }
        let next = Calendar.current.date(byAdding: .day, value: wateringIntervalDays, to: last) ?? last
        return next <= Date()
    }

    var daysUntilWatering: Int {
        guard let last = parseDate(lastWateredAt) else { return -wateringIntervalDays }
        let next = Calendar.current.date(byAdding: .day, value: wateringIntervalDays, to: last) ?? last
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: next)).day ?? 0
    }

    var healthColor: Color {
        switch healthStatus {
        case "great":       return Color(red: 0.15, green: 0.80, blue: 0.4)
        case "good":        return Color(red: 0.25, green: 0.72, blue: 0.35)
        case "needs_water": return Color(red: 1.0,  green: 0.62, blue: 0.1)
        case "critical":    return .red
        default:            return .gray
        }
    }

    var healthIcon: String {
        switch healthStatus {
        case "great":       return "checkmark.circle.fill"
        case "good":        return "leaf.fill"
        case "needs_water": return "drop.fill"
        case "critical":    return "exclamationmark.triangle.fill"
        default:            return "leaf.fill"
        }
    }

    var wateringLabel: String {
        if needsWatering { return String(localized: "Needs water") }
        let d = daysUntilWatering
        if d == 0 { return String(localized: "Water today") }
        if d == 1 { return String(localized: "Water tomorrow") }
        return String(localized: "In \(d) days")
    }

    var lastWateredDisplay: String {
        guard let d = parseDate(lastWateredAt) else { return String(localized: "Never") }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        return AppDateDisplay.dayMonth.string(from: d)
    }

    /// "La fiecare N zile" — the one watering-cadence string, localized with
    /// the singular/plural key pair the care-sheet PDF already ships. The
    /// sheets interpolated it verbatim (a ternary of literals types as
    /// String, never LocalizedStringKey), so devices saw raw English.
    static func wateringIntervalDisplay(_ days: Int) -> String {
        String(format: String(localized: days == 1 ? "Every %lld day" : "Every %lld days"), days)
    }

    static let emojiOptions = ["🌿","🌱","🌸","🌺","🌻","🌹","🌷","🌵","🪴","🌾","🍀","🍃","🌳","🌲","🌊","🪸"]

    static let healthOptions: [(id: String, label: String)] = [
        ("great",       "Excellent"),
        ("good",        "Good"),
        ("needs_water", "Needs water"),
        ("critical",    "Critical"),
    ]

    var localizedHealthLabel: String {
        switch healthStatus {
        case "great":       return String(localized: "Excellent")
        case "good":        return String(localized: "Good")
        case "needs_water": return String(localized: "Needs water")
        case "critical":    return String(localized: "Critical")
        default:            return healthStatus
        }
    }
}

// MARK: - Payloads

/// The Plant OS P1 general-information fields, bundled so the payloads stay
/// readable. All optional; a plant with none set writes exactly like before.
struct PlantGeneralInfo: Encodable, Equatable {
    var nickname: String?
    var latinName: String?
    var botanicalFamily: String?
    var genus: String?
    var cultivar: String?
    var origin: String?
    var climateZone: String?
    var toxicCats = false
    var toxicDogs = false
    var toxicKids = false
    var placement: String?

    enum CodingKeys: String, CodingKey {
        case nickname, genus, cultivar, origin, placement
        case latinName       = "latin_name"
        case botanicalFamily = "botanical_family"
        case climateZone     = "climate_zone"
        case toxicCats       = "toxic_cats"
        case toxicDogs       = "toxic_dogs"
        case toxicKids       = "toxic_kids"
    }

    init() {}
    init(from p: Plant) {
        nickname = p.nickname; latinName = p.latinName; botanicalFamily = p.botanicalFamily
        genus = p.genus; cultivar = p.cultivar; origin = p.origin; climateZone = p.climateZone
        toxicCats = p.toxicCats; toxicDogs = p.toxicDogs; toxicKids = p.toxicKids
        placement = p.placement
    }
}

struct NewPlantPayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let name: String
    let species: String?
    let location: String?
    let wateringIntervalDays: Int
    let healthStatus: String
    let notes: String?
    let emoji: String
    let createdAt: String
    let updatedAt: String
    var info = PlantGeneralInfo()

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case name, species, location
        case wateringIntervalDays = "watering_interval_days"
        case healthStatus         = "health_status"
        case notes, emoji
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(propertyId, forKey: .propertyId)
        try c.encode(ownerId, forKey: .ownerId)
        try c.encode(name, forKey: .name)
        try c.encode(species, forKey: .species)
        try c.encode(location, forKey: .location)
        try c.encode(wateringIntervalDays, forKey: .wateringIntervalDays)
        try c.encode(healthStatus, forKey: .healthStatus)
        try c.encode(notes, forKey: .notes)
        try c.encode(emoji, forKey: .emoji)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try info.encode(to: encoder)   // flattens the general-info keys alongside
    }
}

struct PlantUpdate: Encodable {
    let name: String
    let species: String?
    let location: String?
    let wateringIntervalDays: Int
    let healthStatus: String
    let notes: String?
    let emoji: String
    let updatedAt: String
    var info = PlantGeneralInfo()

    enum CodingKeys: String, CodingKey {
        case name, species, location
        case wateringIntervalDays = "watering_interval_days"
        case healthStatus         = "health_status"
        case notes, emoji
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(species, forKey: .species)
        try c.encode(location, forKey: .location)
        try c.encode(wateringIntervalDays, forKey: .wateringIntervalDays)
        try c.encode(healthStatus, forKey: .healthStatus)
        try c.encode(notes, forKey: .notes)
        try c.encode(emoji, forKey: .emoji)
        try c.encode(updatedAt, forKey: .updatedAt)
        try info.encode(to: encoder)
    }
}

// MARK: - Plant photo album (P1)

struct PlantPhoto: Identifiable, Codable, Hashable {
    let id: UUID
    let plantId: UUID
    let propertyId: UUID
    var url: String
    var note: String?
    var takenAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, url, note
        case plantId    = "plant_id"
        case propertyId = "property_id"
        case takenAt    = "taken_at"
        case createdAt  = "created_at"
    }

    var takenDisplay: String {
        guard let d = ISODate.date(from: takenAt) else { return "" }
        return AppDateDisplay.dayMonthYear.string(from: d)
    }
}

struct PlantWateringUpdate: Encodable {
    let lastWateredAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case lastWateredAt = "last_watered_at"
        case updatedAt     = "updated_at"
    }
}

/// Persists the computed Plant Health Score (P6). Focused single-purpose
/// update, like `PlantWateringUpdate`, so the edit form never touches it and a
/// normal save can't overwrite the score.
struct PlantHealthScoreUpdate: Encodable {
    let healthScore: Int
    let healthScoreAt: String

    enum CodingKeys: String, CodingKey {
        case healthScore   = "health_score"
        case healthScoreAt = "health_score_at"
    }
}

/// Persists the plant's hero photo URL after upload. Focused single-purpose
/// update, like `PlantWateringUpdate`, so a normal save can't clobber it.
struct PlantHeroPhotoUpdate: Encodable {
    let photoUrl: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case photoUrl  = "photo_url"
        case updatedAt = "updated_at"
    }
}

/// Links (or unlinks, when nil) a plant to its `plant_species` encyclopedia
/// entry. Kept separate from `PlantUpdate` so the edit form never touches it
/// (mirrors `PlantWateringUpdate`).
struct PlantSpeciesLink: Encodable {
    let speciesId: UUID?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case speciesId = "species_id"
        case updatedAt = "updated_at"
    }

    /// Explicit encoding so a nil id is written as JSON `null` (clearing the
    /// column). The synthesized encoder would use `encodeIfPresent` and omit
    /// the key, which PostgREST reads as "leave unchanged" — the wrong result
    /// for an unlink.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(speciesId, forKey: .speciesId)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

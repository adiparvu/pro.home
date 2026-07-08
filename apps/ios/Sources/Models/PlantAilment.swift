import Foundation
import SwiftUI

// MARK: - Plant ailment (health knowledge base, Plant OS P4)
//
// A row of the shared, read-mostly `plant_ailments` catalog: one common
// houseplant disease, pest or physiological disorder. Like `plant_species`
// this is a GLOBAL, public-read corpus curated by migrations — never written
// from the client.
//
// Honesty law: every optional field renders only when populated. `symptomTags`
// are the normalized keys the offline decision tree matches against; the UI
// presents results as "possible matches", never a definitive diagnosis, and
// shows no fabricated confidence figure.

struct PlantAilment: Identifiable, Codable, Hashable {
    let id: UUID

    var slug: String
    var kind: String                 // disease / pest / disorder
    var commonName: String
    var latinName: String?

    var symptoms: [String]?
    var symptomTags: [String]?
    var affectedParts: [String]?

    var causes: String?
    var treatment: String?
    var prevention: String?
    var severity: String?            // low / moderate / serious
    var sources: [String]?

    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, kind, symptoms, causes, treatment, prevention, severity, sources
        case commonName    = "common_name"
        case latinName     = "latin_name"
        case symptomTags   = "symptom_tags"
        case affectedParts = "affected_parts"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }

    /// Normalized symptom tags as a set for fast decision-tree matching.
    var tagSet: Set<String> { Set(symptomTags ?? []) }

    // MARK: Presentation helpers

    /// Category glyph, keyed off `kind`.
    var kindIcon: String {
        switch kind {
        case "pest":     return "ant.fill"
        case "disease":  return "allergens"
        default:         return "leaf.arrow.triangle.circlepath" // disorder
        }
    }

    /// Localization key for the human-readable kind label.
    var kindLabelKey: LocalizedStringKey {
        switch kind {
        case "pest":     return "plant_health_kind_pest"
        case "disease":  return "plant_health_kind_disease"
        default:         return "plant_health_kind_disorder"
        }
    }

    /// Severity accent colour (design tokens; nil severity is treated neutrally).
    var severityColor: Color {
        switch severity {
        case "serious":  return .brandDanger
        case "moderate": return .brandWarning
        case "low":      return .brandSuccess
        default:         return .secondary
        }
    }

    /// Localization key for the human-readable severity label.
    var severityLabelKey: LocalizedStringKey {
        switch severity {
        case "serious":  return "plant_health_sev_serious"
        case "moderate": return "plant_health_sev_moderate"
        case "low":      return "plant_health_sev_low"
        default:         return "plant_health_sev_unknown"
        }
    }
}

// MARK: - Species ↔ ailment susceptibility link

/// One row of `plant_species_ailments`: a species the catalog considers
/// susceptible to an ailment. Used only to gently boost matches for a plant
/// whose linked species appears here — never to invent a diagnosis.
struct PlantSpeciesAilmentLink: Identifiable, Codable, Hashable {
    let id: UUID
    var speciesId: UUID
    var ailmentId: UUID
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, note
        case speciesId = "species_id"
        case ailmentId = "ailment_id"
    }
}

// MARK: - Symptom-tag catalog (guided diagnosis checklist)
//
// The fixed, offline set of symptoms a user can tick. Each option carries a
// normalized `tag` (matched against `PlantAilment.symptomTags`), an SF Symbol
// and a localization key. Grouped for a scannable checklist. This is the
// single source of truth the decision tree and the UI share.

/// A logical grouping of symptom options in the checklist.
enum PlantSymptomGroup: String, CaseIterable, Identifiable {
    case leafAppearance
    case leafSurface
    case pests
    case rootsStemSoil

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .leafAppearance: return "plant_health_grp_leaf_appearance"
        case .leafSurface:    return "plant_health_grp_leaf_surface"
        case .pests:          return "plant_health_grp_pests"
        case .rootsStemSoil:  return "plant_health_grp_roots"
        }
    }

    var icon: String {
        switch self {
        case .leafAppearance: return "leaf"
        case .leafSurface:    return "sparkles"
        case .pests:          return "ant"
        case .rootsStemSoil:  return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// One tappable symptom in the guided-diagnosis checklist.
struct PlantSymptomTag: Identifiable, Hashable {
    let tag: String                  // matches PlantAilment.symptomTags
    let labelKey: LocalizedStringKey
    let icon: String
    let group: PlantSymptomGroup

    var id: String { tag }

    // `LocalizedStringKey` isn't Hashable, so synthesis can't apply. Identity
    // is fully carried by `tag`, so hash and compare on that alone.
    static func == (lhs: PlantSymptomTag, rhs: PlantSymptomTag) -> Bool { lhs.tag == rhs.tag }
    func hash(into hasher: inout Hasher) { hasher.combine(tag) }
}

enum PlantSymptomCatalog {
    /// The complete, ordered catalog. Every `tag` here is a key some seeded
    /// ailment references; every ailment tag is represented here.
    static let all: [PlantSymptomTag] = [
        // Leaf appearance / colour
        .init(tag: "yellow_leaves",   labelKey: "plant_sym_yellow_leaves",   icon: "leaf.fill",                 group: .leafAppearance),
        .init(tag: "brown_tips",      labelKey: "plant_sym_brown_tips",      icon: "leaf",                      group: .leafAppearance),
        .init(tag: "brown_patches",   labelKey: "plant_sym_brown_patches",   icon: "leaf",                      group: .leafAppearance),
        .init(tag: "black_spots",     labelKey: "plant_sym_black_spots",     icon: "circle.fill",               group: .leafAppearance),
        .init(tag: "white_spots",     labelKey: "plant_sym_white_spots",     icon: "circle.dotted",             group: .leafAppearance),
        .init(tag: "white_powder",    labelKey: "plant_sym_white_powder",    icon: "cloud.fill",                group: .leafAppearance),
        .init(tag: "pale_new_growth", labelKey: "plant_sym_pale_new_growth", icon: "leaf.arrow.triangle.circlepath", group: .leafAppearance),
        .init(tag: "bleached_leaves", labelKey: "plant_sym_bleached_leaves", icon: "sun.max.fill",              group: .leafAppearance),

        // Leaf surface / texture
        .init(tag: "wilting",          labelKey: "plant_sym_wilting",          icon: "arrow.down",              group: .leafSurface),
        .init(tag: "curling_distorted", labelKey: "plant_sym_curling_distorted", icon: "tornado",              group: .leafSurface),
        .init(tag: "crispy_dry",       labelKey: "plant_sym_crispy_dry",       icon: "flame",                  group: .leafSurface),
        .init(tag: "sticky_residue",   labelKey: "plant_sym_sticky_residue",   icon: "drop.fill",              group: .leafSurface),
        .init(tag: "black_coating",    labelKey: "plant_sym_black_coating",    icon: "smoke.fill",             group: .leafSurface),
        .init(tag: "silvery_streaks",  labelKey: "plant_sym_silvery_streaks",  icon: "scribble.variable",      group: .leafSurface),
        .init(tag: "blisters_underside", labelKey: "plant_sym_blisters_underside", icon: "circlebadge.2",     group: .leafSurface),

        // Visible pests
        .init(tag: "webbing",          labelKey: "plant_sym_webbing",          icon: "line.diagonal",          group: .pests),
        .init(tag: "white_cottony",    labelKey: "plant_sym_white_cottony",    icon: "cloud",                  group: .pests),
        .init(tag: "bumps_on_stems",   labelKey: "plant_sym_bumps_on_stems",   icon: "circlebadge",            group: .pests),
        .init(tag: "clustered_insects", labelKey: "plant_sym_clustered_insects", icon: "aqi.medium",          group: .pests),
        .init(tag: "flying_insects",   labelKey: "plant_sym_flying_insects",   icon: "ant.fill",               group: .pests),
        .init(tag: "gnats_from_soil",  labelKey: "plant_sym_gnats_from_soil",  icon: "aqi.low",                group: .pests),

        // Roots / stem / soil
        .init(tag: "soft_black_roots", labelKey: "plant_sym_soft_black_roots", icon: "point.3.connected.trianglepath.dotted", group: .rootsStemSoil),
        .init(tag: "mushy_stem_base",  labelKey: "plant_sym_mushy_stem_base",  icon: "exclamationmark.triangle.fill", group: .rootsStemSoil),
        .init(tag: "soil_stays_wet",   labelKey: "plant_sym_soil_stays_wet",   icon: "drop.triangle.fill",     group: .rootsStemSoil),
        .init(tag: "stunted_growth",   labelKey: "plant_sym_stunted_growth",   icon: "arrow.down.right.and.arrow.up.left", group: .rootsStemSoil),
    ]

    /// Options in a given group, preserving catalog order.
    static func inGroup(_ group: PlantSymptomGroup) -> [PlantSymptomTag] {
        all.filter { $0.group == group }
    }

    /// Resolves a raw tag key to its catalog entry (for rendering matched tags).
    static func entry(for tag: String) -> PlantSymptomTag? {
        all.first { $0.tag == tag }
    }
}

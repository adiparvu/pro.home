import SwiftUI

// MARK: - Space kind (Estate OS E1)
//
// What a Digital Twin zone IS as a lived-in space — the classification the
// estate surfaces (the dashboard's "Domeniul" strip, the space detail page)
// dress themselves by: one SF Symbol, one localized title, one warm scene
// gradient per kind. Persisted per zone in `property_zones.space_kind`
// (nullable); zones never classified resolve through a deliberately
// conservative name/icon heuristic and otherwise stay `.custom` — the UI
// never guesses a kind it can't justify.

enum SpaceKind: String, CaseIterable, Identifiable {
    case house, garden, pond, forest, greenhouse, garage, basement, custom

    var id: String { rawValue }

    /// The kind's SF Symbol — used wherever the zone has no stored icon of
    /// its own to show (strip thumbnails without a photo, the kind picker).
    var icon: String {
        switch self {
        case .house:      return "house.fill"
        case .garden:     return "leaf.fill"
        case .pond:       return "water.waves"
        case .forest:     return "tree.fill"
        case .greenhouse: return "thermometer.sun.fill"
        case .garage:     return "door.garage.closed"
        case .basement:   return "stairs"
        case .custom:     return "square.dashed"
        }
    }

    /// Localization key ("space_kind_*") for the kind's display title.
    var titleKey: String { "space_kind_\(rawValue)" }

    /// Resolved display title through the app's string catalog.
    var title: String { String(localized: String.LocalizationValue(titleKey)) }

    /// The kind's warm scene gradient — the backdrop for spaces without a
    /// photo. Tokens live in `SmartHomeTheme` with the rest of the warm skin.
    var sceneGradient: LinearGradient {
        switch self {
        case .house, .custom: return SmartHomeTheme.fallbackGradient
        case .garden:         return SmartHomeTheme.sceneGardenGradient
        case .pond:           return SmartHomeTheme.scenePondGradient
        case .forest:         return SmartHomeTheme.sceneForestGradient
        case .greenhouse:     return SmartHomeTheme.sceneGreenhouseGradient
        case .garage:         return SmartHomeTheme.sceneGarageGradient
        case .basement:       return SmartHomeTheme.sceneBasementGradient
        }
    }

    // MARK: Heuristic (conservative, RO + EN)

    /// Infers a kind from the zone's own words (its name, then its stored
    /// SF Symbol). Substring match on the diacritic/case-folded name — the
    /// stems are chosen so "Grădina de legume", "Iazul mic" or "Pond deck"
    /// all land, while anything ambiguous stays `.custom` (never a guess).
    static func inferred(fromName name: String, icon: String) -> SpaceKind {
        let folded = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()

        let nameRules: [(SpaceKind, [String])] = [
            (.pond,       ["iaz", "pond"]),
            // Before garden: "sera din grădină" is the greenhouse.
            (.greenhouse, ["sera", "greenhouse"]),
            (.garden,     ["gradin", "garden"]),
            (.garage,     ["garaj", "garage"]),
            (.basement,   ["subsol", "basement", "pivnit", "beci"]),
            (.forest,     ["padur", "forest"]),
            (.house,      ["casa", "house", "home"]),
        ]
        for (kind, stems) in nameRules where stems.contains(where: { folded.contains($0) }) {
            return kind
        }

        // The zone's stored SF Symbol as a second, weaker signal.
        let iconRules: [(SpaceKind, [String])] = [
            (.house,  ["house", "home"]),
            (.forest, ["tree"]),
            (.garden, ["leaf", "camera.macro"]),
            (.garage, ["car", "garage"]),
            (.pond,   ["drop", "water"]),
        ]
        for (kind, stems) in iconRules where stems.contains(where: { icon.contains($0) }) {
            return kind
        }
        return .custom
    }
}

// MARK: - PropertyZone → SpaceKind

extension PropertyZone {
    /// The zone's effective kind: the explicitly stored `space_kind` when
    /// present (and still a known case), else the conservative heuristic.
    var resolvedSpaceKind: SpaceKind {
        if let raw = spaceKind, let kind = SpaceKind(rawValue: raw) {
            return kind
        }
        return SpaceKind.inferred(fromName: name, icon: icon)
    }
}

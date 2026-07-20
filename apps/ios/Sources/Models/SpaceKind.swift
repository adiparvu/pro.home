import SwiftUI

// MARK: - Space kind (Estate OS E1)
//
// What a Digital Twin zone IS as a lived-in space — the classification the
// estate surfaces (the dashboard's "Domeniul" strip, the space detail page)
// dress themselves by: one SF Symbol, one localized title, one accent color
// and one adaptive scene wash per kind. Persisted per zone in
// `property_zones.space_kind` (nullable); zones never classified resolve
// through a deliberately conservative name/icon heuristic and otherwise
// stay `.custom` — the UI never guesses a kind it can't justify.

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

    /// The kind's accent color — always laid over glass or the mood
    /// backdrop, so every hue is either a brand token or a system color
    /// that adapts to both light and dark schemes.
    var accent: Color {
        switch self {
        case .house:      return .brandSkyBlue
        case .garden:     return .brandSuccess
        case .pond:       return .brandTeal
        case .forest:     return .green
        case .greenhouse: return .brandGold
        case .garage:     return .gray
        case .basement:   return .brown
        case .custom:     return .accentColor
        }
    }

    /// The kind's scene wash — the photo slot's stand-in (and loading
    /// state) for spaces without a photo: the accent as a quiet tinted
    /// gradient over whatever surface hosts it. Low opacities keep both
    /// the light and dark mood grounds (and the icon on top) legible.
    var sceneGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.30), accent.opacity(0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
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

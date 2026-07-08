import SwiftUI

// MARK: - Plant event (Plant OS P5)
//
// One entry in a plant's care history: a real action the caretaker took,
// stamped with when it happened. Rendered — interleaved with photo events —
// as the plant page's History timeline. Honesty rule: a row exists only for an
// action the user actually performed (see PlantEventService.log).

struct PlantEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let plantId: UUID
    let propertyId: UUID
    var kind: String
    var details: [String: String]?
    var at: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, details, at
        case plantId    = "plant_id"
        case propertyId = "property_id"
        case createdAt  = "created_at"
    }

    /// The typed kind, falling back to `.note` for any unknown server value so
    /// an added kind on the server never crashes an older client.
    var kindEnum: PlantEventKind { PlantEventKind(rawValue: kind) ?? .note }

    /// The free-text note attached to a `.note` (or any) event, if present.
    var noteText: String? {
        guard let t = details?["note"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }

    /// Parsed timestamp of when the action happened.
    var date: Date? { AppDate.timestamp(from: at) }
}

// MARK: - Plant event kind

/// The care actions a plant timeline records. Photos are NOT a kind here — they
/// live in `plant_photos` and interleave into the timeline separately.
enum PlantEventKind: String, CaseIterable, Identifiable {
    case watered
    case fertilized
    case repotted
    case sprayed
    case treated
    case pruned
    case note

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .watered:    return "drop.fill"
        case .fertilized: return "leaf.fill"
        case .repotted:   return "arrow.up.bin.fill"
        case .sprayed:    return "humidity.fill"
        case .treated:    return "cross.case.fill"
        case .pruned:     return "scissors"
        case .note:       return "note.text"
        }
    }

    /// Localization key for the kind's label (RO source / EN).
    var labelKey: LocalizedStringKey {
        switch self {
        case .watered:    return "plant_evt_watered"
        case .fertilized: return "plant_evt_fertilized"
        case .repotted:   return "plant_evt_repotted"
        case .sprayed:    return "plant_evt_sprayed"
        case .treated:    return "plant_evt_treated"
        case .pruned:     return "plant_evt_pruned"
        case .note:       return "plant_evt_note"
        }
    }

    /// Brand-token tint (design system), one hue per kind for at-a-glance scan.
    var tint: Color {
        switch self {
        case .watered:    return .brandPrimaryBlue
        case .fertilized: return .brandSuccess
        case .repotted:   return .brandGold
        case .sprayed:    return .brandTeal
        case .treated:    return .brandDanger
        case .pruned:     return .brandPurple
        case .note:       return .brandSkyBlue
        }
    }
}

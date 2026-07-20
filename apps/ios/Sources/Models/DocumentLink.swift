import SwiftUI

// MARK: - Document relations (Document Intelligence D4)

/// A document attached to a thing in the house. Only kinds backed by a real
/// module are offered in the UI — the app never presents a link it can't
/// resolve (honesty law). New modules (vehicles, pets) join the list when
/// they ship.
enum DocumentTargetKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case property, room, appliance, element, plant, person

    var id: String { rawValue }

    /// The table the target's name is read from.
    var table: String {
        switch self {
        case .property:  return "properties"
        case .room:      return "property_zones"
        case .appliance: return "appliances"
        case .element:   return "property_elements"
        case .plant:     return "plants"
        case .person:    return "family_members"
        }
    }

    var icon: String {
        switch self {
        case .property:  return "house.fill"
        case .room:      return "square.split.bottomrightquarter.fill"
        case .appliance: return "refrigerator.fill"
        case .element:   return "cube.fill"
        case .plant:     return "leaf.fill"
        case .person:    return "person.fill"
        }
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .property:  return "doc_target_property"
        case .room:      return "doc_target_room"
        case .appliance: return "doc_target_appliance"
        case .element:   return "doc_target_element"
        case .plant:     return "doc_target_plant"
        case .person:    return "doc_target_person"
        }
    }
}

struct DocumentLink: Identifiable, Codable, Hashable {
    let id: UUID
    let documentId: UUID
    var targetKind: String
    var targetId: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case targetKind = "target_kind"
        case targetId   = "target_id"
        case createdAt  = "created_at"
    }

    var kind: DocumentTargetKind? { DocumentTargetKind(rawValue: targetKind) }
}

/// A parent→child edge between two documents (contract → invoice → receipt).
struct RelatedDocument: Identifiable, Codable, Hashable {
    let id: UUID
    let parentId: UUID
    let childId: UUID
    var relation: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, relation
        case parentId  = "parent_id"
        case childId   = "child_id"
        case createdAt = "created_at"
    }
}

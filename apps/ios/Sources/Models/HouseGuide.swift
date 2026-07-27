import SwiftUI

// MARK: - House manual ("Manualul casei")
//
// How the home actually works, written down once: where the water main is,
// how the boiler restarts, which fuse feeds the kitchen. Every guide can
// anchor to a zone or an appliance — the same objects the passport and the
// service book already know — so the manual is part of the house's dossier,
// not a loose notes app.

struct HouseGuide: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var icon: String?
    var content: String
    var zoneId: UUID?
    var applianceId: UUID?
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, icon, content
        case propertyId  = "property_id"
        case zoneId      = "zone_id"
        case applianceId = "appliance_id"
        case createdBy   = "created_by"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    var iconName: String { icon ?? "book.closed.fill" }
}

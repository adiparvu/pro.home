import SwiftUI

// MARK: - Floor plans & rooms (Plans & 3D rebuild, phase A)
//
// These map the existing `floor_plans` and `rooms` tables — a schema that
// was designed for exactly this feature and sat dormant. A floor groups
// rooms; a room can carry plan-rectangle geometry (percent-based, for the
// interactive 2D plan in phase C) and a RoomPlan .usdz scan stored in the
// private `documents` bucket (signed on display).

struct FloorPlanRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var floorNumber: Int
    var svgData: String?
    var imageUrl: String?
    var widthM: Double?
    var lengthM: Double?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case propertyId  = "property_id"
        case floorNumber = "floor_number"
        case svgData     = "svg_data"
        case imageUrl    = "image_url"
        case widthM      = "width_m"
        case lengthM     = "length_m"
        case sortOrder   = "sort_order"
    }
}

struct RoomRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var roomType: String
    var floor: Int
    var areaSqm: Double?
    var floorPlanId: UUID?
    var xPct: Double?
    var yPct: Double?
    var widthPct: Double?
    var heightPct: Double?
    var color: String?
    var icon: String?
    /// Storage object path of the room's .usdz scan (documents bucket).
    var scanPath: String?
    /// The PropertyZone this room represents on the plan (migration 159) —
    /// the id-link that replaced the fragile name join between the two
    /// space worlds. Optional so cached/pre-migration rows still decode.
    var zoneId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, floor, color, icon
        case propertyId  = "property_id"
        case roomType    = "room_type"
        case areaSqm     = "area_sqm"
        case floorPlanId = "floor_plan_id"
        case xPct        = "x_pct"
        case yPct        = "y_pct"
        case widthPct    = "width_pct"
        case heightPct   = "height_pct"
        case scanPath    = "scan_path"
        case zoneId      = "zone_id"
    }

    var hasScan: Bool { !(scanPath ?? "").isEmpty }
    var kindIcon: String { icon ?? RoomKind.icon(roomType) }
    var kindLabel: String { RoomKind.label(roomType) }
}

// MARK: - Room kind metadata (mirrors the DB `room_type` enum)

enum RoomKind {
    /// Every value of the DB enum, in display order.
    static let all = ["living_room", "kitchen", "bedroom", "bathroom", "dining_room",
                      "office", "hallway", "laundry", "storage", "garage",
                      "basement", "attic", "balcony", "terrace", "garden", "other"]

    static func label(_ t: String) -> String {
        switch t {
        case "bedroom":     return String(localized: "room_type_bedroom")
        case "bathroom":    return String(localized: "room_type_bathroom")
        case "kitchen":     return String(localized: "room_type_kitchen")
        case "living_room": return String(localized: "room_type_living_room")
        case "dining_room": return String(localized: "room_type_dining_room")
        case "office":      return String(localized: "room_type_office")
        case "garage":      return String(localized: "room_type_garage")
        case "basement":    return String(localized: "room_type_basement")
        case "attic":       return String(localized: "room_type_attic")
        case "hallway":     return String(localized: "room_type_hallway")
        case "laundry":     return String(localized: "room_type_laundry")
        case "storage":     return String(localized: "room_type_storage")
        case "garden":      return String(localized: "room_type_garden")
        case "balcony":     return String(localized: "room_type_balcony")
        case "terrace":     return String(localized: "room_type_terrace")
        default:            return String(localized: "room_type_other")
        }
    }

    static func icon(_ t: String) -> String {
        switch t {
        case "bedroom":     return "bed.double.fill"
        case "bathroom":    return "shower.fill"
        case "kitchen":     return "refrigerator.fill"
        case "living_room": return "sofa.fill"
        case "dining_room": return "fork.knife"
        case "office":      return "desktopcomputer"
        case "garage":      return "car.fill"
        case "basement":    return "stairs"
        case "attic":       return "house.lodge.fill"
        case "hallway":     return "door.left.hand.open"
        case "laundry":     return "washer.fill"
        case "storage":     return "shippingbox.fill"
        case "garden":      return "leaf.fill"
        case "balcony":     return "sun.horizon.fill"
        case "terrace":     return "cloud.sun.fill"
        default:            return "square.split.bottomrightquarter.fill"
        }
    }

    static func color(_ t: String) -> Color {
        switch t {
        case "bedroom":              return .indigo
        case "bathroom":             return .cyan
        case "kitchen":              return .orange
        case "living_room":          return .blue
        case "dining_room":          return .brown
        case "office":               return .purple
        case "garage":               return .gray
        case "basement", "attic":    return .brown
        case "hallway":              return .teal
        case "laundry":              return .mint
        case "storage":              return .gray
        case "garden", "balcony", "terrace": return .green
        default:                     return .secondary
        }
    }
}

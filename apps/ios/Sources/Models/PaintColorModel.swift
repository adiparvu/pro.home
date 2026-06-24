import SwiftUI

enum PaintFinish: String, CaseIterable, Codable {
    case matte
    case satin
    case eggshell
    case semiGloss = "semi-gloss"
    case gloss

    var displayName: String {
        switch self {
        case .matte:     return String(localized: "Matte")
        case .satin:     return String(localized: "Satin")
        case .eggshell:  return String(localized: "Eggshell")
        case .semiGloss: return String(localized: "Semi-Gloss")
        case .gloss:     return String(localized: "Gloss")
        }
    }
}

struct PaintColor: Identifiable, Codable, Equatable {
    var id: UUID
    var propertyId: UUID
    var ownerId: UUID
    var roomName: String
    var surface: String
    var colorName: String
    var brand: String?
    var code: String?
    var finish: PaintFinish?
    var hexColor: String?
    var notes: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case roomName   = "room_name"
        case surface
        case colorName  = "color_name"
        case brand, code, finish, notes
        case hexColor   = "hex_color"
        case createdAt  = "created_at"
    }

    var swatchColor: Color {
        guard let hex = hexColor, !hex.isEmpty else {
            return Color.primary.opacity(0.3)
        }
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return Color.primary.opacity(0.3)
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8)  & 0xFF) / 255.0
        let b = Double( value        & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    var finishDisplay: String { finish?.displayName ?? "Unknown" }
}

struct NewPaintColorPayload: Encodable {
    let propertyId: UUID
    let ownerId: UUID
    let roomName: String
    let surface: String
    let colorName: String
    let brand: String?
    let code: String?
    let finish: String?
    let hexColor: String?
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case ownerId    = "owner_id"
        case roomName   = "room_name"
        case surface
        case colorName  = "color_name"
        case brand, code, finish, notes
        case hexColor   = "hex_color"
        case createdAt  = "created_at"
    }
}

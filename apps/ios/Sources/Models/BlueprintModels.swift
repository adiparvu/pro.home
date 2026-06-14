import SwiftUI

// MARK: - Home Scan (3D models, floor plans, blueprints, photos)

struct HomeScan: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: String        // "room3d" | "site3d" | "floorplan" | "blueprint" | "photo"
    var fileName: String     // stored under Blueprints/ in the app documents directory
    var fileFormat: String   // "usdz" | "image" | "pdf"
    var notes: String = ""
    var createdAt: Date = Date()

    var kindLabel: String {
        switch kind {
        case "room3d":    return "3D Room Scan"
        case "site3d":    return "3D Site Scan"
        case "floorplan": return "Floor Plan"
        case "blueprint": return "Blueprint"
        case "photo":     return "Photo"
        default:          return "Plan"
        }
    }

    var icon: String {
        switch fileFormat {
        case "usdz":  return "cube.transparent.fill"
        case "pdf":   return "doc.richtext.fill"
        case "image": return "photo.fill"
        default:      return "doc.fill"
        }
    }

    var accent: Color {
        switch kind {
        case "room3d", "site3d": return .purple
        case "floorplan":        return .blue
        case "blueprint":        return .teal
        case "photo":            return .orange
        default:                 return .gray
        }
    }
}

// MARK: - Buried Utility (underground cables, pipes, etc.)

struct BuriedUtility: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: String          // see BuriedUtilityKind.all
    var depthCm: Double        // burial depth in centimetres
    var lengthM: Double        // run length in metres
    var latitude: Double?
    var longitude: Double?
    var photoName: String?     // optional reference photo in Blueprints/
    var notes: String = ""
    var installedDate: Date?
    var createdAt: Date = Date()

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var swiftColor: Color { BuriedUtilityKind.color(type) }
    var icon: String { BuriedUtilityKind.icon(type) }
    var typeLabel: String { BuriedUtilityKind.label(type) }

    var depthDisplay: String {
        if depthCm >= 100 {
            return String(format: "%.2f m deep", depthCm / 100)
        }
        return String(format: "%.0f cm deep", depthCm)
    }

    var lengthDisplay: String {
        String(format: "%.1f m", lengthM)
    }
}

// MARK: - Utility kind metadata

enum BuriedUtilityKind {
    static let all = ["electrical", "water", "gas", "sewage", "internet", "irrigation", "drainage", "other"]

    static func label(_ t: String) -> String {
        switch t {
        case "electrical": return "Electrical"
        case "water":      return "Water"
        case "gas":        return "Gas"
        case "sewage":     return "Sewage"
        case "internet":   return "Internet / Data"
        case "irrigation": return "Irrigation"
        case "drainage":   return "Drainage"
        default:           return "Other"
        }
    }

    static func icon(_ t: String) -> String {
        switch t {
        case "electrical": return "bolt.fill"
        case "water":      return "drop.fill"
        case "gas":        return "flame.fill"
        case "sewage":     return "arrow.down.to.line"
        case "internet":   return "network"
        case "irrigation": return "sprinkler.and.droplets.fill"
        case "drainage":   return "water.waves"
        default:           return "point.topleft.down.to.point.bottomright.curvepath.fill"
        }
    }

    static func color(_ t: String) -> Color {
        switch t {
        case "electrical": return .yellow
        case "water":      return .blue
        case "gas":        return .orange
        case "sewage":     return .brown
        case "internet":   return .green
        case "irrigation": return .cyan
        case "drainage":   return .indigo
        default:           return .gray
        }
    }
}

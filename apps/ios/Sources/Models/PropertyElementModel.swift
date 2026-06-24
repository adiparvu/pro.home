import Foundation
import SwiftUI
import CoreLocation

// MARK: - PropertyElement

struct PropertyElement: Identifiable, Codable, Equatable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var elementType: PropertyElementType
    var description: String?
    var positionX: Double
    var positionY: Double
    var healthScore: Int
    var technicalCondition: TechnicalCondition
    var estimatedValue: Double?
    var valueCurrency: String
    var purchaseDate: String?
    var warrantyUntil: String?
    var brand: String?
    var model: String?
    var serialNumber: String?
    var notes: String?
    var layer: PropertyLayer
    var sortOrder: Int
    // Digital Twin — optional geo placement on the satellite map + zone link.
    var latitude: Double?
    var longitude: Double?
    var zoneId: UUID?
    var photoUrls: [String]?
    let createdAt: String
    var updatedAt: String

    var photos: [String] { photoUrls ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, name, description, brand, model, notes, layer, latitude, longitude
        case photoUrls         = "photo_urls"
        case propertyId        = "property_id"
        case elementType       = "element_type"
        case positionX         = "position_x"
        case positionY         = "position_y"
        case healthScore       = "health_score"
        case technicalCondition = "technical_condition"
        case estimatedValue    = "estimated_value"
        case valueCurrency     = "value_currency"
        case purchaseDate      = "purchase_date"
        case warrantyUntil     = "warranty_until"
        case serialNumber      = "serial_number"
        case sortOrder         = "sort_order"
        case zoneId            = "zone_id"
        case createdAt         = "created_at"
        case updatedAt         = "updated_at"
    }

    /// Map coordinate when the object has been geo-located.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var healthColor: Color {
        switch healthScore {
        case 90...100: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return Color.orange
        case 25..<50:  return Color(red: 1.0, green: 0.45, blue: 0.1)
        default:       return Color.red
        }
    }

    var warrantyStatus: WarrantyStatus {
        guard let until = warrantyUntil else { return .none }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: until) else { return .none }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return .expired }
        if days <= 90 { return .expiringSoon }
        return .valid
    }
}

enum WarrantyStatus {
    case none, valid, expiringSoon, expired
    var color: Color {
        switch self {
        case .none:         return .secondary
        case .valid:        return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .expiringSoon: return .orange
        case .expired:      return .red
        }
    }
    var label: String {
        switch self {
        case .none:         return String(localized: "No warranty")
        case .valid:        return String(localized: "Under warranty")
        case .expiringSoon: return String(localized: "Expiring soon")
        case .expired:      return String(localized: "Warranty expired")
        }
    }
}

// MARK: - PropertyElementType

enum PropertyElementType: String, Codable, CaseIterable {
    case house           = "house"
    case garage          = "garage"
    case gazebo          = "gazebo"
    case pool            = "pool"
    case yard            = "yard"
    case lawn            = "lawn"
    case tree            = "tree"
    case fence           = "fence"
    case gate            = "gate"
    case camera          = "camera"
    case irrigation      = "irrigation"
    case solar           = "solar"
    case boiler          = "boiler"
    case electricalPanel = "electrical_panel"
    case shed            = "shed"
    case pet             = "pet"
    case other           = "other"

    var displayName: String {
        switch self {
        case .house:           return String(localized: "House")
        case .garage:          return String(localized: "Garage")
        case .gazebo:          return String(localized: "Gazebo")
        case .pool:            return String(localized: "Pool")
        case .yard:            return String(localized: "Yard")
        case .lawn:            return String(localized: "Lawn")
        case .tree:            return String(localized: "Tree")
        case .fence:           return String(localized: "Fence")
        case .gate:            return String(localized: "Gate")
        case .camera:          return String(localized: "Security camera")
        case .irrigation:      return String(localized: "Irrigation system")
        case .solar:           return String(localized: "Solar panels")
        case .boiler:          return String(localized: "Boiler")
        case .electricalPanel: return String(localized: "Electrical panel")
        case .shed:            return String(localized: "Shed")
        case .pet:             return String(localized: "Pet")
        case .other:           return String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .house:           return "house.fill"
        case .garage:          return "car.fill"
        case .gazebo:          return "umbrella.fill"
        case .pool:            return "drop.fill"
        case .yard:            return "leaf.fill"
        case .lawn:            return "leaf"
        case .tree:            return "tree.fill"
        case .fence:           return "align.horizontal.left"
        case .gate:            return "door.left.hand.open"
        case .camera:          return "camera.fill"
        case .irrigation:      return "humidity.fill"
        case .solar:           return "sun.max.fill"
        case .boiler:          return "flame.fill"
        case .electricalPanel: return "bolt.fill"
        case .shed:            return "shippingbox.fill"
        case .pet:             return "pawprint.fill"
        case .other:           return "questionmark.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .house:           return Color(red: 0.29, green: 0.56, blue: 0.89)
        case .garage:          return Color(red: 0.48, green: 0.41, blue: 0.93)
        case .gazebo:          return Color(red: 0.31, green: 0.78, blue: 0.47)
        case .pool:            return Color(red: 0.0,  green: 0.71, blue: 0.85)
        case .yard, .lawn:     return Color(red: 0.18, green: 0.8,  blue: 0.44)
        case .tree:            return Color(red: 0.1,  green: 0.65, blue: 0.3)
        case .fence, .gate:    return Color(red: 0.58, green: 0.65, blue: 0.65)
        case .camera:          return Color(red: 0.91, green: 0.3,  blue: 0.24)
        case .irrigation:      return Color(red: 0.2,  green: 0.6,  blue: 0.86)
        case .solar:           return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .boiler:          return Color(red: 0.91, green: 0.3,  blue: 0.24)
        case .electricalPanel: return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .shed:            return Color(red: 0.55, green: 0.45, blue: 0.33)
        case .pet:             return Color(red: 0.91, green: 0.12, blue: 0.39)
        case .other:           return Color(red: 0.61, green: 0.35, blue: 0.71)
        }
    }

    var defaultLayer: PropertyLayer {
        switch self {
        case .camera, .irrigation, .solar, .boiler, .electricalPanel: return .utility
        default: return .property
        }
    }
}

// MARK: - TechnicalCondition

enum TechnicalCondition: String, Codable, CaseIterable {
    case excellent = "excellent"
    case good      = "good"
    case fair      = "fair"
    case poor      = "poor"
    case critical  = "critical"

    var displayName: String {
        switch self {
        case .excellent: return String(localized: "Excellent")
        case .good:      return String(localized: "Good")
        case .fair:      return String(localized: "Fair")
        case .poor:      return String(localized: "Poor")
        case .critical:  return String(localized: "Critical")
        }
    }

    var color: Color {
        switch self {
        case .excellent: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .good:      return Color(red: 0.4, green: 0.75, blue: 0.3)
        case .fair:      return Color.orange
        case .poor:      return Color(red: 1.0, green: 0.45, blue: 0.1)
        case .critical:  return Color.red
        }
    }

    var defaultHealthScore: Int {
        switch self {
        case .excellent: return 95
        case .good:      return 80
        case .fair:      return 60
        case .poor:      return 35
        case .critical:  return 15
        }
    }
}

// MARK: - PropertyLayer

enum PropertyLayer: String, Codable, CaseIterable {
    case property   = "property"
    case maintenance = "maintenance"
    case utility    = "utility"
    case financial  = "financial"
    case smartHome  = "smart_home"

    var displayName: String {
        switch self {
        case .property:    return String(localized: "Property")
        case .maintenance: return String(localized: "Maintenance")
        case .utility:     return String(localized: "Utilities")
        case .financial:   return String(localized: "Financial")
        case .smartHome:   return String(localized: "Smart Home")
        }
    }

    var icon: String {
        switch self {
        case .property:    return "house"
        case .maintenance: return "wrench.and.screwdriver"
        case .utility:     return "bolt"
        case .financial:   return "banknote"
        case .smartHome:   return "homekit"
        }
    }

    var color: Color {
        switch self {
        case .property:    return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .maintenance: return .orange
        case .utility:     return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .financial:   return Color(red: 0.2, green: 0.8, blue: 0.45)
        case .smartHome:   return Color(red: 0.48, green: 0.41, blue: 0.93)
        }
    }
}

// MARK: - ElementRecord

struct ElementRecord: Identifiable, Codable {
    let id: UUID
    let elementId: UUID
    let propertyId: UUID
    var recordType: ElementRecordType
    var title: String
    var content: String?
    var cost: Double?
    var currency: String
    var recordDate: String
    var performedBy: String?
    var nextActionDate: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, content, currency, cost
        case elementId       = "element_id"
        case propertyId      = "property_id"
        case recordType      = "record_type"
        case performedBy     = "performed_by"
        case recordDate      = "record_date"
        case nextActionDate  = "next_action_date"
        case createdAt       = "created_at"
    }
}

enum ElementRecordType: String, Codable, CaseIterable {
    case note        = "note"
    case maintenance = "maintenance"
    case cost        = "cost"
    case inspection  = "inspection"
    case reminder    = "reminder"

    var displayName: String {
        switch self {
        case .note:        return "Note"
        case .maintenance: return "Work"
        case .cost:        return "Cost"
        case .inspection:  return "Inspection"
        case .reminder:    return "Reminder"
        }
    }

    var icon: String {
        switch self {
        case .note:        return "note.text"
        case .maintenance: return "wrench.and.screwdriver"
        case .cost:        return "eurosign"
        case .inspection:  return "checkmark.shield"
        case .reminder:    return "bell"
        }
    }

    var color: Color {
        switch self {
        case .note:        return Color(red: 0.29, green: 0.56, blue: 0.89)
        case .maintenance: return Color.orange
        case .cost:        return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .inspection:  return Color(red: 0.48, green: 0.41, blue: 0.93)
        case .reminder:    return Color(red: 0.95, green: 0.77, blue: 0.06)
        }
    }
}

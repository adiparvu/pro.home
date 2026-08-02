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
    var coverPhotoUrl: String?
    var isElectric: Bool
    var automationSystem: String?
    var isFavorite: Bool
    var homekitAccessoryId: String?
    var tags: [String]
    let createdAt: String
    var updatedAt: String
    /// Predictive phase 2: how often (months) this element should be
    /// serviced, and when it last was. Both optional — untracked elements
    /// stay exactly as before.
    var serviceIntervalMonths: Int?
    var lastServiceAt: String?

    var photos: [String] { photoUrls ?? [] }

    /// The next predicted service date: last service (or, failing that, the
    /// purchase date) plus the interval. Nil unless the household set a
    /// cadence — the honesty law forbids inventing schedules.
    var nextServiceDue: Date? {
        guard let months = serviceIntervalMonths, months > 0 else { return nil }
        let baseStr = lastServiceAt ?? purchaseDate
        guard let baseStr, let base = AppDate.day(from: baseStr) else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: base)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, brand, model, notes, layer, latitude, longitude, tags
        case photoUrls         = "photo_urls"
        case coverPhotoUrl     = "cover_photo_url"
        case isElectric        = "is_electric"
        case automationSystem  = "automation_system"
        case isFavorite        = "is_favorite"
        case homekitAccessoryId = "homekit_accessory_id"
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
        case serviceIntervalMonths = "service_interval_months"
        case lastServiceAt     = "last_service_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        name = try c.decode(String.self, forKey: .name)
        elementType = try c.decode(PropertyElementType.self, forKey: .elementType)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        positionX = try c.decodeIfPresent(Double.self, forKey: .positionX) ?? 0
        positionY = try c.decodeIfPresent(Double.self, forKey: .positionY) ?? 0
        healthScore = try c.decodeIfPresent(Int.self, forKey: .healthScore) ?? 100
        technicalCondition = try c.decodeIfPresent(TechnicalCondition.self, forKey: .technicalCondition) ?? .good
        estimatedValue = try c.decodeIfPresent(Double.self, forKey: .estimatedValue)
        valueCurrency = try c.decodeIfPresent(String.self, forKey: .valueCurrency) ?? "EUR"
        purchaseDate = try c.decodeIfPresent(String.self, forKey: .purchaseDate)
        warrantyUntil = try c.decodeIfPresent(String.self, forKey: .warrantyUntil)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        serialNumber = try c.decodeIfPresent(String.self, forKey: .serialNumber)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        layer = try c.decodeIfPresent(PropertyLayer.self, forKey: .layer) ?? .property
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        zoneId = try c.decodeIfPresent(UUID.self, forKey: .zoneId)
        photoUrls = try c.decodeIfPresent([String].self, forKey: .photoUrls)
        coverPhotoUrl = try c.decodeIfPresent(String.self, forKey: .coverPhotoUrl)
        isElectric = try c.decodeIfPresent(Bool.self, forKey: .isElectric) ?? false
        automationSystem = try c.decodeIfPresent(String.self, forKey: .automationSystem)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        homekitAccessoryId = try c.decodeIfPresent(String.self, forKey: .homekitAccessoryId)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        serviceIntervalMonths = try? c.decodeIfPresent(Int.self, forKey: .serviceIntervalMonths)
        lastServiceAt = try? c.decodeIfPresent(String.self, forKey: .lastServiceAt)
    }

    /// Map coordinate when the object has been geo-located.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var healthColor: Color {
        switch healthScore {
        case 90...100: return Color.brandSuccess
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return Color.orange
        case 25..<50:  return Color.brandWarning
        default:       return Color.red
        }
    }

    var warrantyStatus: WarrantyStatus {
        guard let until = warrantyUntil else { return .none }
        guard let date = AppDate.day(from: until) else { return .none }
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
        case .valid:        return Color.brandSuccess
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
    // Structures
    case house = "house", garage = "garage", gazebo = "gazebo", shed = "shed"
    case barn = "barn", carport = "carport", terrace = "terrace", balcony = "balcony"
    case basement = "basement", attic = "attic", roof = "roof", chimney = "chimney"
    case staircase = "staircase", greenhouse = "greenhouse", playground = "playground"
    // Access
    case fence = "fence", gate = "gate", driveway = "driveway", parking = "parking"
    // Rooms
    case kitchen = "kitchen", bathroom = "bathroom", bedroom = "bedroom"
    case livingRoom = "living_room", office = "office", laundry = "laundry"
    // Outdoor / green
    case yard = "yard", lawn = "lawn", tree = "tree", garden = "garden"
    case vegetableGarden = "vegetable_garden", pool = "pool", pond = "pond", fountain = "fountain"
    // Water
    case well = "well", septic = "septic", waterTank = "water_tank", irrigation = "irrigation"
    // Energy / utilities
    case solar = "solar", boiler = "boiler", electricalPanel = "electrical_panel"
    case heatPump = "heat_pump", airConditioner = "air_conditioner", ventilation = "ventilation"
    case waterHeater = "water_heater", generator = "generator", battery = "battery_storage"
    case evCharger = "ev_charger", gasMeter = "gas_meter", waterMeter = "water_meter", electricMeter = "electric_meter"
    // Smart / security
    case camera = "camera", alarm = "alarm_system", smartLock = "smart_lock"
    case intercom = "intercom", doorbell = "doorbell", thermostat = "thermostat"
    case router = "router", sensor = "sensor"
    // Appliances
    case fridge = "fridge", washingMachine = "washing_machine", dryer = "dryer"
    case dishwasher = "dishwasher", oven = "oven", stove = "stove", microwave = "microwave", tv = "tv"
    // Equipment / misc
    case bbq = "bbq", lawnMower = "lawn_mower", pet = "pet", other = "other"

    var displayName: String {
        switch self {
        case .house:           return String(localized: "House")
        case .garage:          return String(localized: "Garage")
        case .gazebo:          return String(localized: "Gazebo")
        case .shed:            return String(localized: "Shed")
        case .barn:            return String(localized: "Barn")
        case .carport:         return String(localized: "Carport")
        case .terrace:         return String(localized: "Terrace")
        case .balcony:         return String(localized: "Balcony")
        case .basement:        return String(localized: "Basement")
        case .attic:           return String(localized: "Attic")
        case .roof:            return String(localized: "Roof")
        case .chimney:         return String(localized: "Chimney")
        case .staircase:       return String(localized: "Staircase")
        case .greenhouse:      return String(localized: "Greenhouse")
        case .playground:      return String(localized: "Playground")
        case .fence:           return String(localized: "Fence")
        case .gate:            return String(localized: "Gate")
        case .driveway:        return String(localized: "Driveway")
        case .parking:         return String(localized: "Parking")
        case .kitchen:         return String(localized: "Kitchen")
        case .bathroom:        return String(localized: "Bathroom")
        case .bedroom:         return String(localized: "Bedroom")
        case .livingRoom:      return String(localized: "Living room")
        case .office:          return String(localized: "Office")
        case .laundry:         return String(localized: "Laundry room")
        case .yard:            return String(localized: "Yard")
        case .lawn:            return String(localized: "Lawn")
        case .tree:            return String(localized: "Tree")
        case .garden:          return String(localized: "Garden")
        case .vegetableGarden: return String(localized: "Vegetable garden")
        case .pool:            return String(localized: "Pool")
        case .pond:            return String(localized: "Pond")
        case .fountain:        return String(localized: "Fountain")
        case .well:            return String(localized: "Well")
        case .septic:          return String(localized: "Septic tank")
        case .waterTank:       return String(localized: "Water tank")
        case .irrigation:      return String(localized: "Irrigation system")
        case .solar:           return String(localized: "Solar panels")
        case .boiler:          return String(localized: "Boiler")
        case .electricalPanel: return String(localized: "Electrical panel")
        case .heatPump:        return String(localized: "Heat pump")
        case .airConditioner:  return String(localized: "Air conditioning")
        case .ventilation:     return String(localized: "Ventilation")
        case .waterHeater:     return String(localized: "Water heater")
        case .generator:       return String(localized: "Generator")
        case .battery:         return String(localized: "Battery storage")
        case .evCharger:       return String(localized: "EV charger")
        case .gasMeter:        return String(localized: "Gas meter")
        case .waterMeter:      return String(localized: "Water meter")
        case .electricMeter:   return String(localized: "Electric meter")
        case .camera:          return String(localized: "Security camera")
        case .alarm:           return String(localized: "Alarm system")
        case .smartLock:       return String(localized: "Smart lock")
        case .intercom:        return String(localized: "Intercom")
        case .doorbell:        return String(localized: "Doorbell")
        case .thermostat:      return String(localized: "Thermostat")
        case .router:          return String(localized: "Router / Wi-Fi")
        case .sensor:          return String(localized: "Sensor")
        case .fridge:          return String(localized: "Refrigerator")
        case .washingMachine:  return String(localized: "Washing machine")
        case .dryer:           return String(localized: "Dryer")
        case .dishwasher:      return String(localized: "Dishwasher")
        case .oven:            return String(localized: "Oven")
        case .stove:           return String(localized: "Stove")
        case .microwave:       return String(localized: "Microwave")
        case .tv:              return String(localized: "TV")
        case .bbq:             return String(localized: "BBQ / Grill")
        case .lawnMower:       return String(localized: "Lawn mower")
        case .pet:             return String(localized: "Pet")
        case .other:           return String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .house:           return "house.fill"
        case .garage:          return "car.fill"
        case .gazebo:          return "umbrella.fill"
        case .shed:            return "shippingbox.fill"
        case .barn:            return "house.lodge.fill"
        case .carport:         return "car.2.fill"
        case .terrace:         return "sun.haze.fill"
        case .balcony:         return "building.2.fill"
        case .basement:        return "stairs"
        case .attic:           return "house"
        case .roof:            return "house.lodge.fill"
        case .chimney:         return "smoke.fill"
        case .staircase:       return "stairs"
        case .greenhouse:      return "leaf.circle.fill"
        case .playground:      return "figure.play"
        case .fence:           return "align.horizontal.left"
        case .gate:            return "door.left.hand.open"
        case .driveway:        return "road.lanes"
        case .parking:         return "parkingsign"
        case .kitchen:         return "frying.pan.fill"
        case .bathroom:        return "shower.fill"
        case .bedroom:         return "bed.double.fill"
        case .livingRoom:      return "sofa.fill"
        case .office:          return "lamp.desk.fill"
        case .laundry:         return "washer.fill"
        case .yard:            return "leaf.fill"
        case .lawn:            return "leaf"
        case .tree:            return "tree.fill"
        case .garden:          return "camera.macro"
        case .vegetableGarden: return "carrot.fill"
        case .pool:            return "drop.fill"
        case .pond:            return "water.waves"
        case .fountain:        return "drop.circle.fill"
        case .well:            return "cylinder.split.1x2.fill"
        case .septic:          return "arrow.triangle.2.circlepath"
        case .waterTank:       return "cylinder.fill"
        case .irrigation:      return "humidity.fill"
        case .solar:           return "sun.max.fill"
        case .boiler:          return "flame.fill"
        case .electricalPanel: return "bolt.fill"
        case .heatPump:        return "thermometer.snowflake"
        case .airConditioner:  return "wind.snow"
        case .ventilation:     return "fan.fill"
        case .waterHeater:     return "spigot.fill"
        case .generator:       return "engine.combustion.fill"
        case .battery:         return "minus.plus.batteryblock.fill"
        case .evCharger:       return "bolt.car.fill"
        case .gasMeter:        return "flame.circle.fill"
        case .waterMeter:      return "gauge.medium"
        case .electricMeter:   return "bolt.circle.fill"
        case .camera:          return "camera.fill"
        case .alarm:           return "bell.badge.fill"
        case .smartLock:       return "lock.fill"
        case .intercom:        return "phone.bubble.fill"
        case .doorbell:        return "bell.fill"
        case .thermostat:      return "thermometer.medium"
        case .router:          return "wifi.router.fill"
        case .sensor:          return "sensor.fill"
        case .fridge:          return "refrigerator.fill"
        case .washingMachine:  return "washer.fill"
        case .dryer:           return "dryer.fill"
        case .dishwasher:      return "dishwasher.fill"
        case .oven:            return "oven.fill"
        case .stove:           return "stove.fill"
        case .microwave:       return "microwave.fill"
        case .tv:              return "tv.fill"
        case .bbq:             return "flame.fill"
        case .lawnMower:       return "scissors"
        case .pet:             return "pawprint.fill"
        case .other:           return "questionmark.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        // Structures — slate blue
        case .house, .garage, .gazebo, .shed, .barn, .carport, .terrace, .balcony,
             .basement, .attic, .roof, .chimney, .staircase, .playground:
            return Color.brandPrimaryBlue
        // Access — gray
        case .fence, .gate, .driveway, .parking:
            return Color(red: 0.58, green: 0.65, blue: 0.65)
        // Rooms — indigo
        case .kitchen, .bathroom, .bedroom, .livingRoom, .office, .laundry:
            return Color.brandPurple
        // Green
        case .yard, .lawn, .garden, .vegetableGarden, .greenhouse:
            return Color(red: 0.18, green: 0.8, blue: 0.44)
        case .tree:
            return Color(red: 0.1, green: 0.65, blue: 0.3)
        // Water — cyan
        case .pool, .pond, .fountain, .well, .septic, .waterTank, .irrigation, .waterMeter:
            return Color(red: 0.0, green: 0.71, blue: 0.85)
        // Energy — amber
        case .solar, .electricalPanel, .evCharger, .gasMeter, .electricMeter, .battery, .generator:
            return Color(red: 0.95, green: 0.77, blue: 0.06)
        // Heat — red/orange
        case .boiler, .heatPump, .waterHeater, .bbq:
            return Color.brandDanger
        // Climate / appliances — teal/purple
        case .airConditioner, .ventilation, .thermostat, .router,
             .fridge, .washingMachine, .dryer, .dishwasher, .oven, .stove, .microwave, .tv:
            return Color(red: 0.0, green: 0.6, blue: 0.7)
        // Security — red
        case .camera, .alarm, .smartLock, .intercom, .doorbell, .sensor:
            return Color.brandDanger
        case .pet:
            return Color(red: 0.91, green: 0.12, blue: 0.39)
        case .lawnMower:
            return Color(red: 0.55, green: 0.45, blue: 0.33)
        case .other:
            return Color(red: 0.61, green: 0.35, blue: 0.71)
        }
    }

    var defaultLayer: PropertyLayer {
        switch self {
        case .camera, .irrigation, .solar, .boiler, .electricalPanel, .heatPump,
             .airConditioner, .ventilation, .waterHeater, .generator, .battery,
             .evCharger, .gasMeter, .waterMeter, .electricMeter, .smartLock, .alarm,
             .intercom, .doorbell, .thermostat, .router, .sensor,
             .fridge, .washingMachine, .dryer, .dishwasher, .oven, .stove, .microwave, .tv:
            return .utility
        default:
            return .property
        }
    }

    /// Curated short list shown as quick chips; the full set is in `allCases`.
    static let common: [PropertyElementType] = [
        .house, .garage, .gate, .fence, .pool, .yard, .tree, .camera, .boiler, .solar
    ]

    var category: ElementCategory {
        switch self {
        case .house, .garage, .gazebo, .shed, .barn, .carport, .terrace, .balcony,
             .basement, .attic, .roof, .chimney, .staircase, .fence, .gate, .driveway, .parking:
            return .structures
        case .kitchen, .bathroom, .bedroom, .livingRoom, .office, .laundry:
            return .rooms
        case .yard, .lawn, .tree, .garden, .vegetableGarden, .greenhouse, .playground:
            return .outdoor
        case .pool, .pond, .fountain, .well, .septic, .waterTank, .irrigation, .waterMeter:
            return .water
        case .solar, .boiler, .electricalPanel, .heatPump, .waterHeater, .generator,
             .battery, .evCharger, .gasMeter, .electricMeter:
            return .energy
        case .camera, .alarm, .smartLock, .intercom, .doorbell, .sensor:
            return .security
        case .airConditioner, .ventilation, .thermostat, .router,
             .fridge, .washingMachine, .dryer, .dishwasher, .oven, .stove, .microwave, .tv:
            return .appliances
        case .bbq, .lawnMower:
            return .equipment
        case .pet, .other:
            return .other
        }
    }
}

// MARK: - ElementCategory (type groups, for filtering)

enum ElementCategory: String, CaseIterable, Identifiable {
    case structures, rooms, outdoor, water, energy, security, appliances, equipment, other
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .structures: return String(localized: "Structures")
        case .rooms:      return String(localized: "Rooms")
        case .outdoor:    return String(localized: "Outdoor")
        case .water:      return String(localized: "Water")
        case .energy:     return String(localized: "Energy")
        case .security:   return String(localized: "Security")
        case .appliances: return String(localized: "Appliances")
        case .equipment:  return String(localized: "Equipment")
        case .other:      return String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .structures: return "building.2.fill"
        case .rooms:      return "sofa.fill"
        case .outdoor:    return "leaf.fill"
        case .water:      return "drop.fill"
        case .energy:     return "bolt.fill"
        case .security:   return "lock.shield.fill"
        case .appliances: return "tv.fill"
        case .equipment:  return "wrench.and.screwdriver.fill"
        case .other:      return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .structures: return Color.brandPrimaryBlue
        case .rooms:      return Color.brandPurple
        case .outdoor:    return Color(red: 0.18, green: 0.8, blue: 0.44)
        case .water:      return Color(red: 0.0, green: 0.71, blue: 0.85)
        case .energy:     return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .security:   return Color.brandDanger
        case .appliances: return Color(red: 0.0, green: 0.6, blue: 0.7)
        case .equipment:  return Color(red: 0.55, green: 0.45, blue: 0.33)
        case .other:      return Color(red: 0.61, green: 0.35, blue: 0.71)
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
        case .excellent: return Color.brandSuccess
        case .good:      return Color(red: 0.4, green: 0.75, blue: 0.3)
        case .fair:      return Color.orange
        case .poor:      return Color.brandWarning
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

    /// Tolerant decode (IMG_9279): ONE zone written by an old build carried
    /// layer="indoor" — a label outside this vocabulary — and that single
    /// row's decode failure blinded the ENTIRE spaces list for six weeks:
    /// the page showed empty, the family kept re-creating spaces, and every
    /// "save" looked lost. An unknown label degrades to .property; it must
    /// never again take the whole fetch down with it.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PropertyLayer(rawValue: raw) ?? .property
    }

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
        case .property:    return Color.brandSkyBlue
        case .maintenance: return .orange
        case .utility:     return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .financial:   return Color.brandSuccess
        case .smartHome:   return Color.brandPurple
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
        case .note:        return String(localized: "Note")
        case .maintenance: return String(localized: "Work")
        case .cost:        return String(localized: "Cost")
        case .inspection:  return String(localized: "Inspection")
        case .reminder:    return String(localized: "Reminder")
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
        case .note:        return Color.brandPrimaryBlue
        case .maintenance: return Color.orange
        case .cost:        return Color.brandSuccess
        case .inspection:  return Color.brandPurple
        case .reminder:    return Color(red: 0.95, green: 0.77, blue: 0.06)
        }
    }
}

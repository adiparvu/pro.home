import Foundation
import SwiftUI

// MARK: - Pond Type

enum PondType: String, Codable, CaseIterable {
    case koi         = "koi"
    case ornamental  = "ornamental"
    case aquaculture = "aquaculture"
    case natural     = "natural"
    case swimming    = "swimming"

    var displayName: String {
        switch self {
        case .koi:         return "Koi Pond"
        case .ornamental:  return "Ornamental Pond"
        case .aquaculture: return "Aquaculture"
        case .natural:     return "Natural Pond"
        case .swimming:    return "Swimming Pond"
        }
    }

    var icon: String {
        switch self {
        case .koi:         return "fish.fill"
        case .ornamental:  return "leaf.fill"
        case .aquaculture: return "chart.bar.fill"
        case .natural:     return "mountain.2.fill"
        case .swimming:    return "figure.pool.swim"
        }
    }
}

// MARK: - Pond Zone Type

enum PondZoneType: String, Codable, CaseIterable {
    case shallowArea    = "shallow_area"
    case deepArea       = "deep_area"
    case filterZone     = "filter_zone"
    case streamSection  = "stream_section"
    case plantingArea   = "planting_area"
    case oxygenPoint    = "oxygen_point"
    case feedingStation = "feeding_station"

    var displayName: String {
        switch self {
        case .shallowArea:    return "Shallow Area"
        case .deepArea:       return "Deep Area"
        case .filterZone:     return "Filter Zone"
        case .streamSection:  return "Stream / Waterfall"
        case .plantingArea:   return "Planting Area"
        case .oxygenPoint:    return "Oxygenation Point"
        case .feedingStation: return "Feeding Station"
        }
    }

    var icon: String {
        switch self {
        case .shallowArea:    return "water.waves"
        case .deepArea:       return "arrow.down.to.line"
        case .filterZone:     return "line.3.horizontal.decrease.circle"
        case .streamSection:  return "wind"
        case .plantingArea:   return "leaf"
        case .oxygenPoint:    return "bubble.right"
        case .feedingStation: return "fork.knife"
        }
    }

    var colorHex: String {
        switch self {
        case .shallowArea:    return "#5AC8FA"
        case .deepArea:       return "#0A84FF"
        case .filterZone:     return "#34C759"
        case .streamSection:  return "#30D158"
        case .plantingArea:   return "#30D158"
        case .oxygenPoint:    return "#BF5AF2"
        case .feedingStation: return "#FF9F0A"
        }
    }
}

// MARK: - Pond

struct Pond: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: String
    var name: String
    var type: PondType
    var volumeLiters: Double?
    var surfaceAreaSqm: Double?
    var maxDepthCm: Double?
    var photoUrl: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var haInstanceId: String?

    init(
        id: UUID = UUID(),
        propertyId: String,
        name: String,
        type: PondType = .ornamental,
        volumeLiters: Double? = nil,
        surfaceAreaSqm: Double? = nil,
        maxDepthCm: Double? = nil,
        photoUrl: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        haInstanceId: String? = nil
    ) {
        self.id = id
        self.propertyId = propertyId
        self.name = name
        self.type = type
        self.volumeLiters = volumeLiters
        self.surfaceAreaSqm = surfaceAreaSqm
        self.maxDepthCm = maxDepthCm
        self.photoUrl = photoUrl
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.haInstanceId = haInstanceId
    }
}

// MARK: - Pond Zone (sub-areas within a pond)

struct PondZone: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var name: String
    var zoneType: PondZoneType
    var positionX: Double       // 0.0–1.0 relative to pond canvas
    var positionY: Double
    var radiusPercent: Double   // 0.0–1.0 relative to pond width
    var colorHex: String
    var notes: String?

    init(
        id: UUID = UUID(),
        pondId: UUID,
        name: String,
        zoneType: PondZoneType,
        positionX: Double = 0.5,
        positionY: Double = 0.5,
        radiusPercent: Double = 0.2,
        colorHex: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.pondId = pondId
        self.name = name
        self.zoneType = zoneType
        self.positionX = positionX
        self.positionY = positionY
        self.radiusPercent = radiusPercent
        self.colorHex = colorHex ?? zoneType.colorHex
        self.notes = notes
    }
}

// MARK: - Water Parameters

enum WaterParameter: String, Codable, CaseIterable {
    case temperature     = "temperature"
    case ph              = "ph"
    case dissolvedOxygen = "dissolved_oxygen"
    case turbidity       = "turbidity"
    case salinity        = "salinity"
    case conductivity    = "conductivity"
    case waterLevel      = "water_level"
    case ammonia         = "ammonia"
    case nitrite         = "nitrite"
    case nitrate         = "nitrate"
    case phosphate       = "phosphate"
    case orp             = "orp"

    var displayName: String {
        switch self {
        case .temperature:     return "Water Temperature"
        case .ph:              return "pH"
        case .dissolvedOxygen: return "Dissolved Oxygen"
        case .turbidity:       return "Turbidity"
        case .salinity:        return "Salinity"
        case .conductivity:    return "Conductivity"
        case .waterLevel:      return "Water Level"
        case .ammonia:         return "Ammonia"
        case .nitrite:         return "Nitrite"
        case .nitrate:         return "Nitrate"
        case .phosphate:       return "Phosphate"
        case .orp:             return "ORP"
        }
    }

    var unit: String {
        switch self {
        case .temperature:     return "°C"
        case .ph:              return "pH"
        case .dissolvedOxygen: return "mg/L"
        case .turbidity:       return "NTU"
        case .salinity:        return "ppt"
        case .conductivity:    return "μS/cm"
        case .waterLevel:      return "cm"
        case .ammonia:         return "mg/L"
        case .nitrite:         return "mg/L"
        case .nitrate:         return "mg/L"
        case .phosphate:       return "mg/L"
        case .orp:             return "mV"
        }
    }

    var icon: String {
        switch self {
        case .temperature:     return "thermometer.medium"
        case .ph:              return "atom"
        case .dissolvedOxygen: return "bubbles.and.sparkles"
        case .turbidity:       return "eye.slash"
        case .salinity:        return "drop.halffull"
        case .conductivity:    return "bolt.fill"
        case .waterLevel:      return "water.waves"
        case .ammonia:         return "exclamationmark.triangle.fill"
        case .nitrite:         return "exclamationmark.triangle"
        case .nitrate:         return "chart.bar"
        case .phosphate:       return "leaf"
        case .orp:             return "waveform.path.ecg"
        }
    }

    var colorHex: String {
        switch self {
        case .temperature:     return "#FF6B35"
        case .ph:              return "#BF5AF2"
        case .dissolvedOxygen: return "#30D158"
        case .turbidity:       return "#8E8E93"
        case .salinity:        return "#30B0C7"
        case .conductivity:    return "#FFD60A"
        case .waterLevel:      return "#0A84FF"
        case .ammonia:         return "#FF3B30"
        case .nitrite:         return "#FF9F0A"
        case .nitrate:         return "#34C759"
        case .phosphate:       return "#5AC8FA"
        case .orp:             return "#636366"
        }
    }

    // Healthy ranges for koi ponds (used for alert logic)
    var koiHealthyRange: ClosedRange<Double>? {
        switch self {
        case .temperature:     return 18...26
        case .ph:              return 7.0...8.5
        case .dissolvedOxygen: return 8...14
        case .turbidity:       return 0...30
        case .salinity:        return 0...0.1
        case .conductivity:    return 100...500
        case .waterLevel:      return nil
        case .ammonia:         return 0...0.25
        case .nitrite:         return 0...0.25
        case .nitrate:         return 0...60
        case .phosphate:       return 0...0.5
        case .orp:             return 200...500
        }
    }

    var criticalLow: Double? {
        switch self {
        case .ph:              return 6.0
        case .dissolvedOxygen: return 4.0
        case .ammonia:         return nil
        case .nitrite:         return nil
        default:               return nil
        }
    }

    var criticalHigh: Double? {
        switch self {
        case .temperature:     return 30.0
        case .ph:              return 9.5
        case .ammonia:         return 1.0
        case .nitrite:         return 1.0
        case .nitrate:         return 120.0
        default:               return nil
        }
    }
}

// MARK: - Water Quality Reading

enum ReadingSource: Codable, Hashable {
    case manual
    case esphome(entityId: String)
    case haEntity(entityId: String)
    case predicted
}

struct WaterQualityReading: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var parameter: WaterParameter
    var value: Double
    var recordedAt: Date
    var source: ReadingSource

    init(
        id: UUID = UUID(),
        pondId: UUID,
        parameter: WaterParameter,
        value: Double,
        recordedAt: Date = Date(),
        source: ReadingSource = .manual
    ) {
        self.id = id
        self.pondId = pondId
        self.parameter = parameter
        self.value = value
        self.recordedAt = recordedAt
        self.source = source
    }
}

// MARK: - Pond Equipment

enum EquipmentType: String, Codable, CaseIterable {
    case pump       = "pump"
    case filter     = "filter"
    case aerator    = "aerator"
    case uv         = "uv_sterilizer"
    case heater     = "heater"
    case chiller    = "chiller"
    case feeder     = "auto_feeder"
    case camera     = "camera"
    case light      = "light"
    case sensor     = "sensor"
    case dosing     = "dosing_pump"
    case skimmer    = "skimmer"

    var displayName: String {
        switch self {
        case .pump:    return "Pump"
        case .filter:  return "Filter"
        case .aerator: return "Aerator"
        case .uv:      return "UV Sterilizer"
        case .heater:  return "Heater"
        case .chiller: return "Chiller"
        case .feeder:  return "Auto Feeder"
        case .camera:  return "Camera"
        case .light:   return "Light"
        case .sensor:  return "Sensor"
        case .dosing:  return "Dosing Pump"
        case .skimmer: return "Skimmer"
        }
    }

    var icon: String {
        switch self {
        case .pump:    return "arrow.triangle.2.circlepath"
        case .filter:  return "line.3.horizontal.decrease.circle"
        case .aerator: return "bubble.right.fill"
        case .uv:      return "sun.max.fill"
        case .heater:  return "thermometer.high"
        case .chiller: return "thermometer.snowflake"
        case .feeder:  return "fork.knife"
        case .camera:  return "camera.fill"
        case .light:   return "lightbulb.fill"
        case .sensor:  return "sensor.tag.radiowaves.forward.fill"
        case .dosing:  return "drop.fill"
        case .skimmer: return "water.waves"
        }
    }
}

struct PondEquipment: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var name: String
    var type: EquipmentType
    var brand: String?
    var model: String?
    var positionX: Double
    var positionY: Double
    var isRunning: Bool
    var haEntityId: String?
    var powerWatts: Double?
    var lastMaintenanceAt: Date?
    var warrantyUntil: Date?
    var notes: String?

    init(
        id: UUID = UUID(),
        pondId: UUID,
        name: String,
        type: EquipmentType,
        brand: String? = nil,
        model: String? = nil,
        positionX: Double = 0.5,
        positionY: Double = 0.5,
        isRunning: Bool = false,
        haEntityId: String? = nil,
        powerWatts: Double? = nil,
        lastMaintenanceAt: Date? = nil,
        warrantyUntil: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.pondId = pondId
        self.name = name
        self.type = type
        self.brand = brand
        self.model = model
        self.positionX = positionX
        self.positionY = positionY
        self.isRunning = isRunning
        self.haEntityId = haEntityId
        self.powerWatts = powerWatts
        self.lastMaintenanceAt = lastMaintenanceAt
        self.warrantyUntil = warrantyUntil
        self.notes = notes
    }
}

// MARK: - Fish Species

struct FishSpecies: Identifiable, Codable, Hashable {
    var id: String               // e.g. "cyprinus-carpio-koi"
    var commonName: String
    var latinName: String
    var icon: String             // SF Symbol
    var minTempC: Double
    var maxTempC: Double
    var idealTempC: Double
    var minPh: Double
    var maxPh: Double
    var minDissolvedOxygen: Double
    var avgLengthCm: Double
    var avgWeightKg: Double
    var category: FishCategory
    var notes: String?
}

enum FishCategory: String, Codable, CaseIterable {
    case koi          = "koi"
    case goldfish     = "goldfish"
    case carp         = "carp"
    case trout        = "trout"
    case catfish      = "catfish"
    case bass         = "bass"
    case tilapia      = "tilapia"
    case ornamental   = "ornamental"
    case predator     = "predator"
    case tropical     = "tropical"

    var displayName: String { rawValue.capitalized }
    var icon: String { "fish.fill" }
}

// MARK: - Fish Population

struct FishPopulation: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var speciesId: String
    var estimatedCount: Int
    var averageLengthCm: Double?
    var averageWeightKg: Double?
    var addedAt: Date
    var colorVariety: String?
    var sourceNotes: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        pondId: UUID,
        speciesId: String,
        estimatedCount: Int,
        averageLengthCm: Double? = nil,
        averageWeightKg: Double? = nil,
        addedAt: Date = Date(),
        colorVariety: String? = nil,
        sourceNotes: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.pondId = pondId
        self.speciesId = speciesId
        self.estimatedCount = estimatedCount
        self.averageLengthCm = averageLengthCm
        self.averageWeightKg = averageWeightKg
        self.addedAt = addedAt
        self.colorVariety = colorVariety
        self.sourceNotes = sourceNotes
        self.notes = notes
    }
}

// MARK: - Fish Journal

enum FishEvent: String, Codable, CaseIterable {
    case stocking     = "stocking"
    case harvest      = "harvest"
    case death        = "death"
    case spawn        = "spawn"
    case diseaseNote  = "disease_note"
    case treatment    = "treatment"
    case sizeCheck    = "size_check"
    case observation  = "observation"
    case waterChange  = "water_change"

    var displayName: String {
        switch self {
        case .stocking:    return "Fish Added"
        case .harvest:     return "Fish Removed"
        case .death:       return "Death"
        case .spawn:       return "Spawning"
        case .diseaseNote: return "Disease Observation"
        case .treatment:   return "Treatment Applied"
        case .sizeCheck:   return "Size Measurement"
        case .observation: return "Observation"
        case .waterChange: return "Water Change"
        }
    }

    var icon: String {
        switch self {
        case .stocking:    return "plus.circle.fill"
        case .harvest:     return "minus.circle.fill"
        case .death:       return "xmark.circle.fill"
        case .spawn:       return "heart.fill"
        case .diseaseNote: return "exclamationmark.triangle.fill"
        case .treatment:   return "cross.case.fill"
        case .sizeCheck:   return "ruler"
        case .observation: return "eye.fill"
        case .waterChange: return "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .stocking:    return Color(hex: "#34C759")
        case .harvest:     return Color(hex: "#FF9F0A")
        case .death:       return Color(hex: "#FF3B30")
        case .spawn:       return Color(hex: "#FF2D55")
        case .diseaseNote: return Color(hex: "#FF9F0A")
        case .treatment:   return Color(hex: "#BF5AF2")
        case .sizeCheck:   return Color(hex: "#0A84FF")
        case .observation: return Color(hex: "#636366")
        case .waterChange: return Color(hex: "#5AC8FA")
        }
    }
}

struct FishJournalEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var event: FishEvent
    var count: Int?
    var speciesId: String?
    var notes: String?
    var photoUrl: String?
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        pondId: UUID,
        event: FishEvent,
        count: Int? = nil,
        speciesId: String? = nil,
        notes: String? = nil,
        photoUrl: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.pondId = pondId
        self.event = event
        self.count = count
        self.speciesId = speciesId
        self.notes = notes
        self.photoUrl = photoUrl
        self.recordedAt = recordedAt
    }
}

// MARK: - Feeding System

enum FoodType: String, Codable, CaseIterable {
    case pellet    = "pellet"
    case flake     = "flake"
    case live      = "live"
    case frozen    = "frozen"
    case vegetable = "vegetable"
    case treat     = "treat"
    case growth    = "growth"
    case wheat     = "wheat_germ"

    var displayName: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }

    var icon: String {
        switch self {
        case .pellet:    return "circle.fill"
        case .flake:     return "leaf.fill"
        case .live:      return "ant.fill"
        case .frozen:    return "snowflake"
        case .vegetable: return "carrot.fill"
        case .treat:     return "star.fill"
        case .growth:    return "arrow.up.circle.fill"
        case .wheat:     return "leaf"
        }
    }
}

struct FeedingSchedule: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var name: String
    var hour: Int
    var minute: Int
    var foodType: FoodType
    var amountGrams: Double
    var isActive: Bool
    var daysOfWeek: [Int]          // 1=Sun, 2=Mon … 7=Sat; empty = every day
    var haFeederEntityId: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        pondId: UUID,
        name: String,
        hour: Int,
        minute: Int,
        foodType: FoodType = .pellet,
        amountGrams: Double,
        isActive: Bool = true,
        daysOfWeek: [Int] = [],
        haFeederEntityId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.pondId = pondId
        self.name = name
        self.hour = hour
        self.minute = minute
        self.foodType = foodType
        self.amountGrams = amountGrams
        self.isActive = isActive
        self.daysOfWeek = daysOfWeek
        self.haFeederEntityId = haFeederEntityId
        self.notes = notes
    }
}

enum FeedingSource: String, Codable {
    case manual    = "manual"
    case automatic = "automatic"
    case aria      = "aria"
}

struct FeedingLog: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var scheduleId: UUID?
    var foodType: FoodType
    var amountGrams: Double
    var fedAt: Date
    var source: FeedingSource
    var notes: String?

    init(
        id: UUID = UUID(),
        pondId: UUID,
        scheduleId: UUID? = nil,
        foodType: FoodType,
        amountGrams: Double,
        fedAt: Date = Date(),
        source: FeedingSource = .manual,
        notes: String? = nil
    ) {
        self.id = id
        self.pondId = pondId
        self.scheduleId = scheduleId
        self.foodType = foodType
        self.amountGrams = amountGrams
        self.fedAt = fedAt
        self.source = source
        self.notes = notes
    }
}

// MARK: - Pond Alert

enum PondAlertSeverity: String, Codable, Comparable, CaseIterable {
    case info     = "info"
    case warning  = "warning"
    case critical = "critical"

    static func < (lhs: PondAlertSeverity, rhs: PondAlertSeverity) -> Bool {
        let order: [PondAlertSeverity] = [.info, .warning, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    var color: Color {
        switch self {
        case .info:     return Color(hex: "#0A84FF")
        case .warning:  return Color(hex: "#FF9F0A")
        case .critical: return Color(hex: "#FF3B30")
        }
    }

    var icon: String {
        switch self {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

struct PondAlert: Identifiable, Codable, Hashable {
    var id: UUID
    var pondId: UUID
    var parameter: WaterParameter?
    var severity: PondAlertSeverity
    var title: String
    var message: String
    var triggeredAt: Date
    var resolvedAt: Date?
    var isAcknowledged: Bool

    var isActive: Bool { resolvedAt == nil }

    init(
        id: UUID = UUID(),
        pondId: UUID,
        parameter: WaterParameter? = nil,
        severity: PondAlertSeverity,
        title: String,
        message: String,
        triggeredAt: Date = Date(),
        resolvedAt: Date? = nil,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.pondId = pondId
        self.parameter = parameter
        self.severity = severity
        self.title = title
        self.message = message
        self.triggeredAt = triggeredAt
        self.resolvedAt = resolvedAt
        self.isAcknowledged = isAcknowledged
    }
}

// MARK: - Pond Health Snapshot

struct PondHealthSnapshot: Codable {
    var pondId: UUID
    var overallScore: Int         // 0–100
    var waterQualityScore: Int
    var fishHealthScore: Int
    var equipmentScore: Int
    var alerts: [PondAlert]
    var generatedAt: Date

    var healthLabel: String {
        switch overallScore {
        case 80...100: return "Excellent"
        case 65...79:  return "Good"
        case 50...64:  return "Fair"
        case 35...49:  return "Needs Attention"
        default:       return "Critical"
        }
    }

    var healthColor: Color {
        switch overallScore {
        case 80...100: return Color(hex: "#34C759")
        case 65...79:  return Color(hex: "#30D158")
        case 50...64:  return Color(hex: "#FF9F0A")
        case 35...49:  return Color(hex: "#FF6B35")
        default:       return Color(hex: "#FF3B30")
        }
    }
}

// MARK: - Payload types (for Supabase writes)

struct NewPond: Codable {
    let propertyId: String
    let name: String
    let type: String
    let volumeLiters: Double?
    let surfaceAreaSqm: Double?
    let maxDepthCm: Double?
    let haInstanceId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case name, type
        case volumeLiters = "volume_liters"
        case surfaceAreaSqm = "surface_area_sqm"
        case maxDepthCm = "max_depth_cm"
        case haInstanceId = "ha_instance_id"
        case notes
    }
}

struct NewWaterQualityReading: Codable {
    let pondId: String
    let parameter: String
    let value: Double
    let source: String
    let recordedAt: String

    enum CodingKeys: String, CodingKey {
        case pondId = "pond_id"
        case parameter, value, source
        case recordedAt = "recorded_at"
    }
}

struct NewFeedingLog: Codable {
    let pondId: String
    let scheduleId: String?
    let foodType: String
    let amountGrams: Double
    let source: String

    enum CodingKeys: String, CodingKey {
        case pondId = "pond_id"
        case scheduleId = "schedule_id"
        case foodType = "food_type"
        case amountGrams = "amount_grams"
        case source
    }
}

// MARK: - Color extension (reuse existing pattern from PRVIO codebase)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

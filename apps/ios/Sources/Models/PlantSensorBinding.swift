import Foundation
import SwiftUI

// MARK: - Plant ↔ sensor binding (Plant OS P3, Level 3)
//
// One row of `plant_sensors`: it attaches a real IoT hub sensor to a plant so
// the care page can compare a species requirement against a live reading. The
// binding is property-scoped (RLS by property membership); the sensor itself
// lives in the local IoT hub, addressed by the stable `sensorRef`
// (see IoTSensor.stableRef). If a device opening the page does not know that
// sensor, the UI shows the requirement only — never a fabricated reading.

/// The three care metrics that can be compared against a live sensor. Its raw
/// value matches both the `plant_sensors.metric` column and the sensor filter.
enum PlantCareMetric: String, CaseIterable, Identifiable {
    case light, temperature, humidity
    var id: String { rawValue }

    /// The IoT sensor type this care metric compares against.
    var sensorType: IoTSensor.SensorType {
        switch self {
        case .light:       return .light
        case .temperature: return .temperature
        case .humidity:    return .humidity
        }
    }

    /// Whether a sensor of the given type can drive this metric.
    func matches(_ type: IoTSensor.SensorType) -> Bool { type == sensorType }

    var title: LocalizedStringKey {
        switch self {
        case .light:       return "plant_care_light"
        case .temperature: return "plant_care_temperature"
        case .humidity:    return "plant_care_humidity"
        }
    }

    var icon: String {
        switch self {
        case .light:       return "sun.max.fill"
        case .temperature: return "thermometer.medium"
        case .humidity:    return "humidity.fill"
        }
    }
}

struct PlantSensorBinding: Identifiable, Codable, Hashable {
    let id: UUID
    let plantId: UUID
    let propertyId: UUID
    let sensorRef: String
    let metric: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case plantId    = "plant_id"
        case propertyId = "property_id"
        case sensorRef  = "sensor_ref"
        case metric
        case createdAt  = "created_at"
    }

    /// Typed metric, if it is one we understand.
    var careMetric: PlantCareMetric? { PlantCareMetric(rawValue: metric) }
}

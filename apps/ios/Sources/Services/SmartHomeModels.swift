import Foundation
import HomeKit

// MARK: - Unified smart-home device model (Smart Home S1)
//
// PRVIO controls devices from two providers: the user's HomeKit/Matter
// accessories (HMHomeManager) and the property's own IoT hub (sensors +
// Modbus/HTTP relays). The UI never talks to a provider — it renders ONE
// `SmartDevice` whose `capabilities` say exactly what controls exist, so a
// control is drawn only when the device genuinely supports it (honesty law:
// no dead sliders on relays, no fake temperature dials without a thermostat).

/// What a device IS — drives the icon and the type-grouped dashboard cards.
enum SmartDeviceKind: String, CaseIterable, Identifiable {
    case light, outlet, switcher, thermostat, sensor, camera, lock, cover, other
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .light:      return "lightbulb.fill"
        case .outlet:     return "powerplug.fill"
        case .switcher:   return "switch.2"
        case .thermostat: return "thermometer.medium"
        case .sensor:     return "sensor.fill"
        case .camera:     return "video.fill"
        case .lock:       return "lock.fill"
        case .cover:      return "blinds.horizontal.closed"
        case .other:      return "cube.fill"
        }
    }

    var titleKey: String {
        switch self {
        case .light:      return "sh_kind_lights"
        case .outlet:     return "sh_kind_outlets"
        case .switcher:   return "sh_kind_switches"
        case .thermostat: return "sh_kind_thermostats"
        case .sensor:     return "sh_kind_sensors"
        case .camera:     return "sh_kind_cameras"
        case .lock:       return "sh_kind_locks"
        case .cover:      return "sh_kind_covers"
        case .other:      return "sh_kind_other"
        }
    }
}

/// What a device can DO — each case unlocks exactly one control surface.
enum SmartDeviceCapability: Hashable {
    case power
    case brightness
    case color
    case targetTemperature
    case lock
    /// A live reading (temperature, humidity, light…) with its unit.
    case reading
}

/// One device, provider-agnostic. Identity is stable per provider object so
/// SwiftUI diffing survives rebuilds of the aggregated list.
struct SmartDevice: Identifiable {
    /// The provider object behind this device — the routing key for actions.
    enum Backing {
        case homeKit(HMAccessory)
        case iotRelay(IoTActuator)
        case iotSensor(IoTSensor)
    }

    let id: String
    let name: String
    /// HomeKit room name / the IoT sensor's linked zone; nil = unassigned.
    let room: String?
    let kind: SmartDeviceKind
    let capabilities: Set<SmartDeviceCapability>
    let isReachable: Bool
    /// Power state when the device reports one; nil = unknown (never guessed).
    let isOn: Bool?
    /// Live sensor value + unit, only for `.reading` devices.
    let readingValue: Double?
    let readingUnit: String?
    let backing: Backing

    var hasPower: Bool { capabilities.contains(.power) }
}

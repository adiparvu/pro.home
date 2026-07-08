import Foundation
import SwiftUI

// MARK: - Device

struct IoTDevice: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var type: DeviceType
    var host: String
    var port: Int
    var connectionProtocol: ConnectionProtocol
    var apiPath: String = "/sensors"
    var unitId: Int = 1
    var isConnected: Bool = false
    var lastSeen: Date?

    enum DeviceType: String, Codable, CaseIterable {
        case esp32 = "esp32"
        case raspberryPi = "raspberry_pi"
        case rs485Modbus = "rs485_modbus"

        var label: String {
            switch self {
            case .esp32:        return "ESP32"
            case .raspberryPi:  return "Raspberry Pi"
            case .rs485Modbus:  return "RS485 Modbus"
            }
        }
        var icon: String {
            switch self {
            case .esp32:        return "cpu.fill"
            case .raspberryPi:  return "server.rack"
            case .rs485Modbus:  return "cable.connector.horizontal"
            }
        }
        var color: Color {
            switch self {
            case .esp32:        return Color(red: 0.05, green: 0.75, blue: 0.45)
            case .raspberryPi:  return Color(red: 0.85, green: 0.15, blue: 0.35)
            case .rs485Modbus:  return Color.brandSkyBlue
            }
        }
        var defaultPort: Int {
            switch self {
            case .esp32, .raspberryPi: return 80
            case .rs485Modbus:         return 502
            }
        }
        var defaultProtocol: ConnectionProtocol {
            switch self {
            case .esp32, .raspberryPi: return .http
            case .rs485Modbus:         return .modbusTCP
            }
        }
    }

    enum ConnectionProtocol: String, Codable, CaseIterable {
        case http      = "HTTP REST"
        case modbusTCP = "Modbus TCP"

        var hint: String {
            switch self {
            case .http:      return "ESP32/Flask/FastAPI — GET /sensors → JSON"
            case .modbusTCP: return "RTU over TCP gateway, port 502 standard"
            }
        }
    }

    var baseURL: String { "http://\(host):\(port)" }
}

// MARK: - Sensor

struct IoTSensor: Identifiable, Codable {
    var id: UUID = UUID()
    var deviceId: UUID
    var remoteId: String
    var name: String
    var type: SensorType
    var unit: String
    var value: Double?
    var lastUpdated: Date?
    var linkedZoneName: String = ""
    var alertMin: Double?
    var alertMax: Double?
    var modbusAddress: Int?
    var modbusScale: Double = 1.0
    /// User-set tag: this power/energy sensor measures production (solar
    /// inverter output) rather than consumption. Optional so sensor records
    /// saved before the field existed still decode.
    var isProduction: Bool?

    enum SensorType: String, Codable, CaseIterable {
        case temperature, humidity, motion, doorWindow
        case co2, pressure, light, noise
        case current, voltage, power, energy
        case water, smoke, gas, custom

        var icon: String {
            switch self {
            case .temperature: return "thermometer.medium"
            case .humidity:    return "drop.fill"
            case .motion:      return "figure.walk"
            case .doorWindow:  return "door.left.hand.open"
            case .co2:         return "cloud.fill"
            case .pressure:    return "gauge"
            case .light:       return "lightbulb.fill"
            case .noise:       return "waveform"
            case .current:     return "bolt.fill"
            case .voltage:     return "bolt.badge.a.fill"
            case .power:       return "bolt.horizontal.fill"
            case .energy:      return "bolt.horizontal.circle.fill"
            case .water:       return "drop.triangle.fill"
            case .smoke:       return "smoke.fill"
            case .gas:         return "flame.fill"
            case .custom:      return "sensor.tag.radiowaves.forward.fill"
            }
        }
        var color: Color {
            switch self {
            case .temperature: return Color(red: 1.0, green: 0.35, blue: 0.15)
            case .humidity:    return Color(red: 0.15, green: 0.55, blue: 0.95)
            case .motion:      return Color.brandPurple
            case .doorWindow:  return Color(red: 0.35, green: 0.75, blue: 0.55)
            case .co2:         return Color(red: 0.35, green: 0.65, blue: 0.45)
            case .pressure:    return Color(red: 0.55, green: 0.55, blue: 0.95)
            case .light:       return Color(red: 0.95, green: 0.85, blue: 0.15)
            case .noise:       return Color(red: 0.75, green: 0.45, blue: 0.95)
            case .current:     return Color(red: 0.95, green: 0.75, blue: 0.15)
            case .voltage:     return Color(red: 0.95, green: 0.55, blue: 0.15)
            case .power:       return Color.brandWarning
            case .energy:      return Color(red: 0.35, green: 0.85, blue: 0.45)
            case .water:       return Color(red: 0.15, green: 0.65, blue: 0.95)
            case .smoke:       return Color(red: 0.65, green: 0.55, blue: 0.45)
            case .gas:         return Color(red: 1.0, green: 0.45, blue: 0.15)
            case .custom:      return Color.gray
            }
        }
        var label: String { rawValue.capitalized }
        var defaultUnit: String {
            switch self {
            case .temperature: return "°C"
            case .humidity:    return "%"
            case .motion:      return ""
            case .doorWindow:  return ""
            case .co2:         return "ppm"
            case .pressure:    return "hPa"
            case .light:       return "lux"
            case .noise:       return "dB"
            case .current:     return "A"
            case .voltage:     return "V"
            case .power:       return "W"
            case .energy:      return "kWh"
            case .water:       return "L"
            case .smoke:       return ""
            case .gas:         return "ppm"
            case .custom:      return ""
            }
        }
    }

    var displayValue: String {
        guard let v = value else { return "—" }
        switch type {
        case .motion:
            return v > 0.5 ? "Detected" : "Clear"
        case .doorWindow:
            return v > 0.5 ? "Open" : "Closed"
        case .smoke:
            return v > 0.5 ? "Alarm" : "Clear"
        default:
            return String(format: "%.1f", v) + (unit.isEmpty ? "" : " \(unit)")
        }
    }

    var isAlerting: Bool {
        guard let v = value else { return false }
        if let min = alertMin, v < min { return true }
        if let max = alertMax, v > max { return true }
        return false
    }

    /// What the Live Activity layer treats as "alerting": a crossed
    /// user-set threshold, or a binary hazard sensor reporting positive
    /// (smoke needs no threshold to be an alarm).
    var isLiveAlerting: Bool {
        if isAlerting { return true }
        if type == .smoke, let v = value, v > 0.5 { return true }
        return false
    }

    /// Hazard classes get the critical (red, alerting) treatment; everything
    /// else is a warning.
    var isCriticalAlert: Bool {
        isLiveAlerting && (type == .smoke || type == .gas || type == .water)
    }

    /// Eligible for the energy dashboard (instantaneous draw in watts).
    var isPowerReading: Bool { type == .power }

    /// A durable, installation-local identity for binding this sensor to a
    /// plant (Plant OS P3). Sensors are persisted client-side (UserDefaults
    /// JSON), not in a synced table, and the poller matches a sensor by
    /// (deviceId, remoteId) — updating it in place — so that tuple, not the
    /// random `id` (which is regenerated if a sensor is deleted and later
    /// rediscovered), is the stable key. Format: "{deviceId-uuid}:{remoteId}".
    var stableRef: String { "\(deviceId.uuidString):\(remoteId)" }
}

// MARK: - Actuator
//
// The write half of the IoT layer: a relay or a cover (garage door, gate)
// the controller can drive. Commands are capability-gated per kind — the UI
// never renders a button the actuator didn't declare.

struct IoTActuator: Identifiable, Codable {
    var id: UUID = UUID()
    var deviceId: UUID
    /// Identifier the controller firmware knows ("garage", relay index…).
    var remoteId: String
    var name: String
    var kind: ActuatorKind
    /// Last commanded relay state (best-effort; nil until first command).
    var isOn: Bool?
    /// Modbus target: coil address for relays (FC 05), holding register for
    /// covers (FC 06, value 1 = open / 2 = close / 0 = stop).
    var modbusAddress: Int?
    /// Optional door/window sensor that confirms a cover's real end state —
    /// without it the app only ever claims "command finished", never "open".
    var feedbackSensorId: UUID?

    enum ActuatorKind: String, Codable, CaseIterable, Identifiable {
        case relay, cover
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .relay: return "iot_actuator_relay"
            case .cover: return "iot_actuator_cover"
            }
        }
        var icon: String {
            switch self {
            case .relay: return "power"
            case .cover: return "door.garage.closed"
            }
        }
        var commands: [ActuatorCommand] {
            switch self {
            case .relay: return [.turnOn, .turnOff]
            case .cover: return [.open, .close, .stop]
            }
        }
    }
}

enum ActuatorCommand: String, Codable, CaseIterable {
    case turnOn = "on"
    case turnOff = "off"
    case open, close, stop

    var label: LocalizedStringKey {
        switch self {
        case .turnOn:  return "iot_cmd_on"
        case .turnOff: return "iot_cmd_off"
        case .open:    return "iot_cmd_open"
        case .close:   return "iot_cmd_close"
        case .stop:    return "iot_cmd_stop"
        }
    }
    var icon: String {
        switch self {
        case .turnOn:  return "power.circle.fill"
        case .turnOff: return "power.circle"
        case .open:    return "arrow.up.circle.fill"
        case .close:   return "arrow.down.circle.fill"
        case .stop:    return "stop.circle.fill"
        }
    }
}

// MARK: - Automation

struct IoTAutomation: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var isEnabled: Bool = true
    var triggerSensorId: UUID?
    var triggerSensorName: String = ""
    var condition: TriggerCondition = .above
    var triggerValue: Double = 0
    var action: AutomationAction = .sendNotification
    var actionPayload: String = ""

    enum TriggerCondition: String, Codable, CaseIterable {
        case above  = ">"
        case below  = "<"
        case equals = "="
        var label: String { rawValue }
    }

    enum AutomationAction: String, Codable, CaseIterable {
        case sendNotification = "Send Notification"
        case createTask       = "Create Task"
        case callWebhook      = "Call Webhook"
        /// POSTs the sensor event to the account's iot-event webhook — the
        /// same endpoint a controller can call directly with the app closed.
        case phoneAlert       = "Phone Alert"
        var icon: String {
            switch self {
            case .sendNotification: return "bell.fill"
            case .createTask:       return "checklist"
            case .callWebhook:      return "arrow.up.circle.fill"
            case .phoneAlert:       return "iphone.radiowaves.left.and.right"
            }
        }
    }

    var conditionDescription: String {
        "\(triggerSensorName) \(condition.rawValue) \(String(format: "%.1f", triggerValue))"
    }
}

// MARK: - Plant automation bridge (Plant OS P6)
//
// The transient, engine-side shape of a per-plant automation rule. Per-plant
// rules are persisted server-side (`plant_automations`) as the household-synced
// source of truth; `PlantAutomationService` resolves each active rule's bound
// sensor to a live sensor on THIS device and hands the resolved rules to
// `IoTService`, which evaluates them on every sensor poll using the SAME firing
// path as native IoT automations. A rule whose sensor is not present locally is
// simply never resolved into one of these — so it is never fired here, and the
// UI can say so honestly (no fabricated reading).
struct IoTPlantRule: Identifiable {
    let id: UUID              // the plant_automations row id (stable across polls)
    let plantId: UUID
    let name: String
    let triggerSensorId: UUID // resolved live sensor on this device
    let condition: IoTAutomation.TriggerCondition
    let threshold: Double
    let action: IoTAutomation.AutomationAction
    let payload: String
    /// Resolved real relay actuator to drive when the rule fires, if any. Only
    /// ever set when a matching actuator actually exists on this device.
    let actuatorId: UUID?
}

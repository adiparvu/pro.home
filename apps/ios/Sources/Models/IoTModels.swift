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
            case .rs485Modbus:  return Color(red: 0.35, green: 0.55, blue: 0.95)
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
            case .motion:      return Color(red: 0.55, green: 0.35, blue: 0.95)
            case .doorWindow:  return Color(red: 0.35, green: 0.75, blue: 0.55)
            case .co2:         return Color(red: 0.35, green: 0.65, blue: 0.45)
            case .pressure:    return Color(red: 0.55, green: 0.55, blue: 0.95)
            case .light:       return Color(red: 0.95, green: 0.85, blue: 0.15)
            case .noise:       return Color(red: 0.75, green: 0.45, blue: 0.95)
            case .current:     return Color(red: 0.95, green: 0.75, blue: 0.15)
            case .voltage:     return Color(red: 0.95, green: 0.55, blue: 0.15)
            case .power:       return Color(red: 0.95, green: 0.45, blue: 0.15)
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
        var icon: String {
            switch self {
            case .sendNotification: return "bell.fill"
            case .createTask:       return "checklist"
            case .callWebhook:      return "arrow.up.circle.fill"
            }
        }
    }

    var conditionDescription: String {
        "\(triggerSensorName) \(condition.rawValue) \(String(format: "%.1f", triggerValue))"
    }
}

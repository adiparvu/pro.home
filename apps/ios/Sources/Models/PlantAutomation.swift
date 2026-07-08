import SwiftUI

// MARK: - Per-plant automation (Plant OS P6, Level 6)
//
// One row of `plant_automations`: a rule that watches a plant's BOUND IoT
// sensor (the same P3 binding, addressed by its stable installation-local
// `sensorRef`) and, when a threshold is crossed, fires one action through the
// EXISTING IoT hub automation engine (IoTService) — never a second engine.
//
// Honesty law (central to this phase):
//   • A rule can only be EVALUATED on a device that actually knows the bound
//     sensor. Elsewhere the plant page lists the rule but marks it as running
//     on the device that owns the sensor — it never fabricates a reading.
//   • The `.device` action does not claim native HomeKit. It rides the real
//     actuator layer (a relay on a controller, via `actuatorRef`) or an
//     outbound webhook (Homebridge / Shortcuts) — both reachable by the app.
//     Native HomeKit is a separate future phase and is never implied.

/// How a live reading is compared against the rule's threshold. Mirrors the
/// IoT engine's `IoTAutomation.TriggerCondition` (we reuse that engine to
/// evaluate) but is a plant-local, localizable type.
enum PlantAutomationComparison: String, CaseIterable, Identifiable, Codable {
    case above, below
    var id: String { rawValue }

    var symbol: String { self == .above ? ">" : "<" }

    var title: LocalizedStringKey {
        switch self {
        case .above: return "plant_auto_above"
        case .below: return "plant_auto_below"
        }
    }
}

/// What a fired rule does. Every case maps 1:1 onto a real capability of the
/// existing IoT automation engine — no case promises something the app can't
/// perform.
enum PlantAutomationAction: String, CaseIterable, Identifiable, Codable {
    case notify        // local notification
    case task          // creates a maintenance task
    case webhook       // outbound HTTP call (Homebridge / Shortcuts / relay bridge)
    case phoneAlert    // pushes through the account's iot-event webhook (works with app closed)
    case device        // drives a real relay (actuatorRef) or a webhook — NOT HomeKit

    var id: String { rawValue }

    /// Wire value stored in `plant_automations.action`.
    var wire: String {
        switch self {
        case .notify:     return "notify"
        case .task:       return "task"
        case .webhook:    return "webhook"
        case .phoneAlert: return "phone_alert"
        case .device:     return "device"
        }
    }

    init?(wire: String) {
        switch wire {
        case "notify":      self = .notify
        case "task":        self = .task
        case "webhook":     self = .webhook
        case "phone_alert": self = .phoneAlert
        case "device":      self = .device
        default:            return nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .notify:     return "plant_auto_action_notify"
        case .task:       return "plant_auto_action_task"
        case .webhook:    return "plant_auto_action_webhook"
        case .phoneAlert: return "plant_auto_action_phone"
        case .device:     return "plant_auto_action_device"
        }
    }

    var icon: String {
        switch self {
        case .notify:     return "bell.fill"
        case .task:       return "checklist"
        case .webhook:    return "arrow.up.forward.app.fill"
        case .phoneAlert: return "iphone.radiowaves.left.and.right"
        case .device:     return "power"
        }
    }

    /// A one-line, honest description of what the action reaches — surfaced in
    /// the builder so the user is never misled about actuation.
    var honestyNote: LocalizedStringKey {
        switch self {
        case .notify:     return "plant_auto_note_notify"
        case .task:       return "plant_auto_note_task"
        case .webhook:    return "plant_auto_note_webhook"
        case .phoneAlert: return "plant_auto_note_phone"
        case .device:     return "plant_auto_note_device"
        }
    }

    /// Actions that need a payload (URL / title) before they can be saved.
    var needsPayload: Bool { self == .webhook }
}

// MARK: - Row model

struct PlantAutomation: Identifiable, Codable, Hashable {
    let id: UUID
    let plantId: UUID
    let propertyId: UUID
    var name: String
    var sensorRef: String
    var metric: String
    var comparison: String
    var threshold: Double
    var action: String
    var actionPayload: String?
    var actuatorRef: String?
    var isActive: Bool
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, metric, comparison, threshold, action
        case plantId       = "plant_id"
        case propertyId    = "property_id"
        case sensorRef     = "sensor_ref"
        case actionPayload = "action_payload"
        case actuatorRef   = "actuator_ref"
        case isActive      = "is_active"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }

    var metricEnum: PlantCareMetric? { PlantCareMetric(rawValue: metric) }
    var comparisonEnum: PlantAutomationComparison { PlantAutomationComparison(rawValue: comparison) ?? .below }
    var actionEnum: PlantAutomationAction { PlantAutomationAction(wire: action) ?? .notify }

    /// A compact "Light < 800 lux → Notify" style summary for the list row.
    func summary(unit: String) -> String {
        let v = threshold.formatted(.number.precision(.fractionLength(0...1)))
        let u = unit.isEmpty ? "" : " \(unit)"
        return "\(comparisonEnum.symbol) \(v)\(u)"
    }
}

// MARK: - Insert / update payloads

struct NewPlantAutomation: Encodable {
    let plantId: UUID
    let propertyId: UUID
    let name: String
    let sensorRef: String
    let metric: String
    let comparison: String
    let threshold: Double
    let action: String
    let actionPayload: String?
    let actuatorRef: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name, metric, comparison, threshold, action
        case plantId       = "plant_id"
        case propertyId    = "property_id"
        case sensorRef     = "sensor_ref"
        case actionPayload = "action_payload"
        case actuatorRef   = "actuator_ref"
        case isActive      = "is_active"
    }
}

struct PlantAutomationActiveUpdate: Encodable {
    let isActive: Bool
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case isActive  = "is_active"
        case updatedAt = "updated_at"
    }
}

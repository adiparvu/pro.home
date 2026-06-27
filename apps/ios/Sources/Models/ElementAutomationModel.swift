import Foundation
import SwiftUI

// An automation attached to a property element. Phase 1: reminder-style rules
// that schedule a local notification (and optionally create a maintenance task)
// at `nextRun`. Phase 2 will add HomeKit actions.

struct ElementAutomation: Identifiable, Codable, Equatable {
    let id: UUID
    let elementId: UUID
    let propertyId: UUID
    var name: String
    var triggerType: String      // "periodic" | "once" | "warranty"
    var intervalMonths: Int?
    var nextRun: String?         // yyyy-MM-dd
    var createsTask: Bool
    var isActive: Bool
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case elementId      = "element_id"
        case propertyId     = "property_id"
        case triggerType    = "trigger_type"
        case intervalMonths = "interval_months"
        case nextRun        = "next_run"
        case createsTask    = "creates_task"
        case isActive       = "is_active"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }

    var trigger: AutomationTrigger { AutomationTrigger(rawValue: triggerType) ?? .periodic }

    var summary: String {
        switch trigger {
        case .periodic:
            let n = intervalMonths ?? 1
            return String(format: String(localized: "Every %d month(s)"), n)
        case .once:
            return nextRun.map { String(format: String(localized: "On %@"), $0) } ?? String(localized: "One-off")
        case .warranty:
            return String(localized: "Warranty expiry alert")
        }
    }
}

enum AutomationTrigger: String, CaseIterable, Identifiable {
    case periodic, once, warranty
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .periodic: return String(localized: "Periodic")
        case .once:     return String(localized: "One-off date")
        case .warranty: return String(localized: "Warranty alert")
        }
    }
    var icon: String {
        switch self {
        case .periodic: return "repeat"
        case .once:     return "calendar"
        case .warranty: return "checkmark.seal"
        }
    }
}

struct NewElementAutomation: Encodable {
    let elementId: UUID
    let propertyId: UUID
    var name: String
    var triggerType: String
    var intervalMonths: Int?
    var nextRun: String?
    var createsTask: Bool
    var isActive: Bool
    enum CodingKeys: String, CodingKey {
        case name
        case elementId      = "element_id"
        case propertyId     = "property_id"
        case triggerType    = "trigger_type"
        case intervalMonths = "interval_months"
        case nextRun        = "next_run"
        case createsTask    = "creates_task"
        case isActive       = "is_active"
    }
}

struct ElementAutomationUpdate: Encodable {
    var name: String
    var triggerType: String
    var intervalMonths: Int?
    var nextRun: String?
    var createsTask: Bool
    var isActive: Bool
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case name
        case triggerType    = "trigger_type"
        case intervalMonths = "interval_months"
        case nextRun        = "next_run"
        case createsTask    = "creates_task"
        case isActive       = "is_active"
        case updatedAt      = "updated_at"
    }
}

import Foundation
import SwiftUI
import Observation

// Server-backed storage for the global automations page (was UserDefaults).
// Stores the AutomationRule list per property in `property_automations`.

@MainActor
@Observable
final class GlobalAutomationService {
    var error: String?

    private struct Row: Decodable {
        let name, triggerIcon, triggerLabel, conditionIcon, conditionLabel, actionIcon, actionLabel: String
        let isActive: Bool
        let colorHex: String
        enum CodingKeys: String, CodingKey {
            case name
            case triggerIcon = "trigger_icon", triggerLabel = "trigger_label"
            case conditionIcon = "condition_icon", conditionLabel = "condition_label"
            case actionIcon = "action_icon", actionLabel = "action_label"
            case isActive = "is_active", colorHex = "color_hex"
        }
    }

    private struct InsertRow: Encodable {
        let property_id: String
        let name, trigger_icon, trigger_label, condition_icon, condition_label, action_icon, action_label: String
        let is_active: Bool
        let color_hex: String
        let sort_order: Int
    }

    func load(propertyId: UUID) async -> [AutomationRule] {
        do {
            let rows: [Row] = try await supabase
                .from("property_automations")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            return rows.map { r in
                AutomationRule(
                    name: r.name,
                    triggerIcon: r.triggerIcon, triggerLabel: r.triggerLabel,
                    conditionIcon: r.conditionIcon, conditionLabel: r.conditionLabel,
                    actionIcon: r.actionIcon, actionLabel: r.actionLabel,
                    isActive: r.isActive, color: Color(hex: r.colorHex) ?? .blue
                )
            }
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    /// Replace the property's full rule set (simple + fine for small counts).
    func replaceAll(propertyId: UUID, rules: [AutomationRule]) async {
        do {
            try await supabase.from("property_automations")
                .delete().eq("property_id", value: propertyId.uuidString).execute()
            guard !rules.isEmpty else { return }
            let rows = rules.enumerated().map { idx, r in
                InsertRow(
                    property_id: propertyId.uuidString,
                    name: r.name,
                    trigger_icon: r.triggerIcon, trigger_label: r.triggerLabel,
                    condition_icon: r.conditionIcon, condition_label: r.conditionLabel,
                    action_icon: r.actionIcon, action_label: r.actionLabel,
                    is_active: r.isActive, color_hex: r.colorHex, sort_order: idx
                )
            }
            try await supabase.from("property_automations").insert(rows).execute()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

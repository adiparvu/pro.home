import Foundation
import Observation
import Supabase

// MARK: - Per-plant automations (Plant OS P6)
//
// Loads and mutates the `plant_automations` rows for one plant — the durable,
// household-synced source of truth for its rules. After every load/mutation it
// resolves each ACTIVE rule's bound sensor to a live sensor on THIS device and
// hands the resolved rules to `IoTService`, the existing IoT hub automation
// engine, which is what actually evaluates and fires them on each sensor poll.
//
// Honesty law: a rule whose bound sensor is not present on this device is kept
// in the list (it still runs on the device that owns the sensor) but is NOT
// pushed into the engine here — so nothing is ever evaluated against a
// fabricated reading. Mirrors the @Observable, load-on-task style of
// PlantSensorService / PlantEventService.

@MainActor
@Observable
final class PlantAutomationService {
    private(set) var automations: [PlantAutomation] = []
    var isLoading = false

    // MARK: Load

    func load(plantId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        automations = (try? await supabase.from("plant_automations")
            .select()
            .eq("plant_id", value: plantId.uuidString)
            .order("created_at", ascending: false)
            .execute().value) ?? []
        syncEngine(plantId: plantId)
    }

    // MARK: Mutations

    @discardableResult
    func add(_ payload: NewPlantAutomation) async -> Bool {
        do {
            let row: PlantAutomation = try await supabase.from("plant_automations")
                .insert(payload).select().single().execute().value
            automations.insert(row, at: 0)
            syncEngine(plantId: row.plantId)
            return true
        } catch {
            return false
        }
    }

    func setActive(_ automation: PlantAutomation, active: Bool) async {
        // Optimistic local flip so the toggle + engine react instantly.
        if let i = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[i].isActive = active
        }
        syncEngine(plantId: automation.plantId)
        let payload = PlantAutomationActiveUpdate(
            isActive: active, updatedAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try await supabase.from("plant_automations").update(payload)
                .eq("id", value: automation.id.uuidString).execute()
        } catch {
            // Revert on failure so the UI never lies about persisted state.
            if let i = automations.firstIndex(where: { $0.id == automation.id }) {
                automations[i].isActive = !active
            }
            syncEngine(plantId: automation.plantId)
        }
    }

    func delete(_ automation: PlantAutomation) async {
        automations.removeAll { $0.id == automation.id }
        syncEngine(plantId: automation.plantId)
        do {
            try await supabase.from("plant_automations").delete()
                .eq("id", value: automation.id.uuidString).execute()
        } catch { /* best-effort; already gone locally */ }
    }

    // MARK: Engine bridge

    /// True when this device knows the rule's bound sensor, so the rule is
    /// actually evaluated here. When false, the plant page tells the user the
    /// rule runs on whichever device owns that sensor — never a fake reading.
    func isEvaluatedHere(_ automation: PlantAutomation) -> Bool {
        IoTService.shared.plantRuleSensorId(forRef: automation.sensorRef) != nil
    }

    /// Maps a plant action onto the existing engine's action set. `.device`
    /// rides the webhook path here (a Homebridge/Shortcuts URL in the payload);
    /// its real-relay half is driven separately by IoTService via actuatorId.
    private func engineAction(_ action: PlantAutomationAction) -> IoTAutomation.AutomationAction {
        switch action {
        case .notify:     return .sendNotification
        case .task:       return .createTask
        case .webhook:    return .callWebhook
        case .phoneAlert: return .phoneAlert
        case .device:     return .callWebhook
        }
    }

    /// Resolves this plant's active rules against live sensors and registers
    /// them with the IoT engine. Rules whose sensor is absent here are dropped
    /// from the engine set (but stay in `automations` for the list).
    private func syncEngine(plantId: UUID) {
        let iot = IoTService.shared
        let resolved: [IoTPlantRule] = automations
            .filter { $0.isActive }
            .compactMap { a in
                guard let sensorId = iot.plantRuleSensorId(forRef: a.sensorRef) else { return nil }
                let actuatorId = a.actuatorRef.flatMap { iot.actuator(forRef: $0)?.id }
                return IoTPlantRule(
                    id: a.id, plantId: a.plantId, name: a.name,
                    triggerSensorId: sensorId,
                    condition: a.comparisonEnum == .above ? .above : .below,
                    threshold: a.threshold,
                    action: engineAction(a.actionEnum),
                    payload: a.actionPayload ?? "",
                    actuatorId: actuatorId)
            }
        iot.setPlantRules(resolved, forPlant: plantId)
    }
}

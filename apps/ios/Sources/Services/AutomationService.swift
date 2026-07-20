import Foundation
import SwiftUI
import UserNotifications
import Observation

@MainActor
@Observable
final class AutomationService {
    var byElement: [UUID: [ElementAutomation]] = [:]
    var error: String?

    private let df: DateFormatter = AppDate.day

    func automations(for elementId: UUID) -> [ElementAutomation] {
        byElement[elementId] ?? []
    }

    func load(elementId: UUID) async {
        do {
            let loaded: [ElementAutomation] = try await supabase
                .from("element_automations")
                .select()
                .eq("element_id", value: elementId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            byElement[elementId] = loaded
        } catch {
            self.error = error.recordableDescription
        }
    }

    func add(_ payload: NewElementAutomation) async -> ElementAutomation? {
        do {
            let created: ElementAutomation = try await supabase
                .from("element_automations")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            byElement[created.elementId, default: []].insert(created, at: 0)
            await scheduleNotification(for: created)
            return created
        } catch {
            self.error = error.recordableDescription
            return nil
        }
    }

    func setActive(_ automation: ElementAutomation, active: Bool) async {
        let payload = ElementAutomationUpdate(
            name: automation.name, triggerType: automation.triggerType,
            intervalMonths: automation.intervalMonths, nextRun: automation.nextRun,
            createsTask: automation.createsTask, isActive: active,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase.from("element_automations").update(payload)
                .eq("id", value: automation.id.uuidString).execute()
            if var arr = byElement[automation.elementId],
               let idx = arr.firstIndex(where: { $0.id == automation.id }) {
                arr[idx].isActive = active
                byElement[automation.elementId] = arr
                if active { await scheduleNotification(for: arr[idx]) }
                else { cancelNotification(id: automation.id) }
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    func delete(_ automation: ElementAutomation) async {
        do {
            try await supabase.from("element_automations").delete()
                .eq("id", value: automation.id.uuidString).execute()
            byElement[automation.elementId]?.removeAll { $0.id == automation.id }
            cancelNotification(id: automation.id)
        } catch {
            self.error = error.recordableDescription
        }
    }

    // MARK: - Local notification scheduling

    private func scheduleNotification(for a: ElementAutomation) async {
        cancelNotification(id: a.id)
        guard a.isActive, let runStr = a.nextRun, let run = df.date(from: runStr), run > Date() else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Automation")
        content.body = a.name
        content.sound = .default

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: run)
        comps.hour = 9; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: "automation.\(a.id.uuidString)",
            content: content,
            trigger: trigger
        ))
    }

    private func cancelNotification(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["automation.\(id.uuidString)"])
    }

    // MARK: - Helpers for building a rule

    /// Computes the next-run date string for a trigger choice.
    func nextRunString(trigger: AutomationTrigger, intervalMonths: Int, onceDate: Date, warrantyUntil: String?) -> String? {
        switch trigger {
        case .periodic:
            let d = Calendar.current.date(byAdding: .month, value: intervalMonths, to: Date()) ?? Date()
            return df.string(from: d)
        case .once:
            return df.string(from: onceDate)
        case .warranty:
            guard let w = warrantyUntil, let date = df.date(from: w),
                  let alert = Calendar.current.date(byAdding: .day, value: -7, to: date) else { return nil }
            return df.string(from: alert)
        }
    }
}

import Foundation
import UserNotifications
import Supabase

// MARK: - Feeding Service
//
// Manages feeding schedules and logs.
// Reuses NotificationScheduler patterns for scheduling.
// Triggers HA feeder entity via HAEntityBridge for automated feeders.

@MainActor
final class FeedingService: ObservableObject {

    // MARK: Published

    @Published private(set) var schedules: [FeedingSchedule] = []
    @Published private(set) var recentLogs: [FeedingLog] = []

    private let db = SupabaseClient.shared
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: Load

    func loadSchedules(for pondId: UUID) async throws {
        schedules = try await db
            .from("feeding_schedules")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .order("hour")
            .execute()
            .value
    }

    func loadRecentLogs(for pondId: UUID, limit: Int = 30) async throws {
        recentLogs = try await db
            .from("feeding_logs")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .order("fed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    // MARK: Schedule Management

    func addSchedule(_ schedule: FeedingSchedule) async throws {
        struct Payload: Codable {
            let pondId: String
            let name: String
            let hour: Int
            let minute: Int
            let foodType: String
            let amountGrams: Double
            let isActive: Bool
            let daysOfWeek: [Int]
            let haFeederEntityId: String?
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case pondId = "pond_id"
                case name, hour, minute
                case foodType = "food_type"
                case amountGrams = "amount_grams"
                case isActive = "is_active"
                case daysOfWeek = "days_of_week"
                case haFeederEntityId = "ha_feeder_entity_id"
                case notes
            }
        }
        let payload = Payload(
            pondId: schedule.pondId.uuidString,
            name: schedule.name,
            hour: schedule.hour,
            minute: schedule.minute,
            foodType: schedule.foodType.rawValue,
            amountGrams: schedule.amountGrams,
            isActive: schedule.isActive,
            daysOfWeek: schedule.daysOfWeek,
            haFeederEntityId: schedule.haFeederEntityId,
            notes: schedule.notes
        )
        let created: FeedingSchedule = try await db
            .from("feeding_schedules")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        schedules.append(created)

        if created.isActive {
            scheduleNotification(for: created)
        }
    }

    func toggleSchedule(_ schedule: FeedingSchedule) async throws {
        struct Payload: Codable {
            let isActive: Bool
            enum CodingKeys: String, CodingKey {
                case isActive = "is_active"
            }
        }
        try await db
            .from("feeding_schedules")
            .update(Payload(isActive: !schedule.isActive))
            .eq("id", value: schedule.id.uuidString)
            .execute()
        if let idx = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[idx].isActive.toggle()
        }

        if schedule.isActive {
            cancelNotification(for: schedule)
        } else {
            if let updated = schedules.first(where: { $0.id == schedule.id }) {
                scheduleNotification(for: updated)
            }
        }
    }

    func deleteSchedule(_ schedule: FeedingSchedule) async throws {
        try await db
            .from("feeding_schedules")
            .delete()
            .eq("id", value: schedule.id.uuidString)
            .execute()
        schedules.removeAll { $0.id == schedule.id }
        cancelNotification(for: schedule)
    }

    // MARK: Manual Feeding Log

    func logManualFeeding(
        pondId: UUID,
        foodType: FoodType,
        amountGrams: Double,
        notes: String? = nil
    ) async throws {
        let payload = NewFeedingLog(
            pondId: pondId.uuidString,
            scheduleId: nil,
            foodType: foodType.rawValue,
            amountGrams: amountGrams,
            source: FeedingSource.manual.rawValue
        )
        let created: FeedingLog = try await db
            .from("feeding_logs")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        recentLogs.insert(created, at: 0)
    }

    // MARK: Trigger Automated Feeder via HA
    //
    // Calls HA service switch.turn_on for the feeder entity.
    // Actual HA API call is delegated to HAWebSocketManager (existing).

    func triggerHAFeeder(entityId: String) async {
        // Dispatches through HAWebSocketManager.callService
        // "switch.turn_on" or "script.turn_on" depending on feeder type
        // Implementation in Phase 2 — requires 1.D4 HAWebSocketManager
    }

    // MARK: Stats

    func weeklyFoodConsumptionGrams(logs: [FeedingLog]? = nil) -> Double {
        let entries = logs ?? recentLogs
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries
            .filter { $0.fedAt >= cutoff }
            .reduce(0) { $0 + $1.amountGrams }
    }

    func lastFeedingTime(for pondId: UUID) -> Date? {
        recentLogs.first(where: { $0.pondId == pondId })?.fedAt
    }

    // MARK: Local Notifications (reuses UNUserNotificationCenter — same as NotificationScheduler)

    private func scheduleNotification(for schedule: FeedingSchedule) {
        let content = UNMutableNotificationContent()
        content.title = "Pond Feeding Time"
        content.body = "Feed \(schedule.amountGrams)g of \(schedule.foodType.displayName)"
        content.sound = .default
        content.categoryIdentifier = "POND_FEEDING"

        var dateComponents = DateComponents()
        dateComponents.hour = schedule.hour
        dateComponents.minute = schedule.minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "pond.feeding.\(schedule.id.uuidString)",
            content: content,
            trigger: trigger
        )
        notificationCenter.add(request)
    }

    private func cancelNotification(for schedule: FeedingSchedule) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["pond.feeding.\(schedule.id.uuidString)"]
        )
    }
}

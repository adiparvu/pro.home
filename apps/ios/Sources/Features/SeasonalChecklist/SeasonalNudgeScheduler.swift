import Foundation
import UserNotifications

// MARK: - Season-start nudges
//
// One local notification on the first morning of each season — "A început
// primăvara — verificările casei te așteaptă." Four fixed-identifier
// repeating calendar triggers (Mar/Jun/Sep/Dec 1st, 09:00), so re-arming is
// idempotent and the total notification budget cost is constant.
//
// Feature-local by design: `Services/NotificationScheduler` is frozen for
// this change, and precedent exists — PropertyValueView arms its yearly
// revaluation reminder against UNUserNotificationCenter directly the same
// way. `NotificationScheduler.reschedule` sweeps only its own "agenda.*"
// namespace, so these requests survive its passes.

enum SeasonalNudgeScheduler {

    private static func identifier(for season: Season) -> String {
        "seasonal.start.\(season.rawValue)"
    }

    /// Arms (or refreshes) all four season-start nudges. Called when the
    /// checklist opens; refreshing keeps the copy in the app's current
    /// language. Silent no-op without notification permission.
    static func armSeasonStartNudges() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(
            withIdentifiers: Season.allCases.map(identifier(for:)))

        for season in Season.allCases {
            let content = UNMutableNotificationContent()
            content.title = season.startNudgeTitle
            content.body  = String(localized: "seasonal_notif_body")
            content.sound = .default

            var comps = DateComponents()
            comps.month = season.startMonth
            comps.day = 1
            comps.hour = 9
            comps.minute = 0

            try? await center.add(UNNotificationRequest(
                identifier: identifier(for: season),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }
}

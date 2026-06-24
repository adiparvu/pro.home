import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: ObservableObject {

    // Persisted preferences
    @Published var taskReminders: Bool  { didSet { UserDefaults.standard.set(taskReminders,  forKey: Keys.taskReminders) } }
    @Published var documentExpiry: Bool { didSet { UserDefaults.standard.set(documentExpiry, forKey: Keys.documentExpiry) } }
    @Published var financialAlerts: Bool { didSet { UserDefaults.standard.set(financialAlerts, forKey: Keys.financialAlerts) } }
    @Published var warrantyAlerts: Bool { didSet { UserDefaults.standard.set(warrantyAlerts, forKey: Keys.warrantyAlerts) } }
    @Published var inventoryLoans: Bool { didSet { UserDefaults.standard.set(inventoryLoans, forKey: Keys.inventoryLoans) } }
    @Published var chatMessages: Bool   { didSet { UserDefaults.standard.set(chatMessages,   forKey: Keys.chatMessages) } }
    @Published var mentions: Bool       { didSet { UserDefaults.standard.set(mentions,        forKey: Keys.mentions) } }
    @Published var automationAlerts: Bool { didSet { UserDefaults.standard.set(automationAlerts, forKey: Keys.automationAlerts) } }
    @Published var weeklyDigest: Bool   { didSet { UserDefaults.standard.set(weeklyDigest,   forKey: Keys.weeklyDigest) } }

    enum Keys {
        static let taskReminders   = "prvio.notif.tasks"
        static let documentExpiry  = "prvio.notif.docExpiry"
        static let financialAlerts = "prvio.notif.financial"
        static let warrantyAlerts  = "prvio.notif.warranty"
        static let inventoryLoans  = "prvio.notif.inventory"
        static let chatMessages    = "prvio.notif.chat"
        static let mentions        = "prvio.notif.mentions"
        static let automationAlerts = "prvio.notif.automation"
        static let weeklyDigest    = "prvio.notif.weekly"
    }

    /// Static check usable from anywhere that fires a local notification
    /// (chat mentions, inventory loans, …) without holding the instance.
    static func prefEnabled(_ key: String, default def: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.bool(forKey: key)
    }

    init() {
        let d = UserDefaults.standard
        self.taskReminders    = d.object(forKey: Keys.taskReminders)    as? Bool ?? true
        self.documentExpiry   = d.object(forKey: Keys.documentExpiry)   as? Bool ?? true
        self.financialAlerts  = d.object(forKey: Keys.financialAlerts)  as? Bool ?? true
        self.warrantyAlerts   = d.object(forKey: Keys.warrantyAlerts)   as? Bool ?? true
        self.inventoryLoans   = d.object(forKey: Keys.inventoryLoans)   as? Bool ?? true
        self.chatMessages     = d.object(forKey: Keys.chatMessages)     as? Bool ?? true
        self.mentions         = d.object(forKey: Keys.mentions)         as? Bool ?? true
        self.automationAlerts = d.object(forKey: Keys.automationAlerts) as? Bool ?? true
        self.weeklyDigest     = d.object(forKey: Keys.weeklyDigest)     as? Bool ?? false
    }

    // MARK: - Category registration

    func registerCategories() {
        let taskComplete = UNNotificationAction(identifier: "TASK_COMPLETE", title: String(localized: "Completed ✓"),
                                                options: [.authenticationRequired])
        let taskRemind   = UNNotificationAction(identifier: "TASK_REMIND",   title: String(localized: "Remind me tomorrow"), options: [])
        let taskCategory = UNNotificationCategory(identifier: "TASK",
                                                  actions: [taskComplete, taskRemind],
                                                  intentIdentifiers: [], options: [])

        let plantWatered = UNNotificationAction(identifier: "PLANT_WATERED", title: String(localized: "Watered 💧"), options: [])
        let plantRemind  = UNNotificationAction(identifier: "PLANT_REMIND",  title: String(localized: "Remind me in 2h"), options: [])
        let plantCategory = UNNotificationCategory(identifier: "PLANT",
                                                   actions: [plantWatered, plantRemind],
                                                   intentIdentifiers: [], options: [])

        let supplyAdd     = UNNotificationAction(identifier: "SUPPLY_ADD",   title: String(localized: "Add to list"),
                                                 options: [.foreground])
        let supplyCategory = UNNotificationCategory(identifier: "SUPPLY",
                                                    actions: [supplyAdd],
                                                    intentIdentifiers: [], options: [])

        UNUserNotificationCenter.current().setNotificationCategories([taskCategory, plantCategory, supplyCategory])
    }

    // MARK: - Plant watering notifications

    func schedulePlantWateringNotifications(_ plants: [Plant]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let ids = plants.map { "plant.water.\($0.id.uuidString)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let cal = Calendar.current
        var requests: [UNNotificationRequest] = []

        for plant in plants where plant.needsWatering || plant.daysUntilWatering <= 1 {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Time to water the plants!")
            content.body  = String(format: String(localized: "%@ %@ needs water"), plant.emoji, plant.name)
            content.sound = .default
            content.categoryIdentifier = "PLANT"
            content.userInfo = ["plantId": plant.id.uuidString]

            var components = cal.dateComponents([.year, .month, .day], from: Date())
            if !plant.needsWatering, let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) {
                components = cal.dateComponents([.year, .month, .day], from: tomorrow)
            }
            components.hour   = 8
            components.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            requests.append(UNNotificationRequest(
                identifier: "plant.water.\(plant.id.uuidString)",
                content: content,
                trigger: trigger
            ))
        }

        for request in requests { try? await center.add(request) }
    }

    // MARK: - Main entry point

    func reschedule(tasks: [MaintenanceTask], documents: [DocumentModel]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        // Remove existing app-scheduled notifications
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers(tasks: tasks, documents: documents))

        var requests: [UNNotificationRequest] = []

        if taskReminders {
            requests += taskNotifications(tasks)
        }
        if documentExpiry {
            requests += documentNotifications(documents)
        }
        if weeklyDigest {
            requests += [weeklyDigestNotification()]
        }

        for request in requests {
            try? await center.add(request)
        }
    }

    // MARK: - Task notifications

    private func taskNotifications(_ tasks: [MaintenanceTask]) -> [UNNotificationRequest] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        var requests: [UNNotificationRequest] = []

        for task in tasks where !task.isCompleted {
            guard let ds = task.dueDate, let dueDate = iso.date(from: ds) else { continue }

            let now = Date()
            let cal = Calendar.current

            // Overdue — fire once, 1 minute from now if already overdue
            if dueDate < cal.startOfDay(for: now) {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Overdue Task")
                content.body  = String(format: String(localized: "%@ was due %@"), task.title, task.dueDateDisplay)
                content.sound = .default
                content.badge = NSNumber(value: 1)
                content.categoryIdentifier = "TASK"
                content.userInfo = ["taskId": task.id.uuidString]

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
                requests.append(UNNotificationRequest(
                    identifier: "task.overdue.\(task.id.uuidString)",
                    content: content,
                    trigger: trigger
                ))

            } else {
                // Fire at 9am on the due date
                var components = cal.dateComponents([.year, .month, .day], from: dueDate)
                components.hour = 9
                components.minute = 0

                let content = UNMutableNotificationContent()
                content.title = String(localized: "Task Due Today")
                content.body  = task.title
                content.sound = .default
                content.categoryIdentifier = "TASK"
                content.userInfo = ["taskId": task.id.uuidString]

                if let fireDate = cal.date(from: components), fireDate > now {
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    requests.append(UNNotificationRequest(
                        identifier: "task.due.\(task.id.uuidString)",
                        content: content,
                        trigger: trigger
                    ))
                }

                // Also fire a 3-day-ahead reminder
                if let threeDaysBefore = cal.date(byAdding: .day, value: -3, to: dueDate),
                   threeDaysBefore > now {
                    var reminderComponents = cal.dateComponents([.year, .month, .day], from: threeDaysBefore)
                    reminderComponents.hour = 9
                    reminderComponents.minute = 0

                    let reminderContent = UNMutableNotificationContent()
                    reminderContent.title = String(localized: "Task Due in 3 Days")
                    reminderContent.body  = task.title
                    reminderContent.sound = .default
                    reminderContent.categoryIdentifier = "TASK"

                    let trigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: false)
                    requests.append(UNNotificationRequest(
                        identifier: "task.reminder3d.\(task.id.uuidString)",
                        content: reminderContent,
                        trigger: trigger
                    ))
                }
            }
        }

        return requests
    }

    // MARK: - Document expiry notifications

    private func documentNotifications(_ documents: [DocumentModel]) -> [UNNotificationRequest] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        var requests: [UNNotificationRequest] = []
        let now = Date()
        let cal = Calendar.current

        for doc in documents {
            guard let ds = doc.expiresAt, let expiry = iso.date(from: ds) else { continue }

            // 30-day alert
            if let fireDate30 = cal.date(byAdding: .day, value: -30, to: expiry),
               fireDate30 > now {
                var components = cal.dateComponents([.year, .month, .day], from: fireDate30)
                components.hour = 9; components.minute = 0

                let content = UNMutableNotificationContent()
                content.title = String(localized: "Document Expiring Soon")
                content.body  = String(format: String(localized: "%@ expires in 30 days"), doc.name)
                content.sound = .default
                content.categoryIdentifier = "DOCUMENT"
                content.userInfo = ["docId": doc.id.uuidString]

                requests.append(UNNotificationRequest(
                    identifier: "doc.30d.\(doc.id.uuidString)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }

            // 7-day alert
            if let fireDate7 = cal.date(byAdding: .day, value: -7, to: expiry),
               fireDate7 > now {
                var components = cal.dateComponents([.year, .month, .day], from: fireDate7)
                components.hour = 9; components.minute = 0

                let content = UNMutableNotificationContent()
                content.title = String(localized: "Document Expiring in 7 Days")
                content.body  = String(format: String(localized: "%@ – renew before %@"), doc.name, doc.expiresDisplay ?? ds)
                content.sound = .default
                content.categoryIdentifier = "DOCUMENT"

                requests.append(UNNotificationRequest(
                    identifier: "doc.7d.\(doc.id.uuidString)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }
        }

        return requests
    }

    // MARK: - Weekly digest (every Monday 9am)

    private func weeklyDigestNotification() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "PRVIO Weekly Digest")
        content.body  = String(localized: "Review your property tasks, finances, and documents for the week.")
        content.sound = .default

        var components = DateComponents()
        components.weekday = 2  // Monday
        components.hour    = 9
        components.minute  = 0

        return UNNotificationRequest(
            identifier: "weekly.digest",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
    }

    // MARK: - Helpers

    private func pendingIdentifiers(tasks: [MaintenanceTask], documents: [DocumentModel]) -> [String] {
        var ids: [String] = ["weekly.digest"]
        for t in tasks {
            ids += [
                "task.overdue.\(t.id.uuidString)",
                "task.due.\(t.id.uuidString)",
                "task.reminder3d.\(t.id.uuidString)"
            ]
        }
        for d in documents {
            ids += ["doc.30d.\(d.id.uuidString)", "doc.7d.\(d.id.uuidString)"]
        }
        return ids
    }
}

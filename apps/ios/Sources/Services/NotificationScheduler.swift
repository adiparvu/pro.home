import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationScheduler {

    // Persisted preferences
    var taskReminders: Bool  { didSet { UserDefaults.standard.set(taskReminders,  forKey: Keys.taskReminders) } }
    var documentExpiry: Bool { didSet { UserDefaults.standard.set(documentExpiry, forKey: Keys.documentExpiry) } }
    var financialAlerts: Bool { didSet { UserDefaults.standard.set(financialAlerts, forKey: Keys.financialAlerts) } }
    var warrantyAlerts: Bool { didSet { UserDefaults.standard.set(warrantyAlerts, forKey: Keys.warrantyAlerts) } }
    var inventoryLoans: Bool { didSet { UserDefaults.standard.set(inventoryLoans, forKey: Keys.inventoryLoans) } }
    var chatMessages: Bool   { didSet { UserDefaults.standard.set(chatMessages,   forKey: Keys.chatMessages) } }
    var mentions: Bool       { didSet { UserDefaults.standard.set(mentions,        forKey: Keys.mentions) } }
    var automationAlerts: Bool { didSet { UserDefaults.standard.set(automationAlerts, forKey: Keys.automationAlerts) } }
    var weeklyDigest: Bool   { didSet { UserDefaults.standard.set(weeklyDigest,   forKey: Keys.weeklyDigest) } }
    /// Rent-due & lease-end reminders. New in the calendar wave — its toggle
    /// lives next to the other deadline categories in Profile → Notifications.
    var leaseAlerts: Bool    { didSet { UserDefaults.standard.set(leaseAlerts,    forKey: Keys.leaseAlerts) } }

    // Per-category lead time: how many days BEFORE a deadline the reminder
    // fires (an on-the-day reminder always fires too). Configurable so a user
    // who wants 60 days' notice on a passport and 3 on a bill can have both.
    var taskLeadDays: Int      { didSet { UserDefaults.standard.set(taskLeadDays,      forKey: Keys.taskLead) } }
    var documentLeadDays: Int  { didSet { UserDefaults.standard.set(documentLeadDays,  forKey: Keys.documentLead) } }
    var warrantyLeadDays: Int  { didSet { UserDefaults.standard.set(warrantyLeadDays,  forKey: Keys.warrantyLead) } }
    var financialLeadDays: Int { didSet { UserDefaults.standard.set(financialLeadDays, forKey: Keys.financialLead) } }
    var leaseLeadDays: Int     { didSet { UserDefaults.standard.set(leaseLeadDays,     forKey: Keys.leaseLead) } }

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
        static let leaseAlerts     = "prvio.notif.lease"
        static let taskLead        = "prvio.notif.tasks.lead"
        static let documentLead    = "prvio.notif.docExpiry.lead"
        static let warrantyLead    = "prvio.notif.warranty.lead"
        static let financialLead   = "prvio.notif.financial.lead"
        static let leaseLead       = "prvio.notif.lease.lead"
    }

    /// Lead-time options offered in the UI (days before a deadline).
    static let leadOptions = [1, 3, 7, 14, 30, 60]

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
        self.leaseAlerts      = d.object(forKey: Keys.leaseAlerts)      as? Bool ?? true
        self.taskLeadDays      = d.object(forKey: Keys.taskLead)      as? Int ?? 3
        self.documentLeadDays  = d.object(forKey: Keys.documentLead)  as? Int ?? 30
        self.warrantyLeadDays  = d.object(forKey: Keys.warrantyLead)  as? Int ?? 30
        self.financialLeadDays = d.object(forKey: Keys.financialLead) as? Int ?? 3
        self.leaseLeadDays     = d.object(forKey: Keys.leaseLead)     as? Int ?? 7
    }

    // MARK: - Per-category deadline settings

    /// The agenda categories that produce configurable deadline reminders.
    /// (Birthdays and plant watering have their own dedicated schedules.)
    func isEnabled(_ category: AgendaCategory) -> Bool {
        switch category {
        case .task:      return taskReminders
        case .document:  return documentExpiry
        case .warranty:  return warrantyAlerts
        case .financial: return financialAlerts
        case .lease:     return leaseAlerts
        // Events, birthdays and plant watering each have their own schedule
        // (events reach the wrist/phone via the Apple Calendar mirror), so they
        // don't produce a second, configurable deadline reminder here.
        case .event, .birthday, .plant: return false
        }
    }

    func leadDays(for category: AgendaCategory) -> Int {
        switch category {
        case .task:      return taskLeadDays
        case .document:  return documentLeadDays
        case .warranty:  return warrantyLeadDays
        case .financial: return financialLeadDays
        case .lease:     return leaseLeadDays
        case .event, .birthday, .plant: return 0
        }
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

        // DOCUMENT and PROACTIVE were being set on content but never
        // registered — their notifications shipped with no actions at all.
        let docRemind = UNNotificationAction(identifier: "DOC_REMIND_WEEK",
                                             title: String(localized: "notif_doc_remind_week"), options: [])
        let documentCategory = UNNotificationCategory(identifier: "DOCUMENT",
                                                      actions: [docRemind],
                                                      intentIdentifiers: [], options: [])

        let proactiveOpen = UNNotificationAction(identifier: "PROACTIVE_OPEN",
                                                 title: String(localized: "notif_view_details"),
                                                 options: [.foreground])
        let proactiveCategory = UNNotificationCategory(identifier: "PROACTIVE",
                                                       actions: [proactiveOpen],
                                                       intentIdentifiers: [], options: [])

        // Reply to a mention straight from the notification — keyboard,
        // scribble or voice, courtesy of the text-input action.
        let messageReply = UNTextInputNotificationAction(
            identifier: "MESSAGE_REPLY",
            title: String(localized: "notif_reply"),
            options: [],
            textInputButtonTitle: String(localized: "Send"),
            textInputPlaceholder: String(localized: "Message…"))
        let messageCategory = UNNotificationCategory(identifier: "MESSAGE",
                                                     actions: [messageReply],
                                                     intentIdentifiers: [], options: [])

        // Loan reminders (IMG_8612): open the item's inventory page, or mark
        // it returned straight from the notification — the return rides the
        // same park-and-drain queue the other actions use.
        let loanView = UNNotificationAction(identifier: "LOAN_VIEW",
                                            title: String(localized: "notif_loan_view"),
                                            options: [.foreground])
        let loanReturned = UNNotificationAction(identifier: "LOAN_RETURNED",
                                                title: String(localized: "notif_loan_returned"),
                                                options: [])
        let loanCategory = UNNotificationCategory(identifier: "LOAN",
                                                  actions: [loanView, loanReturned],
                                                  intentIdentifiers: [], options: [])

        UNUserNotificationCenter.current().setNotificationCategories(
            [taskCategory, plantCategory, supplyCategory,
             documentCategory, proactiveCategory, messageCategory, loanCategory])
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
            // A thirsty plant discovered after 08:00 waits for tomorrow's
            // slot — a past-dated trigger fires on the spot, which turned
            // every app launch into a fresh "water the plants" alert.
            if let fire = cal.date(from: components), fire <= Date(),
               let next = cal.date(byAdding: .day, value: 1, to: fire) {
                components = cal.dateComponents([.year, .month, .day], from: next)
                components.hour   = 8
                components.minute = 0
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            requests.append(UNNotificationRequest(
                identifier: "plant.water.\(plant.id.uuidString)",
                content: content,
                trigger: trigger
            ))
        }

        for request in requests { try? await center.add(request) }
    }

    // MARK: - Monthly recap

    /// The 1st of every month at 09:30: the month's story is ready to read.
    /// One repeating calendar trigger — the system re-fires it forever.
    func scheduleMonthlyRecap() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["monthly.recap"])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "monthly_notif_title")
        content.body = String(localized: "monthly_notif_body")
        content.sound = .default
        var comps = DateComponents()
        comps.day = 1
        comps.hour = 9
        comps.minute = 30
        try? await center.add(UNNotificationRequest(
            identifier: "monthly.recap",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    // MARK: - Celebrations (account anniversary + birthday)

    /// PRVIO celebrates with you: a congratulation on every yearly anniversary
    /// of the account and on the user's birthday (when set in the profile).
    /// Non-repeating triggers re-armed at every launch, so the year count in
    /// the copy is always correct.
    func scheduleCelebrations(accountCreatedAt: String?, birthDate: String?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(
            withIdentifiers: ["celebration.anniversary", "celebration.birthday"])

        let cal = Calendar.current
        let now = Date()

        if let s = accountCreatedAt,
           let created = AppDate.timestamp(from: s) ?? AppDate.day(from: s),
           let next = nextYearlyOccurrence(of: created, after: now, calendar: cal) {
            let years = cal.dateComponents([.year], from: created, to: next.date).year ?? 0
            if years >= 1 {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "celebration_anniversary_title")
                content.body = years == 1
                    ? String(localized: "celebration_anniversary_body_one")
                    : String(format: String(localized: "celebration_anniversary_body_many"), years)
                content.sound = .default
                try? await center.add(UNNotificationRequest(
                    identifier: "celebration.anniversary",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: next.components, repeats: false)))
            }
        }

        if let s = birthDate, let birthday = AppDate.day(from: s),
           let next = nextYearlyOccurrence(of: birthday, after: now, calendar: cal) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "celebration_birthday_title")
            content.body  = String(localized: "celebration_birthday_body")
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "celebration.birthday",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: next.components, repeats: false)))
        }
    }

    /// The next 09:00 on the month/day of `date`, strictly after `now`.
    /// Feb 29 anniversaries roll forward per the calendar's matching rules.
    private func nextYearlyOccurrence(of date: Date, after now: Date, calendar cal: Calendar)
        -> (date: Date, components: DateComponents)? {
        var match = cal.dateComponents([.month, .day], from: date)
        match.hour = 9; match.minute = 0
        guard let next = cal.nextDate(after: now, matching: match,
                                      matchingPolicy: .nextTimePreservingSmallerComponents) else { return nil }
        return (next, cal.dateComponents([.year, .month, .day, .hour, .minute], from: next))
    }

    // MARK: - Main entry point
    //
    // One deadline scheduler for the whole house. Every dated thing —
    // tasks, documents, warranties, rents/large transactions and leases —
    // flows from the same `HouseAgenda` the calendar and the Apple Calendar
    // mirror use, so what you see on the calendar is exactly what reminds you.
    // For each item in an enabled category we fire a reminder `leadDays`
    // before it (user-configurable per category) and one on the day itself;
    // an overdue task additionally nudges once, a minute from now.

    func reschedule(agenda: [AgendaItem]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        // Clear every reminder we previously scheduled — the current agenda is
        // the whole truth. We match on our own id namespace, and sweep the
        // legacy per-item ids from before this unified scheduler so an upgrade
        // never leaves an orphaned alert behind.
        let legacyPrefixes = ["task.overdue.", "task.due.", "task.reminder3d.", "doc.30d.", "doc.7d."]
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { id in
            id.hasPrefix("agenda.") || id == "weekly.digest"
                || legacyPrefixes.contains(where: id.hasPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let now = Date()
        let cal = Calendar.current
        var requests: [UNNotificationRequest] = []

        // Overdue nudges dedupe by DAY, not by launch: reschedule() runs on
        // every world load (cold start, context switch, app update), and the
        // 60-second trigger below would otherwise re-deliver the exact same
        // "overdue" alerts each time the app opens.
        let stampsKey = "prvio.notif.overdueStamps"
        var overdueStamps = UserDefaults.standard.dictionary(forKey: stampsKey) as? [String: String] ?? [:]
        let todayComps = cal.dateComponents([.year, .month, .day], from: now)
        let todayStamp = "\(todayComps.year ?? 0)-\(todayComps.month ?? 0)-\(todayComps.day ?? 0)"

        // iOS keeps at most 64 pending local notifications per app; other
        // schedulers (plant care, celebrations, monthly recap) share that
        // budget, so we cap the deadline pass and — because the agenda is
        // sorted by date — the SOONEST deadlines are the ones that survive.
        let deadlineBudget = 48

        for item in agenda where isEnabled(item.category) && !item.isCompleted {
            if requests.count >= deadlineBudget { break }
            let day = cal.startOfDay(for: item.date)

            // Overdue tasks nudge once per day, shortly after launch.
            if item.category == .task, day < cal.startOfDay(for: now) {
                guard overdueStamps[item.occurrenceKey] != todayStamp else { continue }
                overdueStamps[item.occurrenceKey] = todayStamp
                let content = deadlineContent(for: item, phase: .overdue)
                requests.append(UNNotificationRequest(
                    identifier: "agenda.overdue.\(item.occurrenceKey)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
                continue
            }

            // Lead-time heads-up (skip if it would fire in the past).
            let lead = leadDays(for: item.category)
            if lead > 0, let leadDate = cal.date(byAdding: .day, value: -lead, to: day) {
                if let req = calendarRequest(for: item, fireOn: leadDate, phase: .lead(lead),
                                             idPrefix: "agenda.lead", after: now, cal: cal) {
                    requests.append(req)
                }
            }
            // On-the-day reminder.
            if let req = calendarRequest(for: item, fireOn: day, phase: .day,
                                         idPrefix: "agenda.day", after: now, cal: cal) {
                requests.append(req)
            }
        }

        if weeklyDigest { requests.append(weeklyDigestNotification()) }

        // Stamps for items no longer on the agenda (completed, deleted) are
        // dead weight — prune so the map tracks the live overdue set only.
        let liveKeys = Set(agenda.map(\.occurrenceKey))
        overdueStamps = overdueStamps.filter { liveKeys.contains($0.key) }
        UserDefaults.standard.set(overdueStamps, forKey: stampsKey)

        for request in requests { try? await center.add(request) }
    }

    // MARK: - Deadline notification building

    private enum DeadlinePhase {
        case lead(Int)   // N days before
        case day         // on the day
        case overdue     // already past (tasks only)
    }

    /// A 09:00 calendar-triggered request for `item` on `fireDay`, or nil when
    /// that moment is already in the past.
    private func calendarRequest(for item: AgendaItem, fireOn fireDay: Date,
                                 phase: DeadlinePhase, idPrefix: String,
                                 after now: Date, cal: Calendar) -> UNNotificationRequest? {
        var comps = cal.dateComponents([.year, .month, .day], from: fireDay)
        comps.hour = 9; comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > now else { return nil }
        return UNNotificationRequest(
            identifier: "\(idPrefix).\(item.occurrenceKey)",
            content: deadlineContent(for: item, phase: phase),
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    /// The title is the thing itself; the body says when — so a glance at the
    /// lock screen reads "Passport · in 30 days" without opening the app.
    private func deadlineContent(for item: AgendaItem, phase: DeadlinePhase) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.sound = .default
        switch phase {
        case .lead(let n):
            content.body = String(format: String(localized: "notif_deadline_in_days"), n)
        case .day:
            content.body = String(localized: "notif_deadline_today")
            content.badge = NSNumber(value: 1)
        case .overdue:
            content.body = String(localized: "notif_deadline_overdue")
            content.badge = NSNumber(value: 1)
        }
        // Category → notification category (action buttons) + routing payload.
        switch item.category {
        case .task:
            content.categoryIdentifier = "TASK"
            content.userInfo = ["taskId": item.sourceId, "deepLink": item.deepLink ?? ""]
        case .document:
            content.categoryIdentifier = "DOCUMENT"
            content.userInfo = ["docId": item.sourceId, "deepLink": item.deepLink ?? ""]
        default:
            content.categoryIdentifier = "PROACTIVE"
            content.userInfo = ["deepLink": item.deepLink ?? ""]
        }
        return content
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
}

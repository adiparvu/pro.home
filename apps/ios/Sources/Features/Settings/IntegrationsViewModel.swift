import SwiftUI
import EventKit
import Contacts

// MARK: - Status

enum IntegrationStatus: Equatable {
    case connected
    case notConnected
    case loading
    case comingSoon
    case active(String)
    case deepLink(String)
}

// MARK: - ViewModel

@MainActor
final class IntegrationsViewModel: ObservableObject {
    @Published var calendarStatus: IntegrationStatus = .notConnected
    @Published var remindersStatus: IntegrationStatus = .notConnected
    @Published var contactsStatus: IntegrationStatus = .notConnected
    @Published var showCalendarSuccess = false
    @Published var showContactsSuccess = false
    @Published var showPermissionDenied = false
    var tasks: [MaintenanceTask] = []
    var property: PropertyModel? = nil
    var familyMembers: [FamilyMember] = []

    private let store = EKEventStore()
    private let calendarSyncedKey = "prvio.calendar.synced_ids"
    private let reminderSyncedKey = "prvio.reminders.synced_ids"

    func checkStatuses() async {
        calendarStatus = await checkCalendarAccess() ? .connected : .notConnected
        remindersStatus = await checkRemindersAccess() ? .connected : .notConnected
        contactsStatus = checkContactsAccess() ? .connected : .notConnected
    }

    // MARK: - Calendar

    func toggleCalendar() async {
        if calendarStatus == .connected {
            calendarStatus = .notConnected
            UserDefaults.standard.removeObject(forKey: calendarSyncedKey)
            return
        }
        calendarStatus = .loading
        let granted = await requestCalendarAccess()
        if granted {
            await syncTasksToCalendar()
            calendarStatus = .connected
            showCalendarSuccess = true
        } else {
            calendarStatus = .notConnected
            showPermissionDenied = true
        }
    }

    func toggleReminders() async {
        if remindersStatus == .connected {
            remindersStatus = .notConnected
            UserDefaults.standard.removeObject(forKey: reminderSyncedKey)
            return
        }
        remindersStatus = .loading
        let granted = await requestRemindersAccess()
        if granted {
            await syncOverdueToReminders()
            remindersStatus = .connected
        } else {
            remindersStatus = .notConnected
            showPermissionDenied = true
        }
    }

    // MARK: - Contacts

    func toggleContacts() async {
        if contactsStatus == .connected {
            contactsStatus = .notConnected
            return
        }
        contactsStatus = .loading
        let granted = await requestContactsAccess()
        if granted {
            syncFamilyToContacts()
            contactsStatus = .connected
            showContactsSuccess = true
        } else {
            contactsStatus = .notConnected
            showPermissionDenied = true
        }
    }

    private func checkContactsAccess() -> Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    private func requestContactsAccess() async -> Bool {
        do {
            return try await CNContactStore().requestAccess(for: .contacts)
        } catch { return false }
    }

    private func syncFamilyToContacts() {
        let contactStore = CNContactStore()
        let saveRequest = CNSaveRequest()

        for member in familyMembers {
            let contact = CNMutableContact()
            let parts = member.name.split(separator: " ", maxSplits: 1)
            contact.givenName = String(parts.first ?? Substring(member.name))
            if parts.count > 1 { contact.familyName = String(parts[1]) }
            if let email = member.email {
                contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
            }
            if let phone = member.phone {
                contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
            }
            contact.organizationName = String(localized: "PRVIO Family")
            saveRequest.add(contact, toContainerWithIdentifier: nil)
        }

        try? contactStore.execute(saveRequest)
    }

    // MARK: - Calendar helpers

    private func checkCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .authorized
    }

    private func requestCalendarAccess() async -> Bool {
        do {
            if #available(iOS 17, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch { return false }
    }

    private func syncTasksToCalendar() async {
        let sources = store.sources
        guard let source = sources.first(where: { $0.sourceType == .calDAV })
                         ?? sources.first(where: { $0.sourceType == .local })
                         ?? sources.first else { return }

        let calTitle = "PRVIO"
        let cal: EKCalendar
        if let existing = store.calendars(for: .event).first(where: { $0.title == calTitle }) {
            cal = existing
        } else {
            cal = EKCalendar(for: .event, eventStore: store)
            cal.title = calTitle
            cal.source = source
            cal.cgColor = UIColor.systemBlue.cgColor
            try? store.saveCalendar(cal, commit: true)
        }

        var synced = UserDefaults.standard.stringArray(forKey: calendarSyncedKey) ?? []
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"

        for task in tasks where !task.isCompleted {
            guard let ds = task.dueDate, let date = iso.date(from: ds) else { continue }
            let key = task.id.uuidString
            guard !synced.contains(key) else { continue }

            let event = EKEvent(eventStore: store)
            event.title = task.title
            event.notes = task.description
            event.startDate = date
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
            event.calendar = cal
            event.isAllDay = true

            if (try? store.save(event, span: .thisEvent)) != nil {
                synced.append(key)
            }
        }
        try? store.commit()
        UserDefaults.standard.set(synced, forKey: calendarSyncedKey)
    }

    // MARK: - Reminders helpers

    private func checkRemindersAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .fullAccess || status == .authorized
    }

    private func requestRemindersAccess() async -> Bool {
        do {
            if #available(iOS 17, *) {
                return try await store.requestFullAccessToReminders()
            } else {
                return try await store.requestAccess(to: .reminder)
            }
        } catch { return false }
    }

    private func syncOverdueToReminders() async {
        let listTitle = "PRVIO"
        let list: EKCalendar
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listTitle }) {
            list = existing
        } else {
            guard let source = store.sources.first(where: { $0.sourceType == .local }) ?? store.sources.first else { return }
            let newList = EKCalendar(for: .reminder, eventStore: store)
            newList.title = listTitle
            newList.source = source
            newList.cgColor = UIColor.systemOrange.cgColor
            try? store.saveCalendar(newList, commit: true)
            list = newList
        }

        var synced = UserDefaults.standard.stringArray(forKey: reminderSyncedKey) ?? []
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"

        let overduePending = tasks.filter { $0.isOverdue || ($0.status == "pending" && !$0.isCompleted) }
        for task in overduePending {
            let key = task.id.uuidString
            guard !synced.contains(key) else { continue }

            let reminder = EKReminder(eventStore: store)
            let priorityLabel = task.priority == "high" ? String(localized: "High") : task.priority == "medium" ? String(localized: "Medium") : String(localized: "Low")
            reminder.title = "[\(priorityLabel)] \(task.title)"
            reminder.notes = task.description
            reminder.calendar = list

            if let ds = task.dueDate, let date = iso.date(from: ds) {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                reminder.dueDateComponents = comps
            }

            if (try? store.save(reminder, commit: false)) != nil {
                synced.append(key)
            }
        }
        try? store.commit()
        UserDefaults.standard.set(synced, forKey: reminderSyncedKey)
    }
}

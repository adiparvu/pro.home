import SwiftUI
import EventKit
import Contacts
import PassKit

// MARK: - Status

enum IntegrationStatus: Equatable {
    case connected
    case notConnected
    case loading
    case comingSoon
    case active(String)
    case deepLink(String)
}

// MARK: - Sheet destination

enum IntegrationSheet: Identifiable {
    case siriShortcuts, nfcWallet, iotHub, receiptScanner, emailImport, watchShowcase
    var id: Int {
        switch self {
        case .siriShortcuts:  return 1
        case .nfcWallet:      return 2
        case .iotHub:         return 3
        case .receiptScanner: return 4
        case .emailImport:    return 5
        case .watchShowcase:  return 6
        }
    }
}

// MARK: - ViewModel

@MainActor
final class IntegrationsViewModel: ObservableObject {
    @Published var calendarStatus: IntegrationStatus = .notConnected
    @Published var remindersStatus: IntegrationStatus = .notConnected
    @Published var contactsStatus: IntegrationStatus = .notConnected
    @Published var homeKitStatus: IntegrationStatus = .deepLink(String(localized: "Conectează"))
    @Published var showCalendarSuccess = false
    @Published var showContactsSuccess = false
    @Published var showPermissionDenied = false
    @Published var iCloudAvailable = false
    @Published var applePayAvailable = false
    @Published var nfcAvailable = false
    @Published var activeSheet: IntegrationSheet? = nil
    var tasks: [MaintenanceTask] = []
    var property: PropertyModel? = nil
    var familyMembers: [FamilyMember] = []

    private lazy var store = EKEventStore()
    private let calendarSyncedKey = "prvio.calendar.synced_ids"
    private let reminderSyncedKey = "prvio.reminders.synced_ids"

    func checkStatuses() async {
        calendarStatus = await checkCalendarAccess() ? .connected : .notConnected
        remindersStatus = await checkRemindersAccess() ? .connected : .notConnected
        contactsStatus = checkContactsAccess() ? .connected : .notConnected
        // Use FileManager to detect iCloud sign-in without touching CKContainer.
        // CKContainer(identifier:) throws NSInvalidArgumentException when the
        // provisioning profile lacks the iCloud container entitlement.
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        applePayAvailable = ApplePayService.shared.isAvailable
        nfcAvailable = NFCScanService.isSupported
        // HomeKit checked lazily — do NOT access HMHomeManager here to avoid
        // a crash when the provisioning profile lacks the HomeKit capability.
    }

    // MARK: - Apple Pay

    /// Opens the system's Apple Pay card-setup flow (Wallet). Only offered
    /// when the device has no eligible card configured yet.
    func openApplePaySetup() {
        guard PKPassLibrary.isPassLibraryAvailable() else { return }
        PKPassLibrary().openPaymentSetup()
    }

    func activateHomeKit() {
        // Only called from an explicit user tap — safe to initialize HMHomeManager here.
        HomeKitService.shared.requestAccess()
        homeKitStatus = HomeKitService.shared.currentAuthorizationStatus
            ? .active(String(localized: "Conectat")) : .deepLink(String(localized: "Conectează"))
        if let url = URL(string: "homeapp://") {
            UIApplication.shared.open(url)
        }
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
        return status == .fullAccess
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

        for task in tasks where !task.isCompleted {
            guard let ds = task.dueDate, let date = MaintenanceTask.parseDate(ds) else { continue }
            let key = task.id.uuidString
            guard !synced.contains(key) else { continue }

            let event = EKEvent(eventStore: store)
            event.title = task.title
            event.notes = task.description
            event.startDate = date
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
            event.calendar = cal
            event.isAllDay = ds.count <= 10

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
        return status == .fullAccess
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

        let overduePending = tasks.filter { $0.isOverdue || ($0.status == "pending" && !$0.isCompleted) }
        for task in overduePending {
            let key = task.id.uuidString
            guard !synced.contains(key) else { continue }

            let reminder = EKReminder(eventStore: store)
            let priorityLabel = task.priority == "high" ? String(localized: "High") : task.priority == "medium" ? String(localized: "Medium") : String(localized: "Low")
            reminder.title = String(format: String(localized: "[%@] %@"), priorityLabel, task.title)
            reminder.notes = task.description
            reminder.calendar = list

            if let ds = task.dueDate, let date = MaintenanceTask.parseDate(ds) {
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

import SwiftUI
import EventKit

struct IntegrationsView: View {
    @EnvironmentObject private var taskService: TaskService
    @StateObject private var vm = IntegrationsViewModel()

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    PageHeader(title: "Integrations")

                    calendarSection
                    smartHomeSection
                    comingSoonSection

                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.checkStatuses() }
        .task { vm.tasks = taskService.tasks }
        .alert("Calendar Sync Enabled", isPresented: $vm.showCalendarSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your upcoming tasks will appear in your Apple Calendar under the \"PRV House\" calendar.")
        }
        .alert("Access Denied", isPresented: $vm.showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access in Settings to enable this integration.")
        }
    }

    // MARK: - Sections

    private var calendarSection: some View {
        IntegrationGroup(title: "Productivity") {
            IntegrationRow(
                icon: "calendar",
                color: .red,
                title: "Apple Calendar",
                description: "Sync tasks and maintenance reminders to your calendar.",
                status: vm.calendarStatus,
                action: { Task { await vm.toggleCalendar() } }
            )

            IntegrationRow(
                icon: "checklist",
                color: .blue,
                title: "Apple Reminders",
                description: "Add overdue tasks to Reminders for quick action.",
                status: vm.remindersStatus,
                action: { Task { await vm.toggleReminders() } }
            )
        }
    }

    private var smartHomeSection: some View {
        IntegrationGroup(title: "Smart Home") {
            IntegrationRow(
                icon: "homekit",
                color: Color(red: 0.98, green: 0.4, blue: 0.4),
                title: "Apple HomeKit",
                description: "Control smart home devices linked to your property.",
                status: .deepLink("Open Home App"),
                action: {
                    if let url = URL(string: "homeapp://") {
                        UIApplication.shared.open(url)
                    }
                }
            )

            IntegrationRow(
                icon: "lightbulb.fill",
                color: .yellow,
                title: "Philips Hue",
                description: "Control lights and scenes across your home.",
                status: .comingSoon,
                action: nil
            )

            IntegrationRow(
                icon: "thermometer.medium",
                color: .orange,
                title: "Nest / Thermostat",
                description: "Monitor and adjust temperature remotely.",
                status: .comingSoon,
                action: nil
            )
        }
    }

    private var comingSoonSection: some View {
        IntegrationGroup(title: "Services") {
            IntegrationRow(
                icon: "camera.fill",
                color: .indigo,
                title: "Security Cameras",
                description: "View live feeds and motion alerts from your cameras.",
                status: .comingSoon,
                action: nil
            )

            IntegrationRow(
                icon: "calendar.badge.clock",
                color: .green,
                title: "Google Calendar",
                description: "Sync with Google Calendar for shared household schedules.",
                status: .comingSoon,
                action: nil
            )

            IntegrationRow(
                icon: "house.and.flag.fill",
                color: .teal,
                title: "Booking / Airbnb",
                description: "Manage short-term rental bookings and guest access.",
                status: .comingSoon,
                action: nil
            )

            IntegrationRow(
                icon: "bolt.horizontal.circle.fill",
                color: Color(red: 0.3, green: 0.85, blue: 0.5),
                title: "Energy Provider",
                description: "Import utility bills automatically from your energy supplier.",
                status: .comingSoon,
                action: nil
            )
        }
    }
}

// MARK: - ViewModel

@MainActor
final class IntegrationsViewModel: ObservableObject {
    @Published var calendarStatus: IntegrationStatus = .notConnected
    @Published var remindersStatus: IntegrationStatus = .notConnected
    @Published var showCalendarSuccess = false
    @Published var showPermissionDenied = false
    var tasks: [MaintenanceTask] = []

    private let store = EKEventStore()
    private let calendarSyncedKey = "prvhouse.calendar.synced_ids"
    private let reminderSyncedKey = "prvhouse.reminders.synced_ids"

    func checkStatuses() async {
        calendarStatus = await checkCalendarAccess() ? .connected : .notConnected
        remindersStatus = await checkRemindersAccess() ? .connected : .notConnected
    }

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

    // MARK: - Calendar

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

        let calTitle = "PRV House"
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

            if let _ = try? store.save(event, span: .thisEvent) {
                synced.append(key)
            }
        }
        try? store.commit()
        UserDefaults.standard.set(synced, forKey: calendarSyncedKey)
    }

    // MARK: - Reminders

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
        let listTitle = "PRV House"
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
            reminder.title = "[\(task.priority.capitalized)] \(task.title)"
            reminder.notes = task.description
            reminder.calendar = list

            if let ds = task.dueDate, let date = iso.date(from: ds) {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                reminder.dueDateComponents = comps
            }

            if let _ = try? store.save(reminder, commit: false) {
                synced.append(key)
            }
        }
        try? store.commit()
        UserDefaults.standard.set(synced, forKey: reminderSyncedKey)
    }
}

// MARK: - Status

enum IntegrationStatus: Equatable {
    case connected
    case notConnected
    case loading
    case comingSoon
    case deepLink(String)
}

// MARK: - Group + Row

private struct IntegrationGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}

private struct IntegrationRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let status: IntegrationStatus
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: icon, color: color, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineLimit(2)
                }

                Spacer()

                statusBadge
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.leading, 64)
        }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .connected:
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .tint(.green)
                .onTapGesture { action?() }
                .allowsHitTesting(true)

        case .notConnected:
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .tint(.blue)
                .onTapGesture { action?() }
                .allowsHitTesting(true)

        case .loading:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)

        case .comingSoon:
            Text("Soon")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())

        case .deepLink(let label):
            Button {
                action?()
            } label: {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.blue.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

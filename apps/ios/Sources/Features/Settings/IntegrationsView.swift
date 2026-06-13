import SwiftUI
import EventKit

struct IntegrationsView: View {
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
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.checkStatuses() }
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

    private let store = EKEventStore()

    func checkStatuses() async {
        calendarStatus = await checkCalendarAccess() ? .connected : .notConnected
        remindersStatus = await checkRemindersAccess() ? .connected : .notConnected
    }

    func toggleCalendar() async {
        if calendarStatus == .connected {
            calendarStatus = .notConnected
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
            return
        }
        remindersStatus = .loading
        let granted = await requestRemindersAccess()
        if granted {
            remindersStatus = .connected
        } else {
            remindersStatus = .notConnected
            showPermissionDenied = true
        }
    }

    // MARK: - Calendar

    private func checkCalendarAccess() async -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess ||
        EKEventStore.authorizationStatus(for: .event) == .authorized
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
        // Create a PRV House calendar if it doesn't exist
        let sources = store.sources
        guard let source = sources.first(where: { $0.sourceType == .local }) ?? sources.first else { return }

        let calendarTitle = "PRV House"
        let existing = store.calendars(for: .event).first { $0.title == calendarTitle }
        let calendar: EKCalendar
        if let existing { calendar = existing }
        else {
            calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = calendarTitle
            calendar.source = source
            calendar.cgColor = UIColor.systemBlue.cgColor
            try? store.saveCalendar(calendar, commit: true)
        }
        _ = calendar
    }

    // MARK: - Reminders

    private func checkRemindersAccess() async -> Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ||
        EKEventStore.authorizationStatus(for: .reminder) == .authorized
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
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) { content }
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
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
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                }

                Spacer()

                statusBadge
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.05))
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
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.06), in: Capsule())

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

import SwiftUI

struct IntegrationsView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
    @StateObject var vm = IntegrationsViewModel()

    var body: some View {
        List {
            // Apple Ecosystem
            Section("iOS & Apple Ecosystem") {
                IntRow(icon: "mic.fill",           label: "Siri & Shortcuts",       status: "Configure")  { vm.activeSheet = .siriShortcuts }
                IntRow(icon: "person.2.fill",      label: "Apple Contacts",          toggleOn: vm.contactsStatus == .connected) { Task { await vm.toggleContacts() } }
                IntRow(icon: "calendar",           label: "Apple Calendar",          toggleOn: vm.calendarStatus == .connected)  { Task { await vm.toggleCalendar() } }
                IntRow(icon: "checklist",          label: "Apple Reminders",         toggleOn: vm.remindersStatus == .connected) { Task { await vm.toggleReminders() } }
                IntRow(icon: "wave.3.right",       label: "NFC Keys",                status: vm.nfcAvailable ? "Available" : "Unavailable") { vm.activeSheet = .nfcWallet }
                IntRow(icon: "icloud.fill",        label: "iCloud Sync",             status: vm.iCloudAvailable ? "Active" : "Off") { }
                IntRow(icon: "moon.fill",          label: "Focus Modes",             status: "Automatic") { openURL("x-apple.systempreferences:") }
            }

            // Smart Home
            Section("Smart Home") {
                IntRow(icon: "homekit",            label: "Apple HomeKit",           status: vm.homeKitStatus.label) { vm.activateHomeKit() }
                IntRow(icon: "cpu.fill",           label: "ESP32",                   status: "Manage")    { vm.activeSheet = .iotHub }
                IntRow(icon: "server.rack",        label: "Raspberry Pi",            status: "Manage")    { vm.activeSheet = .iotHub }
                IntRow(icon: "network",            label: "RS485 Modbus",            status: "Manage")    { vm.activeSheet = .iotHub }
            }

            // Payments
            Section("Payments") {
                IntRow(icon: "creditcard.fill",    label: "Apple Pay",               status: vm.applePayAvailable ? "Available" : "N/A") { }
                IntRow(icon: "wallet.pass.fill",   label: "Wallet — Access Passes",  status: "Configure") { openURL("shoebox://") }
            }

            // Productivity
            Section("Productivity") {
                IntRow(icon: "calendar.badge.clock", label: "Google Calendar",       status: "Open")      { openURL("https://calendar.google.com") }
                IntRow(icon: "doc.richtext.fill",  label: "Notion",                 status: "Open")      { openURL("https://www.notion.so") }
                IntRow(icon: "bolt.shield.fill",   label: "Zapier",                 status: "Connect")   { openURL("https://zapier.com/apps") }
            }

            // Deliveries
            Section("Deliveries") {
                IntRow(icon: "shippingbox.fill",   label: "Fan Courier",            status: vm.courierStatus("fancourier").label) { vm.connectCourier("fancourier", deepLink: "fancourier://") }
                IntRow(icon: "box.truck.fill",     label: "Cargus",                 status: vm.courierStatus("cargus").label)     { vm.connectCourier("cargus", deepLink: "https://www.cargus.ro") }
                IntRow(icon: "box.truck.fill",     label: "Sameday",                status: vm.courierStatus("sameday").label)    { vm.connectCourier("sameday", deepLink: "sameday://") }
                IntRow(icon: "shippingbox.fill",   label: "DHL",                    status: vm.courierStatus("dhl").label)        { vm.connectCourier("dhl", deepLink: "dhlexpress://") }
                IntRow(icon: "envelope.fill",      label: "Email Import",            status: "Configure") { vm.activateEmailImport() }
            }

            // Security
            Section("Security") {
                IntRow(icon: "camera.fill",        label: "Security Cameras",        status: "Set Up")    { openSettings() }
                IntRow(icon: "bell.badge.fill",    label: "Ring Doorbell",           status: "Soon")      { }
            }

            // Energy
            Section("Energy") {
                IntRow(icon: "bolt.horizontal.circle.fill", label: "Energy Provider", status: "Set Up")   { openURL("https://www.enel.ro") }
                IntRow(icon: "sun.max.circle.fill", label: "Solar / PV System",      status: "Open")      { openURL("https://pvoutput.org") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.checkStatuses() }
        .task { vm.tasks = taskService.tasks }
        .task { vm.property = propertyService.primary }
        .task { vm.familyMembers = familyService.members }
        .alert("Calendar Sync Enabled", isPresented: $vm.showCalendarSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Upcoming tasks will appear in Apple Calendar under \"PRVIO\".")
        }
        .alert("Contacts Synced", isPresented: $vm.showContactsSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Family members added to your Contacts under \"PRVIO Family\".")
        }
        .alert("Access Denied", isPresented: $vm.showPermissionDenied) {
            Button("Open Settings") { openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access in Settings to enable this integration.")
        }
        .sheet(item: $vm.activeSheet) { sheet in
            switch sheet {
            case .siriShortcuts: NavigationStack { SiriShortcutsView() }
            case .nfcWallet:     NavigationStack { NFCWalletView() }
            case .iotHub:        NavigationStack { IoTHubView() }
            }
        }
    }

    private func openURL(_ str: String) {
        if let url = URL(string: str) { UIApplication.shared.open(url) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

// MARK: - Minimal row

private struct IntRow: View {
    let icon: String
    let label: String
    var status: String = ""
    var toggleOn: Bool? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                if let on = toggleOn {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? .green : Color.secondary)
                } else if !status.isEmpty {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - IntegrationStatus label helper

private extension IntegrationStatus {
    var label: String {
        switch self {
        case .connected:           return "Connected"
        case .notConnected:        return "Off"
        case .loading:             return "Loading..."
        case .comingSoon:          return "Soon"
        case .active(let l):       return l
        case .deepLink(let l):     return l
        }
    }
}

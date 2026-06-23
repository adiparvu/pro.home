import SwiftUI

// MARK: - IntegrationsView sections

extension IntegrationsView {

    var appleEcosystemSection: some View {
        IntegrationGroup(title: "iOS & Apple Ecosystem") {
            NavigationLink {
                SiriShortcutsView()
            } label: {
                IntegrationRowContent(
                    icon: "mic.fill", color: Color(red: 0.58, green: 0.25, blue: 0.95),
                    title: "Siri & Shortcuts",
                    description: "Create tasks, water plants, and open features with your voice.",
                    status: .deepLink("Configure"))
            }

            IntegrationRow(icon: "magnifyingglass", color: Color(red: 0.2, green: 0.6, blue: 0.95),
                title: "Spotlight Search",
                description: "Tasks, plants, and documents appear in iOS Spotlight search results.",
                status: .active("Active"), action: nil)

            IntegrationRow(icon: "map.fill", color: Color(red: 0.25, green: 0.75, blue: 0.45),
                title: "Apple Maps",
                description: "View your property location and get directions in Maps.",
                status: .deepLink("Open"),
                action: {
                    if let lat = vm.property?.latitude, let lon = vm.property?.longitude {
                        let coords = "\(lat),\(lon)"
                        let name = (vm.property?.addressLine1 ?? "My Property").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "maps://?ll=\(coords)&q=\(name)") {
                            UIApplication.shared.open(url)
                        }
                    } else if let url = URL(string: "maps://") {
                        UIApplication.shared.open(url)
                    }
                })

            IntegrationRow(
                icon: "person.2.fill", color: Color(red: 0.95, green: 0.45, blue: 0.15),
                title: "Apple Contacts",
                description: "Sync family members to your iPhone Contacts.",
                status: vm.contactsStatus,
                action: { Task { await vm.toggleContacts() } })

            IntegrationRow(icon: "moon.fill", color: Color(red: 0.35, green: 0.35, blue: 0.85),
                title: "Focus Modes",
                description: "PRVIO notifications respect your iOS Focus settings automatically.",
                status: .active("Automatic"),
                action: {
                    let url = URL(string: "App-Prefs:FOCUS") ?? URL(string: UIApplication.openSettingsURLString)
                    if let url { UIApplication.shared.open(url) }
                })

            IntegrationRow(icon: "icloud.fill", color: Color(red: 0.25, green: 0.55, blue: 0.95),
                title: "iCloud Backup",
                description: "App data is included in your iPhone iCloud backup automatically.",
                status: .active("Automatic"), action: nil)
        }
    }

    var productivitySection: some View {
        IntegrationGroup(title: "Productivity") {
            IntegrationRow(icon: "calendar", color: .red,
                title: "Apple Calendar",
                description: "Sync tasks and maintenance reminders to your calendar.",
                status: vm.calendarStatus,
                action: { Task { await vm.toggleCalendar() } })
            IntegrationRow(icon: "checklist", color: Color(red: 0.25, green: 0.5, blue: 0.95),
                title: "Apple Reminders",
                description: "Add overdue tasks to Reminders for quick action.",
                status: vm.remindersStatus,
                action: { Task { await vm.toggleReminders() } })
            IntegrationRow(icon: "calendar.badge.clock", color: Color(red: 0.25, green: 0.7, blue: 1.0),
                title: "Google Calendar",
                description: "Sync household schedules with Google Calendar.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "doc.richtext.fill", color: Color(red: 0.15, green: 0.15, blue: 0.15),
                title: "Notion",
                description: "Export property documents and task lists to Notion.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "arrow.triangle.2.circlepath", color: Color(red: 0.98, green: 0.55, blue: 0.1),
                title: "IFTTT",
                description: "Automate home routines with thousands of app connections.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "bolt.shield.fill", color: Color(red: 0.35, green: 0.75, blue: 0.55),
                title: "Zapier",
                description: "Connect PRVIO to 5,000+ apps without code.",
                status: .comingSoon, action: nil)
        }
    }

    var smartHomeSection: some View {
        IntegrationGroup(title: "Smart Home") {
            IntegrationRow(icon: "homekit", color: Color(red: 0.98, green: 0.4, blue: 0.4),
                title: "Apple HomeKit",
                description: "Control smart home devices linked to your property.",
                status: .deepLink("Open Home"),
                action: { if let url = URL(string: "homeapp://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "house.circle.fill", color: Color(red: 0.12, green: 0.55, blue: 0.95),
                title: "Home Assistant",
                description: "Connect to your local Home Assistant for full smart home control.",
                status: URL(string: "homeassistant://").map { UIApplication.shared.canOpenURL($0) } == true ? .deepLink("Open") : .comingSoon,
                action: { if let url = URL(string: "homeassistant://navigate/lovelace/0") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "lightbulb.fill", color: .yellow,
                title: "Philips Hue",
                description: "Control lights and scenes across all rooms.",
                status: URL(string: "hue://").map { UIApplication.shared.canOpenURL($0) } == true ? .deepLink("Open") : .comingSoon,
                action: { if let url = URL(string: "hue://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "thermometer.medium", color: .orange,
                title: "Nest / Google Home",
                description: "Monitor and adjust temperature remotely.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "speaker.wave.2.fill", color: Color(red: 0.0, green: 0.45, blue: 1.0),
                title: "Sonos",
                description: "Manage whole-home audio from your property dashboard.",
                status: URL(string: "sonos://").map { UIApplication.shared.canOpenURL($0) } == true ? .deepLink("Open") : .comingSoon,
                action: { if let url = URL(string: "sonos://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "lock.shield.fill", color: Color(red: 0.3, green: 0.65, blue: 0.95),
                title: "August / Smart Lock",
                description: "Grant guest access and monitor door activity.",
                status: URL(string: "august-connects://").map { UIApplication.shared.canOpenURL($0) } == true ? .deepLink("Open") : .comingSoon,
                action: { if let url = URL(string: "august-connects://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "lightswitch.on.fill", color: Color(red: 0.0, green: 0.65, blue: 0.55),
                title: "IKEA TRÅDFRI",
                description: "Control IKEA smart lighting and blinds.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "atom", color: Color(red: 0.4, green: 0.7, blue: 0.95),
                title: "Matter & Thread",
                description: "Compatible Matter devices work automatically via Apple Home.",
                status: .active("Via HomeKit"), action: nil)
        }
    }

    var securitySection: some View {
        IntegrationGroup(title: "Security") {
            IntegrationRow(icon: "camera.fill", color: .indigo,
                title: "Security Cameras",
                description: "View live feeds and motion alerts from your cameras.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "bell.badge.fill", color: Color(red: 0.15, green: 0.45, blue: 0.9),
                title: "Ring Doorbell",
                description: "See who's at the door and get motion alerts.",
                status: URL(string: "ring://").map { UIApplication.shared.canOpenURL($0) } == true ? .deepLink("Open") : .comingSoon,
                action: { if let url = URL(string: "ring://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "sensor.tag.radiowaves.forward.fill", color: .purple,
                title: "Arlo / Eufy",
                description: "Integrate wireless security cameras and sensors.",
                status: .comingSoon, action: nil)
        }
    }

    var financeSection: some View {
        IntegrationGroup(title: "Finance & Banking") {
            IntegrationRow(icon: "banknote.fill", color: Color(red: 0.3, green: 0.75, blue: 0.45),
                title: "Revolut / Wise",
                description: "Auto-import home expenses from your bank transactions.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "creditcard.fill", color: Color(red: 0.25, green: 0.5, blue: 0.95),
                title: "Open Banking",
                description: "Connect your bank for automatic expense categorization.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "doc.text.viewfinder", color: .orange,
                title: "Receipt Scanner",
                description: "Scan and auto-categorize home improvement receipts.",
                status: .deepLink("Scan Now"),
                action: {
                    if let url = URL(string: "prvio://scan") { UIApplication.shared.open(url) }
                })
        }
    }

    var rentalsSection: some View {
        IntegrationGroup(title: "Rentals & Hospitality") {
            IntegrationRow(icon: "house.and.flag.fill", color: .teal,
                title: "Booking.com",
                description: "Manage short-term rental bookings and guest access.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "airplane.circle.fill", color: Color(red: 1.0, green: 0.3, blue: 0.3),
                title: "Airbnb",
                description: "Sync Airbnb calendar and automate guest check-ins.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "bed.double.fill", color: Color(red: 0.15, green: 0.45, blue: 0.9),
                title: "VRBO / HomeAway",
                description: "Connect VRBO listings to track occupancy and revenue.",
                status: .comingSoon, action: nil)
        }
    }

    var energySection: some View {
        IntegrationGroup(title: "Energy & Environment") {
            IntegrationRow(icon: "bolt.horizontal.circle.fill", color: Color(red: 0.3, green: 0.85, blue: 0.5),
                title: "Energy Provider",
                description: "Import utility bills automatically from your energy supplier.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "sun.max.circle.fill", color: .yellow,
                title: "Solar / PV System",
                description: "Monitor solar panel output and energy savings.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "car.fill", color: Color(red: 0.35, green: 0.75, blue: 0.35),
                title: "EV Charging",
                description: "Track charging sessions and energy costs for your EV.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "drop.circle.fill", color: Color(red: 0.2, green: 0.6, blue: 0.9),
                title: "Smart Water Meter",
                description: "Monitor water consumption and detect leaks early.",
                status: .comingSoon, action: nil)
        }
    }
}

// MARK: - Group + Row

struct IntegrationGroup<Content: View>: View {
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

struct IntegrationRow: View {
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
                .tint(.accentColor)
                .onTapGesture { action?() }
                .allowsHitTesting(true)

        case .loading:
            ProgressView()
                .tint(.accentColor)
                .scaleEffect(0.8)

        case .comingSoon:
            Text("Soon")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())

        case .active(let label):
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.12), in: Capsule())

        case .deepLink(let label):
            Button {
                action?()
            } label: {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct IntegrationRowContent: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let status: IntegrationStatus

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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.leading, 64)
        }
        .contentShape(Rectangle())
    }
}

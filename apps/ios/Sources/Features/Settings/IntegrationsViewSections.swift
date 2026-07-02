import SwiftUI

// MARK: - IntegrationsView sections

extension IntegrationsView {

    var appleEcosystemSection: some View {
        IntegrationGroup(title: "iOS & Apple Ecosystem") {
            Button { vm.activeSheet = .siriShortcuts } label: {
                IntegrationRowContent(
                    icon: "mic.fill", color: Color(red: 0.58, green: 0.25, blue: 0.95),
                    title: "Siri & Shortcuts",
                    description: "Create tasks, water plants, and open features with your voice.",
                    status: .deepLink("Configure"))
            }
            .buttonStyle(.plain)

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
                icon: "person.2.fill", color: Color.brandWarning,
                title: "Apple Contacts",
                description: "Sync family members to your iPhone Contacts.",
                status: vm.contactsStatus,
                action: { Task { await vm.toggleContacts() } })

            IntegrationRow(icon: "moon.fill", color: Color(red: 0.35, green: 0.35, blue: 0.85),
                title: "Focus Modes",
                description: "PRVIO notifications respect your iOS Focus settings automatically.",
                status: .active("Automatic"),
                action: {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })

            IntegrationRow(icon: "icloud.fill", color: Color(red: 0.25, green: 0.55, blue: 0.95),
                title: "iCloud Backup",
                description: "App data is included in your iPhone iCloud backup automatically.",
                status: .active("Automatic"), action: nil)

            IntegrationRow(icon: "cloud.fill", color: Color(red: 0.15, green: 0.45, blue: 0.95),
                title: "iCloud Sync",
                description: "Sincronizează documente și date între iPhone, iPad și Mac prin CloudKit.",
                status: vm.iCloudAvailable ? .active("Activ") : .notConnected,
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })

            Button { vm.activeSheet = .nfcWallet } label: {
                IntegrationRowContent(
                    icon: "wave.3.right", color: Color(red: 0.15, green: 0.65, blue: 0.85),
                    title: "NFC Keys",
                    description: "Scanează și gestionează tag-uri NFC pentru camere și echipamente — acces instant în Digital Twin.",
                    status: vm.nfcAvailable ? .active("Disponibil") : .notConnected)
            }
            .buttonStyle(.plain)
        }
    }

    var paymentsSection: some View {
        IntegrationGroup(title: "Plăți & Acces") {
            IntegrationRow(icon: "creditcard.fill", color: Color(red: 0.05, green: 0.05, blue: 0.05),
                title: "Apple Pay",
                description: "Plătești contractori și furnizori direct din aplicație cu Apple Pay.",
                status: vm.applePayAvailable ? .active("Disponibil") : .notConnected,
                action: nil)

            IntegrationRow(icon: "wallet.pass.fill", color: Color(red: 0.05, green: 0.45, blue: 0.95),
                title: "Wallet — Pașapoarte Acces",
                description: "Generează passes Wallet pentru contractori și oaspeți cu cod QR și dată de expirare.",
                status: .deepLink("Configurează"),
                action: {
                    if let url = URL(string: "shoebox://") ?? URL(string: "https://www.apple.com/wallet/") {
                        UIApplication.shared.open(url)
                    }
                })

            IntegrationRow(icon: "key.fill", color: Color(red: 0.55, green: 0.35, blue: 0.85),
                title: "AutoFill Credențiale",
                description: "Stochează parolele router, camere IP, panou solar — iOS AutoFill le sugerează automat.",
                status: .deepLink("Gestionează"),
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
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
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://calendar.google.com") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "doc.richtext.fill", color: Color(red: 0.15, green: 0.15, blue: 0.15),
                title: "Notion",
                description: "Export property documents and task lists to Notion.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.notion.so") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "arrow.triangle.2.circlepath", color: Color(red: 0.98, green: 0.55, blue: 0.1),
                title: "IFTTT",
                description: "Automate home routines with thousands of app connections.",
                status: .deepLink("Connect"),
                action: { if let url = URL(string: "https://ifttt.com/explore") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "bolt.shield.fill", color: Color(red: 0.35, green: 0.75, blue: 0.55),
                title: "Zapier",
                description: "Connect PRVIO to 5,000+ apps without code.",
                status: .deepLink("Connect"),
                action: { if let url = URL(string: "https://zapier.com/apps") { UIApplication.shared.open(url) } })
        }
    }

    var localControllersSection: some View {
        IntegrationGroup(title: "Local Controllers") {
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "cpu.fill", color: Color(red: 0.05, green: 0.75, blue: 0.45),
                    title: "ESP32",
                    description: "Connect ESP32 microcontrollers via HTTP REST. Auto-discovers sensors from JSON responses.",
                    status: .deepLink("Manage"))
            }
            .buttonStyle(.plain)
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "server.rack", color: Color(red: 0.85, green: 0.15, blue: 0.35),
                    title: "Raspberry Pi",
                    description: "Poll a Raspberry Pi running Flask or FastAPI for sensor data over HTTP.",
                    status: .deepLink("Manage"))
            }
            .buttonStyle(.plain)
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "network", color: Color(red: 0.35, green: 0.55, blue: 0.95),
                    title: "RS485 Modbus",
                    description: "Read Modbus TCP registers from industrial RS485 gateways (port 502).",
                    status: .deepLink("Manage"))
            }
            .buttonStyle(.plain)
        }
    }

    var smartHomeSection: some View {
        IntegrationGroup(title: "Smart Home") {
            IntegrationRow(icon: "homekit", color: Color(red: 0.35, green: 0.82, blue: 0.58),
                title: "Apple HomeKit",
                description: "Controlează becuri, prize și termostate smart din PRVIO fără să deschizi Casa.",
                status: vm.homeKitStatus,
                action: { vm.activateHomeKit() })
            IntegrationRow(icon: "house.circle.fill", color: Color(red: 0.12, green: 0.55, blue: 0.95),
                title: "Home Assistant",
                description: "Connect to your local Home Assistant for full smart home control.",
                status: .comingSoon,
                action: { if let url = URL(string: "homeassistant://navigate/lovelace/0") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "lightbulb.fill", color: .yellow,
                title: "Philips Hue",
                description: "Control lights and scenes across all rooms.",
                status: .comingSoon,
                action: { if let url = URL(string: "hue://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "thermometer.medium", color: .orange,
                title: "Nest / Google Home",
                description: "Monitor and adjust temperature remotely.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://home.google.com") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "speaker.wave.2.fill", color: Color(red: 0.0, green: 0.45, blue: 1.0),
                title: "Sonos",
                description: "Manage whole-home audio from your property dashboard.",
                status: .comingSoon,
                action: { if let url = URL(string: "sonos://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "lock.shield.fill", color: Color(red: 0.3, green: 0.65, blue: 0.95),
                title: "August / Smart Lock",
                description: "Grant guest access and monitor door activity.",
                status: .comingSoon,
                action: { if let url = URL(string: "august-connects://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "lightswitch.on.fill", color: Color(red: 0.0, green: 0.65, blue: 0.55),
                title: "IKEA TRÅDFRI",
                description: "Control IKEA smart lighting and blinds.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.ikea.com/us/en/customer-service/smart-home/") { UIApplication.shared.open(url) } })
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
                status: .deepLink("Set Up"),
                action: { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "bell.badge.fill", color: Color(red: 0.15, green: 0.45, blue: 0.9),
                title: "Ring Doorbell",
                description: "See who's at the door and get motion alerts.",
                status: .comingSoon,
                action: { if let url = URL(string: "ring://") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "sensor.tag.radiowaves.forward.fill", color: .purple,
                title: "Arlo / Eufy",
                description: "Integrate wireless security cameras and sensors.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.arlo.com") { UIApplication.shared.open(url) } })
        }
    }

    var financeSection: some View {
        IntegrationGroup(title: "Finance & Banking") {
            IntegrationRow(icon: "banknote.fill", color: Color(red: 0.3, green: 0.75, blue: 0.45),
                title: "Revolut / Wise",
                description: "Auto-import home expenses from your bank transactions.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://app.revolut.com") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "creditcard.fill", color: Color(red: 0.25, green: 0.5, blue: 0.95),
                title: "Open Banking",
                description: "Connect your bank for automatic expense categorization.",
                status: .deepLink("Learn More"),
                action: { if let url = URL(string: "https://www.openbanking.org.uk") { UIApplication.shared.open(url) } })
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
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.booking.com") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "airplane.circle.fill", color: Color(red: 1.0, green: 0.3, blue: 0.3),
                title: "Airbnb",
                description: "Sync Airbnb calendar and automate guest check-ins.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.airbnb.com") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "bed.double.fill", color: Color(red: 0.15, green: 0.45, blue: 0.9),
                title: "VRBO / HomeAway",
                description: "Connect VRBO listings to track occupancy and revenue.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.vrbo.com") { UIApplication.shared.open(url) } })
        }
    }

    var deliveriesSection: some View {
        IntegrationGroup(title: "Coletărie & Curierat") {
            IntegrationRow(
                icon: "shippingbox.fill", color: Color(red: 0.95, green: 0.55, blue: 0.10),
                title: "Fan Courier",
                description: "Conectează contul Fan Courier pentru tracking live și import automat AWB.",
                status: vm.courierStatus("fancourier"),
                action: { vm.connectCourier("fancourier", deepLink: "fancourier://") })

            IntegrationRow(
                icon: "box.truck.fill", color: Color(red: 0.80, green: 0.10, blue: 0.10),
                title: "Cargus",
                description: "Import automat colete Cargus din contul tău.",
                status: vm.courierStatus("cargus"),
                action: { vm.connectCourier("cargus", deepLink: "https://www.cargus.ro") })

            IntegrationRow(
                icon: "box.truck.fill", color: Color(red: 0.10, green: 0.45, blue: 0.85),
                title: "Sameday",
                description: "Urmărire live colete Sameday, inclusiv eMag.",
                status: vm.courierStatus("sameday"),
                action: { vm.connectCourier("sameday", deepLink: "sameday://") })

            IntegrationRow(
                icon: "shippingbox.fill", color: Color(red: 0.90, green: 0.70, blue: 0.0),
                title: "DHL",
                description: "Tracking colete DHL Express și DHL Parcel.",
                status: vm.courierStatus("dhl"),
                action: { vm.connectCourier("dhl", deepLink: "dhlexpress://") })

            IntegrationRow(
                icon: "shippingbox.fill", color: Color(red: 0.45, green: 0.15, blue: 0.55),
                title: "DPD",
                description: "Tracking live colete DPD România.",
                status: vm.courierStatus("dpd"),
                action: { vm.connectCourier("dpd", deepLink: "https://www.dpd.com/ro") })

            IntegrationRow(
                icon: "envelope.fill", color: Color(red: 0.15, green: 0.55, blue: 0.85),
                title: "Import din Email",
                description: "Conectează Gmail sau Outlook — PRVIO detectează automat AWB-urile din confirmările de comandă.",
                status: vm.emailImportStatus,
                action: { vm.activateEmailImport() })
        }
    }

    var energySection: some View {
        IntegrationGroup(title: "Energy & Environment") {
            IntegrationRow(icon: "bolt.horizontal.circle.fill", color: Color.brandSuccess,
                title: "Energy Provider",
                description: "Import utility bills automatically from your energy supplier.",
                status: .deepLink("Set Up"),
                action: { if let url = URL(string: "https://www.enel.ro") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "sun.max.circle.fill", color: .yellow,
                title: "Solar / PV System",
                description: "Monitor solar panel output and energy savings.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://pvoutput.org") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "car.fill", color: Color(red: 0.35, green: 0.75, blue: 0.35),
                title: "EV Charging",
                description: "Track charging sessions and energy costs for your EV.",
                status: .deepLink("Open"),
                action: { if let url = URL(string: "https://www.plugshare.com") { UIApplication.shared.open(url) } })
            IntegrationRow(icon: "drop.circle.fill", color: Color(red: 0.2, green: 0.6, blue: 0.9),
                title: "Smart Water Meter",
                description: "Monitor water consumption and detect leaks early.",
                status: .deepLink("Set Up"),
                action: { if let url = URL(string: "https://www.apator.com") { UIApplication.shared.open(url) } })
        }
    }
}

// MARK: - Group + Row

struct IntegrationGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }
}

struct IntegrationRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let status: IntegrationStatus
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: icon, color: color, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineLimit(2)
                }

                Spacer()

                statusBadge
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)

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
                .font(AppFont.caption2)
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xxs)
                .background(Color.primary.opacity(AppOpacity.hairline), in: Capsule())

        case .active(let label):
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(.green)
                .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xxs)
                .background(Color.green.opacity(0.12), in: Capsule())

        case .deepLink(let label):
            Button {
                action?()
            } label: {
                Text(label)
                    .font(AppFont.label)
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
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let status: IntegrationStatus

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: icon, color: color, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.leading, 64)
        }
        .contentShape(Rectangle())
    }
}

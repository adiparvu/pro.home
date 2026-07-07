import SwiftUI

// MARK: - IntegrationsView sections

extension IntegrationsView {

    var customIntegrationsSection: some View {
        NavigationLink {
            CustomIntegrationsView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect anything")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Text("Create your own integrations — each service gets its own secret key and posts straight into your chat.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(AppSpacing.base)
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
        .buttonStyle(.plain)
    }

    var appleEcosystemSection: some View {
        IntegrationGroup(title: "iOS & Apple Ecosystem") {
            Button { vm.activeSheet = .siriShortcuts } label: {
                IntegrationRowContent(
                    icon: "mic.fill", color: Color(red: 0.58, green: 0.25, blue: 0.95),
                    title: "Siri & Shortcuts",
                    description: "Create tasks, water plants, and open features with your voice.")
            }
            .buttonStyle(.plain)

            Button { vm.activeSheet = .watchShowcase } label: {
                IntegrationRowContent(
                    icon: "applewatch", color: Color.brandSkyBlue,
                    title: "Apple Watch",
                    description: "ws_row_desc")
            }
            .buttonStyle(.plain)

            IntegrationRow(icon: "magnifyingglass", color: Color.brandSkyBlue,
                title: "Spotlight Search",
                description: "Tasks, plants, and documents appear in iOS Spotlight search results.",
                status: .active(String(localized: "Active")), action: nil)

            IntegrationRow(icon: "map.fill", color: Color(red: 0.25, green: 0.75, blue: 0.45),
                title: "Apple Maps",
                description: "View your property location and get directions in Maps.",
                status: .deepLink(String(localized: "Deschide")),
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
                status: .active(String(localized: "Automatic")),
                action: {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })

            IntegrationRow(icon: "icloud.fill", color: Color.brandSkyBlue,
                title: "iCloud Backup",
                description: "App data is included in your iPhone iCloud backup automatically.",
                status: .active(String(localized: "Automatic")), action: nil)

            IntegrationRow(icon: "cloud.fill", color: Color(red: 0.15, green: 0.45, blue: 0.95),
                title: "iCloud Sync",
                description: "Sincronizează documente și date între iPhone, iPad și Mac prin CloudKit.",
                status: vm.iCloudAvailable
                    ? .active(String(localized: "Active"))
                    : .deepLink(String(localized: "Configure")),
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })

            Button { vm.activeSheet = .nfcWallet } label: {
                IntegrationRowContent(
                    icon: "wave.3.right", color: Color(red: 0.15, green: 0.65, blue: 0.85),
                    title: "NFC Keys",
                    description: "Scanează și gestionează tag-uri NFC pentru camere și echipamente — acces instant în Digital Twin.")
            }
            .buttonStyle(.plain)
        }
    }

    var paymentsSection: some View {
        IntegrationGroup(title: "Plăți & Acces") {
            // Informational when a card is set up; otherwise offers the real
            // system card-setup flow (PKPassLibrary.openPaymentSetup).
            IntegrationRow(icon: "creditcard.fill", color: Color(red: 0.05, green: 0.05, blue: 0.05),
                title: "Apple Pay",
                description: "Plăți rapide și sigure cu cardurile din Apple Wallet.",
                status: vm.applePayAvailable
                    ? .active(String(localized: "Disponibil"))
                    : .deepLink(String(localized: "Configure")),
                action: vm.applePayAvailable ? nil : { vm.openApplePaySetup() })

            // Signed Wallet passes are generated on the NFC Keys page
            // (AddToWalletButton → sign-pass edge function).
            Button { vm.activeSheet = .nfcWallet } label: {
                IntegrationRowContent(
                    icon: "wallet.pass.fill", color: Color(red: 0.05, green: 0.45, blue: 0.95),
                    title: "Wallet — Pașapoarte Acces",
                    description: "Generează passes semnate pentru tag-urile NFC ale casei și adaugă-le în Apple Wallet.")
            }
            .buttonStyle(.plain)

            // No in-app credentials manager ships yet — honest "Soon" pill.
            IntegrationRow(icon: "key.fill", color: Color(red: 0.55, green: 0.35, blue: 0.85),
                title: "AutoFill Credențiale",
                description: "Stochează parolele router, camere IP, panou solar — iOS AutoFill le sugerează automat.",
                status: .comingSoon,
                action: nil)
        }
    }

    var productivitySection: some View {
        IntegrationGroup(title: "Productivity") {
            IntegrationRow(icon: "calendar", color: .red,
                title: "Apple Calendar",
                description: "Sync tasks and maintenance reminders to your calendar.",
                status: vm.calendarStatus,
                action: { Task { await vm.toggleCalendar() } })
            IntegrationRow(icon: "checklist", color: Color.brandSkyBlue,
                title: "Apple Reminders",
                description: "Add overdue tasks to Reminders for quick action.",
                status: vm.remindersStatus,
                action: { Task { await vm.toggleReminders() } })
            // No Google Calendar / Notion sync exists yet — honest "Soon" pills.
            IntegrationRow(icon: "calendar.badge.clock", color: Color.brandSkyBlue,
                title: "Google Calendar",
                description: "Sync household schedules with Google Calendar.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "doc.richtext.fill", color: Color(red: 0.15, green: 0.15, blue: 0.15),
                title: "Notion",
                description: "Export property documents and task lists to Notion.",
                status: .comingSoon, action: nil)
            // IFTTT/Zapier integrate today through PRVIO's webhook keys
            // (Custom Integrations) — route to the real setup page.
            NavigationLink { CustomIntegrationsView() } label: {
                IntegrationRowContent(
                    icon: "arrow.triangle.2.circlepath", color: Color(red: 0.98, green: 0.55, blue: 0.1),
                    title: "IFTTT",
                    description: "Declanșează mesaje în PRVIO din applet-urile IFTTT printr-un webhook cu cheie secretă.")
            }
            .buttonStyle(.plain)
            NavigationLink { CustomIntegrationsView() } label: {
                IntegrationRowContent(
                    icon: "bolt.shield.fill", color: Color(red: 0.35, green: 0.75, blue: 0.55),
                    title: "Zapier",
                    description: "Conectează Zap-urile tale la PRVIO printr-un webhook cu cheie secretă.")
            }
            .buttonStyle(.plain)
        }
    }

    var localControllersSection: some View {
        IntegrationGroup(title: "Local Controllers") {
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "cpu.fill", color: Color(red: 0.05, green: 0.75, blue: 0.45),
                    title: "ESP32",
                    description: "Connect ESP32 microcontrollers via HTTP REST. Auto-discovers sensors from JSON responses.")
            }
            .buttonStyle(.plain)
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "server.rack", color: Color(red: 0.85, green: 0.15, blue: 0.35),
                    title: "Raspberry Pi",
                    description: "Poll a Raspberry Pi running Flask or FastAPI for sensor data over HTTP.")
            }
            .buttonStyle(.plain)
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "network", color: Color.brandSkyBlue,
                    title: "RS485 Modbus",
                    description: "Read Modbus TCP registers from industrial RS485 gateways (port 502).")
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
            // Home Assistant can post into the house chat today via a PRVIO
            // webhook key — route to the real Custom Integrations setup.
            NavigationLink { CustomIntegrationsView() } label: {
                IntegrationRowContent(
                    icon: "house.circle.fill", color: Color(red: 0.12, green: 0.55, blue: 0.95),
                    title: "Home Assistant",
                    description: "Trimite evenimente din Home Assistant în chat-ul casei printr-un webhook PRVIO.")
            }
            .buttonStyle(.plain)
            // No real backing for these yet — honest "Soon" pills, no dead links.
            IntegrationRow(icon: "lightbulb.fill", color: .yellow,
                title: "Philips Hue",
                description: "Control lights and scenes across all rooms.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "thermometer.medium", color: .orange,
                title: "Nest / Google Home",
                description: "Monitor and adjust temperature remotely.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "speaker.wave.2.fill", color: Color(red: 0.0, green: 0.45, blue: 1.0),
                title: "Sonos",
                description: "Manage whole-home audio from your property dashboard.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "lock.shield.fill", color: Color.brandSkyBlue,
                title: "August / Smart Lock",
                description: "Grant guest access and monitor door activity.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "lightswitch.on.fill", color: Color(red: 0.0, green: 0.65, blue: 0.55),
                title: "IKEA TRÅDFRI",
                description: "Control IKEA smart lighting and blinds.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "atom", color: Color.brandSkyBlue,
                title: "Matter & Thread",
                description: "Compatible Matter devices work automatically via Apple Home.",
                status: .active(String(localized: "Via HomeKit")), action: nil)
        }
    }

    var securitySection: some View {
        IntegrationGroup(title: "Security") {
            // IP cameras and motion sensors connect through the local IoT hub.
            Button { vm.activeSheet = .iotHub } label: {
                IntegrationRowContent(
                    icon: "camera.fill", color: .indigo,
                    title: "Security Cameras",
                    description: "Conectează camere IP și senzori de mișcare prin hub-ul IoT local.")
            }
            .buttonStyle(.plain)
            IntegrationRow(icon: "bell.badge.fill", color: Color(red: 0.15, green: 0.45, blue: 0.9),
                title: "Ring Doorbell",
                description: "See who's at the door and get motion alerts.",
                status: .comingSoon, action: nil)
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
            IntegrationRow(icon: "creditcard.fill", color: Color.brandSkyBlue,
                title: "Open Banking",
                description: "Connect your bank for automatic expense categorization.",
                status: .comingSoon, action: nil)
            // The OCR receipt scanner is real — open it directly.
            Button { vm.activeSheet = .receiptScanner } label: {
                IntegrationRowContent(
                    icon: "doc.text.viewfinder", color: .orange,
                    title: "Receipt Scanner",
                    description: "Scan and auto-categorize home improvement receipts.")
            }
            .buttonStyle(.plain)
        }
    }

    var rentalsSection: some View {
        IntegrationGroup(title: "Rentals & Hospitality") {
            // No rental-platform sync exists — honest "Soon" pills.
            IntegrationRow(icon: "house.and.flag.fill", color: .teal,
                title: "Booking.com",
                description: "Manage short-term rental bookings and guest access.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "airplane.circle.fill", color: Color.brandDanger,
                title: "Airbnb",
                description: "Sync Airbnb calendar and automate guest check-ins.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "bed.double.fill", color: Color(red: 0.15, green: 0.45, blue: 0.9),
                title: "VRBO / HomeAway",
                description: "Connect VRBO listings to track occupancy and revenue.",
                status: .comingSoon, action: nil)
        }
    }

    // Live courier tracking (Ship24 backend) lives on the Deliveries page —
    // every courier row navigates there instead of pretending to link accounts.
    var deliveriesSection: some View {
        IntegrationGroup(title: "Coletărie & Curierat") {
            NavigationLink { DeliveriesView() } label: {
                IntegrationRowContent(
                    icon: "shippingbox.fill", color: Color(red: 0.95, green: 0.55, blue: 0.10),
                    title: "Fan Courier",
                    description: "Urmărește coletele Fan Courier live în pagina Livrări.")
            }
            .buttonStyle(.plain)

            NavigationLink { DeliveriesView() } label: {
                IntegrationRowContent(
                    icon: "box.truck.fill", color: Color(red: 0.80, green: 0.10, blue: 0.10),
                    title: "Cargus",
                    description: "Urmărește coletele Cargus live în pagina Livrări.")
            }
            .buttonStyle(.plain)

            NavigationLink { DeliveriesView() } label: {
                IntegrationRowContent(
                    icon: "box.truck.fill", color: Color(red: 0.10, green: 0.45, blue: 0.85),
                    title: "Sameday",
                    description: "Urmărire live colete Sameday, inclusiv eMag, în pagina Livrări.")
            }
            .buttonStyle(.plain)

            NavigationLink { DeliveriesView() } label: {
                IntegrationRowContent(
                    icon: "shippingbox.fill", color: Color(red: 0.90, green: 0.70, blue: 0.0),
                    title: "DHL",
                    description: "Tracking colete DHL Express și DHL Parcel în pagina Livrări.")
            }
            .buttonStyle(.plain)

            NavigationLink { DeliveriesView() } label: {
                IntegrationRowContent(
                    icon: "shippingbox.fill", color: Color(red: 0.45, green: 0.15, blue: 0.55),
                    title: "DPD",
                    description: "Tracking live colete DPD România în pagina Livrări.")
            }
            .buttonStyle(.plain)

            // Real email-inbound setup: per-property forwarding address whose
            // emails the backend parses into tracked deliveries.
            Button { vm.activeSheet = .emailImport } label: {
                IntegrationRowContent(
                    icon: "envelope.fill", color: Color(red: 0.15, green: 0.55, blue: 0.85),
                    title: "Import din Email",
                    description: "Redirecționează confirmările de comandă către adresa ta PRVIO — AWB-urile sunt detectate automat.")
            }
            .buttonStyle(.plain)
        }
    }

    var energySection: some View {
        IntegrationGroup(title: "Energy & Environment") {
            // Energy readings & costs are tracked in the in-app Utilities module.
            NavigationLink { UtilityView() } label: {
                IntegrationRowContent(
                    icon: "bolt.horizontal.circle.fill", color: Color.brandSuccess,
                    title: "Energy Provider",
                    description: "Urmărește consumul și facturile de energie în modulul Utilități.")
            }
            .buttonStyle(.plain)
            IntegrationRow(icon: "sun.max.circle.fill", color: .yellow,
                title: "Solar / PV System",
                description: "Monitor solar panel output and energy savings.",
                status: .comingSoon, action: nil)
            IntegrationRow(icon: "car.fill", color: Color(red: 0.35, green: 0.75, blue: 0.35),
                title: "EV Charging",
                description: "Track charging sessions and energy costs for your EV.",
                status: .comingSoon, action: nil)
            NavigationLink { UtilityView() } label: {
                IntegrationRowContent(
                    icon: "drop.circle.fill", color: Color(red: 0.2, green: 0.6, blue: 0.9),
                    title: "Smart Water Meter",
                    description: "Monitorizează consumul lunar de apă în modulul Utilități.")
            }
            .buttonStyle(.plain)
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

/// Navigation-style row (chevron affordance) for rows that push or present a
/// real destination — the tap target is supplied by the enclosing
/// Button/NavigationLink.
struct IntegrationRowContent: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey

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

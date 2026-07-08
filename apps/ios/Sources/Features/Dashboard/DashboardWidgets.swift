import SwiftUI
import MapKit
import CoreLocation

extension DashboardView {

    // MARK: - Widget Grid

    var enabledWidgets: [HomeWidgetConfig] { HomeWidgetConfig.load() }

    // Groups widgets into rows honouring each widget's CHOSEN size:
    // full-width widgets get their own row, half-width ones pair left-right.
    var widgetRows: [[HomeWidgetConfig]] {
        var rows: [[HomeWidgetConfig]] = []
        var halfPending: HomeWidgetConfig? = nil
        for config in enabledWidgets {
            if config.size == .full {
                if let pending = halfPending {
                    rows.append([pending])
                    halfPending = nil
                }
                rows.append([config])
            } else {
                if let pending = halfPending {
                    rows.append([pending, config])
                    halfPending = nil
                } else {
                    halfPending = config
                }
            }
        }
        if let pending = halfPending { rows.append([pending]) }
        return rows
    }

    var widgetGrid: some View {
        VStack(spacing: 12) {
            ForEach(Array(widgetRows.enumerated()), id: \.offset) { _, row in
                if row.count == 1 && row[0].size == .full {
                    widgetView(for: row[0])
                } else {
                    HStack(spacing: 12) {
                        ForEach(row) { config in
                            widgetView(for: config)
                                .frame(maxWidth: .infinity)
                        }
                        if row.count == 1 {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func widgetView(for config: HomeWidgetConfig) -> some View {
        let type = config.type
        let size = config.size
        switch type {
        case .tasks:
            HomeWidget(
                icon: "checklist",
                iconColor: taskService.overdueCount > 0 ? .red : Color.brandSkyBlue,
                title: "Tasks",
                value: taskService.overdueCount > 0 ? "\(taskService.overdueCount)" : "\(taskService.openCount)",
                subtitle: taskService.overdueCount > 0 ? String(localized: "urgent") : String(localized: "active"),
                badge: taskService.overdueCount
            ) { router.selectedTab = .tasks }

        case .finances:
            HomeWidget(
                icon: "creditcard.fill",
                iconColor: financialService.currentMonthNet >= 0
                    ? Color.brandSuccess : .orange,
                title: "Finances",
                value: netFormatted,
                subtitle: String(localized: "this month")
            ) { router.navigate(to: .finances) }

        case .documents:
            HomeWidget(
                icon: "doc.fill",
                iconColor: documentService.expiringDocs.isEmpty
                    ? Color(red: 0.55, green: 0.55, blue: 0.95) : .orange,
                title: "Documents",
                value: documentService.expiringDocs.isEmpty
                    ? "\(documentService.documents.count)"
                    : "\(documentService.expiringDocs.count)",
                subtitle: documentService.expiringDocs.isEmpty ? String(localized: "total") : String(localized: "expiring soon"),
                badge: documentService.expiringDocs.count
            ) { router.navigate(to: .documents) }

        case .family:
            HomeWidget(
                icon: "person.2.fill",
                iconColor: Color(red: 0.7, green: 0.45, blue: 0.95),
                title: "Family",
                value: "\(familyService.members.count)",
                subtitle: familyService.members.count == 1 ? String(localized: "member") : String(localized: "members")
            ) { router.navigate(to: .family) }

        case .healthScore:
            HomeWidget(
                icon: "heart.fill",
                iconColor: .red,
                title: "Health",
                value: propertyService.primary?.healthScore.map { "\($0)" } ?? "–",
                subtitle: String(localized: "property score")
            ) { router.selectedTab = .digitalTwin }

        case .inventory:
            HomeWidget(
                icon: "shippingbox.fill",
                iconColor: .orange,
                title: "Inventory",
                value: "\(inventoryService.items.count)",
                subtitle: inventoryService.items.count == 1 ? String(localized: "item") : String(localized: "items")
            ) { router.navigate(to: .inventory) }

        case .contractors:
            HomeWidget(
                icon: "hammer.fill",
                iconColor: Color(red: 0.9, green: 0.65, blue: 0.2),
                title: "Contractors",
                value: "\(contractorService.contractors.count)",
                subtitle: contractorService.contractors.count == 1 ? String(localized: "contact") : String(localized: "contacts")
            ) { router.navigate(to: .contractors) }

        case .weather:
            if size == .full {
                WeatherWidget(
                    cityName: propertyService.primary?.city ?? "",
                    coordinate: propertyService.primary.flatMap {
                        guard let lat = $0.latitude, let lon = $0.longitude else { return nil }
                        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                ) {
                    if let url = URL(string: "weather://") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                // Half size: a compact tile that opens the forecast.
                HomeWidget(
                    icon: "cloud.sun.fill",
                    iconColor: Color.brandPrimaryBlue,
                    title: "Weather",
                    value: propertyService.primary?.city ?? "–",
                    subtitle: String(localized: "Tap for forecast")
                ) {
                    if let url = URL(string: "weather://") {
                        UIApplication.shared.open(url)
                    }
                }
            }

        case .plants:
            HomeWidget(
                icon: "leaf.fill",
                iconColor: plantService.plantsNeedingWater.isEmpty
                    ? Color(red: 0.25, green: 0.78, blue: 0.45)
                    : .orange,
                title: "Plants",
                value: "\(plantService.plants.count)",
                subtitle: plantService.plantsNeedingWater.isEmpty
                    ? String(localized: "all good")
                    : "\(plantService.plantsNeedingWater.count) need water",
                badge: plantService.plantsNeedingWater.count
            ) { router.navigate(to: .plants(id: nil)) }

        case .calendar:
            if size == .full {
                CalendarLargeWidget {
                    if let url = URL(string: "calshow://") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                HomeWidget(
                    icon: "calendar",
                    iconColor: .teal,
                    title: "Calendar",
                    value: "\(Calendar.current.component(.day, from: Date()))",
                    subtitle: Date().formatted(.dateTime.weekday(.wide))
                ) {
                    if let url = URL(string: "calshow://") {
                        UIApplication.shared.open(url)
                    }
                }
            }

        case .deliveries:
            HomeWidget(
                icon: "shippingbox.and.arrow.backward.fill",
                iconColor: Color.brandSkyBlue,
                title: "Deliveries",
                value: "\(deliveryService.activeDeliveries.count)",
                subtitle: String(localized: "in transit"),
                badge: deliveryService.activeDeliveries.count
            ) { router.navigate(to: .deliveries) }

        case .shopping:
            HomeWidget(
                icon: "cart.fill",
                iconColor: Color(red: 1.0, green: 0.62, blue: 0.04),
                title: "Shopping list",
                value: "\(supplyService.totalPending)",
                subtitle: String(localized: "to buy")
            ) { router.navigate(to: .supplies) }

        case .journal:
            HomeWidget(
                icon: "photo.stack.fill",
                iconColor: Color.brandPurple,
                title: "Photo Journal",
                value: "\(photoJournalService.entries.count)",
                subtitle: String(localized: "memories")
            ) { router.navigate(to: .photoJournal) }
        }
    }

    // MARK: - Helpers

    func healthScoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return Color(red: 0.20, green: 0.87, blue: 0.45)
        case 60..<80: return Color(red: 0.55, green: 0.85, blue: 0.20)
        case 40..<60: return Color(red: 1.0,  green: 0.78, blue: 0.05)
        case 20..<40: return Color(red: 1.0,  green: 0.55, blue: 0.05)
        case 10..<20: return Color(red: 1.0,  green: 0.27, blue: 0.12)
        default:      return Color(red: 0.82, green: 0.05, blue: 0.12)
        }
    }

    var monthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = .current
        return f.string(from: Date())
    }

    var netFormatted: String {
        let net = financialService.currentMonthNet
        return "\(net >= 0 ? "+" : "")" + financialService.moneyDisplay(net)
    }

    var propertyCoordinate: CLLocationCoordinate2D {
        if let lat = propertyService.primary?.latitude,
           let lon = propertyService.primary?.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return geocodedCoordinate ?? CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025)
    }

    func resolveMapCoordinate() async {
        guard let property = propertyService.primary else { return }

        if let lat = property.latitude, let lon = property.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            geocodedCoordinate = coord
            mapPosition = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            ))
            return
        }

        let addressString = [property.addressLine1, property.city, property.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !addressString.isEmpty else { return }

        do {
            let placemarks: [CLPlacemark] = try await withCheckedThrowingContinuation { cont in
                CLGeocoder().geocodeAddressString(addressString) { marks, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: marks ?? []) }
                }
            }
            if let location = placemarks.first?.location {
                let coord = location.coordinate
                geocodedCoordinate = coord
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                ))
            }
        } catch {
            // geocoding failed — map keeps last known position
        }
    }

    var displayName: String {
        profileService.profile?.preferredName ?? ""
    }

    var avatarInitial: String {
        let name = profileService.profile?.preferredName ?? profileService.profile?.fullName ?? ""
        return name.isEmpty ? "" : String(name.prefix(1).uppercased())
    }

    var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }

    var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 0
    }

    func startPulse() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

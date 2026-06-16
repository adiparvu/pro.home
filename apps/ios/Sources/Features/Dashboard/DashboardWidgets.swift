import SwiftUI
import MapKit
import CoreLocation

extension DashboardView {

    // MARK: - Widget Grid

    var enabledWidgets: [HomeWidgetType] { HomeWidgetType.load() }

    var widgetGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(enabledWidgets) { type in
                widgetView(for: type)
            }
        }
    }

    @ViewBuilder
    func widgetView(for type: HomeWidgetType) -> some View {
        switch type {
        case .tasks:
            HomeWidget(
                icon: "checklist",
                iconColor: taskService.overdueCount > 0 ? .red : Color(red: 0.35, green: 0.65, blue: 1.0),
                title: "Tasks",
                value: taskService.overdueCount > 0 ? "\(taskService.overdueCount)" : "\(taskService.openCount)",
                subtitle: taskService.overdueCount > 0 ? "urgent" : "active",
                badge: taskService.overdueCount
            ) { router.selectedTab = .tasks }

        case .finances:
            HomeWidget(
                icon: "creditcard.fill",
                iconColor: financialService.currentMonthNet >= 0
                    ? Color(red: 0.3, green: 0.85, blue: 0.45) : .orange,
                title: "Finances",
                value: netFormatted,
                subtitle: "this month"
            ) { router.selectedTab = .settings }

        case .documents:
            HomeWidget(
                icon: "doc.fill",
                iconColor: documentService.expiringDocs.isEmpty
                    ? Color(red: 0.55, green: 0.55, blue: 0.95) : .orange,
                title: "Documents",
                value: documentService.expiringDocs.isEmpty
                    ? "\(documentService.documents.count)"
                    : "\(documentService.expiringDocs.count)",
                subtitle: documentService.expiringDocs.isEmpty ? "total" : "expiring soon",
                badge: documentService.expiringDocs.count
            ) { router.selectedTab = .settings }

        case .family:
            HomeWidget(
                icon: "person.2.fill",
                iconColor: Color(red: 0.7, green: 0.45, blue: 0.95),
                title: "Family",
                value: "\(familyService.members.count)",
                subtitle: familyService.members.count == 1 ? "member" : "members"
            ) { router.selectedTab = .settings }

        case .healthScore:
            HomeWidget(
                icon: "heart.fill",
                iconColor: .red,
                title: "Health",
                value: propertyService.primary?.healthScore.map { "\($0)" } ?? "–",
                subtitle: "property score"
            ) { }

        case .inventory:
            HomeWidget(
                icon: "shippingbox.fill",
                iconColor: .orange,
                title: "Inventory",
                value: "–",
                subtitle: "items"
            ) { router.selectedTab = .settings }

        case .contractors:
            HomeWidget(
                icon: "hammer.fill",
                iconColor: Color(red: 0.9, green: 0.65, blue: 0.2),
                title: "Contractors",
                value: "–",
                subtitle: "active"
            ) { router.selectedTab = .settings }

        case .calendar:
            HomeWidget(
                icon: "calendar",
                iconColor: .teal,
                title: "Calendar",
                value: "\(Calendar.current.component(.day, from: Date()))",
                subtitle: monthName
            ) { }
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
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
    }

    var netFormatted: String {
        let sym = financialService.currencySymbol
        let abs = Int(Swift.abs(financialService.currentMonthNet))
        return financialService.currentMonthNet >= 0 ? "+\(abs)\(sym)" : "-\(abs)\(sym)"
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
        profileService.profile?.preferredName
            ?? auth.session?.user.email?.components(separatedBy: "@").first?.capitalized
            ?? "there"
    }

    var avatarInitial: String {
        String(displayName.prefix(1).uppercased())
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
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

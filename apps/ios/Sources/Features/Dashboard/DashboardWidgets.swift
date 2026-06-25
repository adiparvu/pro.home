import SwiftUI
import MapKit
import CoreLocation

extension DashboardView {

    // MARK: - Widget Grid

    var enabledWidgets: [HomeWidgetType] { HomeWidgetType.load() }

    // Groups widgets into rows: full-width widgets get their own row,
    // half-width widgets are paired left-right.
    var widgetRows: [[HomeWidgetType]] {
        var rows: [[HomeWidgetType]] = []
        var halfPending: HomeWidgetType? = nil
        for widget in enabledWidgets {
            if widget.isFullWidth {
                if let pending = halfPending {
                    rows.append([pending])
                    halfPending = nil
                }
                rows.append([widget])
            } else {
                if let pending = halfPending {
                    rows.append([pending, widget])
                    halfPending = nil
                } else {
                    halfPending = widget
                }
            }
        }
        if let pending = halfPending { rows.append([pending]) }
        return rows
    }

    var widgetGrid: some View {
        Group {
            if isEditingWidgets {
                widgetReorderList
            } else {
                widgetNormalGrid
            }
        }
    }

    private var widgetNormalGrid: some View {
        VStack(spacing: 12) {
            ForEach(Array(widgetRows.enumerated()), id: \.offset) { _, row in
                if row.count == 1 && row[0].isFullWidth {
                    widgetView(for: row[0])
                } else {
                    HStack(spacing: 12) {
                        ForEach(row) { type in
                            widgetView(for: type)
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

    private var widgetReorderList: some View {
        let sectionCount = sectionOrder.count
        let widgetCount = editableWidgets.count
        let totalRows = sectionCount + widgetCount
        return List {
            Section {
                ForEach(sectionOrder) { sec in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(sec.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: sec.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(sec.color)
                        }
                        Text(sec.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.primary.opacity(0.07))
                }
                .onMove { from, to in sectionOrder.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("Sections")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Section {
                ForEach(editableWidgets) { type in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(type.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: type.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(type.color)
                        }
                        Text(type.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.primary.opacity(0.07))
                }
                .onMove { from, to in editableWidgets.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("Overview Widgets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .frame(height: max(200, CGFloat(totalRows) * 56 + 80))
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
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
                subtitle: taskService.overdueCount > 0 ? String(localized: "urgent") : String(localized: "active"),
                badge: taskService.overdueCount
            ) { router.selectedTab = .tasks }

        case .finances:
            HomeWidget(
                icon: "creditcard.fill",
                iconColor: financialService.currentMonthNet >= 0
                    ? Color(red: 0.3, green: 0.85, blue: 0.45) : .orange,
                title: "Finances",
                value: netFormatted,
                subtitle: String(localized: "this month")
            ) { router.showFinances = true }

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
            ) { router.showDocuments = true }

        case .family:
            HomeWidget(
                icon: "person.2.fill",
                iconColor: Color(red: 0.7, green: 0.45, blue: 0.95),
                title: "Family",
                value: "\(familyService.members.count)",
                subtitle: familyService.members.count == 1 ? String(localized: "member") : String(localized: "members")
            ) { router.showFamily = true }

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
            ) { router.selectedTab = .settings; router.showSuppliesView = true }

        case .contractors:
            HomeWidget(
                icon: "hammer.fill",
                iconColor: Color(red: 0.9, green: 0.65, blue: 0.2),
                title: "Contractors",
                value: "\(contractorService.contractors.count)",
                subtitle: contractorService.contractors.count == 1 ? String(localized: "contact") : String(localized: "contacts")
            ) { router.showContractors = true }

        case .weather:
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
            ) { router.showWaterPlant = true }

        case .calendar:
            CalendarLargeWidget {
                if let url = URL(string: "calshow://") {
                    UIApplication.shared.open(url)
                }
            }
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

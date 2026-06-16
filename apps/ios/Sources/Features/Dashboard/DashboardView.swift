import SwiftUI
import MapKit
import CoreLocation

// MARK: - Dashboard (Scrollable Home)

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var deliveryService: DeliveryService

    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
    )
    @State private var geocodedCoordinate: CLLocationCoordinate2D?
    @State private var selectedSection: PropertySection? = nil
    @State private var pulsing = false
    @State private var showNotifications = false
    @State private var showEditProfile = false
    @State private var showSearch = false
    @State private var showWidgetPicker = false

    private let sections = PropertySection.all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                greetingHeader
                Spacer().frame(height: 22)
                mapCard
                Spacer().frame(height: 16)
                widgetSectionHeader
                Spacer().frame(height: 10)
                widgetGrid
                Spacer(minLength: 160)
            }
            .padding(.horizontal, 16)
            .padding(.top, topSafeArea + 8)
            .trackTabScroll()
            .padding(.bottom, 20)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("dashScroll")).minY)
                }
            )
        }
        .coordinateSpace(name: "dashScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
                tabBarVis.scrollOffset = y
            }
        }
        .background(appBackground.ignoresSafeArea())
        .floatingSpeedDial(.home, bottomPadding: bottomSafeArea + 80)
        .navigationBarHidden(true)
        .onAppear { startPulse() }
        .task(id: propertyService.primary?.id) {
            await resolveMapCoordinate()
        }
        .task(id: propertyService.primary?.id) {
            if let pid = propertyService.primary?.id {
                await zoneService.load(propertyId: pid)
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationCenterView()
                .environmentObject(auth)
        }
        .sheet(isPresented: $showEditProfile) {
            NavigationStack {
                EditProfileView()
                    .environmentObject(profileService)
            }
        }
        .sheet(isPresented: $showSearch) {
            GlobalSearchSheet()
                .environmentObject(taskService)
                .environmentObject(documentService)
                .environmentObject(plantService)
                .environmentObject(deliveryService)
        }
        .sheet(isPresented: $showWidgetPicker) {
            WidgetPickerSheet()
                .environmentObject(appSettings)
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { HapticFeedback.impact(.light); showEditProfile = true } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.3, green: 0.85, blue: 0.5),
                                         Color(red: 0.2, green: 0.65, blue: 0.9)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        if let url = profileService.profile?.avatarUrl.flatMap(URL.init) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                        .frame(width: 38, height: 38)
                                        .clipShape(Circle())
                                } else {
                                    Text(avatarInitial)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        } else {
                            Text(avatarInitial)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(greetingText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.5))
                        Text(displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let score = propertyService.primary?.healthScore {
                VStack(spacing: 1) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 7, weight: .bold))
                    Text("\(score)")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(healthScoreColor(score))
                .frame(width: 38, height: 38)
                .glassCircle()
                .allowsHitTesting(false)
            }

            Button {
                HapticFeedback.impact(.light)
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassCircle()

            Button {
                HapticFeedback.impact(.light)
                showNotifications.toggle()
            } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassCircle()
        }
    }

    // MARK: - Widget section header

    private var widgetSectionHeader: some View {
        HStack {
            Text("OVERVIEW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
            Spacer()
            Button {
                HapticFeedback.impact(.light)
                showWidgetPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .glassCircle()
        }
    }

    // MARK: - Greeting text

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning 🌅"
        case 12..<18: return "Good afternoon 👋"
        case 18..<22: return "Good evening 🌇"
        default:      return "Good night 🌙"
        }
    }

    // MARK: - Map Card

    private var mapCard: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                Annotation("Property", coordinate: propertyCoordinate) {
                    PropertyCoreMarker(pulsing: $pulsing) {
                        router.selectedTab = .digitalTwin
                        HapticFeedback.impact(.medium)
                    }
                }
                ForEach(zoneService.zones) { zone in
                    if zone.isDrawable {
                        MapPolygon(coordinates: zone.coordinates)
                            .foregroundStyle(zone.tint.opacity(0.28))
                            .stroke(zone.tint.opacity(0.9), lineWidth: 1.5)
                    }
                }
                if zoneService.zones.isEmpty {
                    ForEach(sections) { section in
                        Annotation(section.name, coordinate: section.offset(from: propertyCoordinate)) {
                            PropertyPointMarker(section: section, isSelected: selectedSection?.id == section.id) {
                                router.selectedTab = .digitalTwin
                                HapticFeedback.impact(.light)
                            }
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls { }
            .frame(height: 260)
            .overlay(alignment: .topTrailing) {
                Button {
                    HapticFeedback.impact(.light)
                    router.selectedTab = .digitalTwin
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .padding(12)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(propertyService.primary?.name ?? "My property")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let addr = propertyService.primary?.addressLine1 {
                        Text(addr)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let section = selectedSection {
                    HStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(section.color)
                        Text(section.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(section.color.opacity(0.18), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .liquidGlass(cornerRadius: 20)
    }

    // MARK: - Widget Grid

    private var enabledWidgets: [HomeWidgetType] { HomeWidgetType.load() }

    private var widgetGrid: some View {
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
    private func widgetView(for type: HomeWidgetType) -> some View {
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

    private func healthScoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return Color(red: 0.20, green: 0.87, blue: 0.45)
        case 60..<80: return Color(red: 0.55, green: 0.85, blue: 0.20)
        case 40..<60: return Color(red: 1.0,  green: 0.78, blue: 0.05)
        case 20..<40: return Color(red: 1.0,  green: 0.55, blue: 0.05)
        case 10..<20: return Color(red: 1.0,  green: 0.27, blue: 0.12)
        default:      return Color(red: 0.82, green: 0.05, blue: 0.12)
        }
    }

    private var monthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
    }

    // MARK: - Helpers

    private var netFormatted: String {
        let sym = financialService.currencySymbol
        let abs = Int(Swift.abs(financialService.currentMonthNet))
        return financialService.currentMonthNet >= 0 ? "+\(abs)\(sym)" : "-\(abs)\(sym)"
    }

    private var propertyCoordinate: CLLocationCoordinate2D {
        if let lat = propertyService.primary?.latitude,
           let lon = propertyService.primary?.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return geocodedCoordinate ?? CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025)
    }

    private func resolveMapCoordinate() async {
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

    private var displayName: String {
        profileService.profile?.preferredName
            ?? auth.session?.user.email?.components(separatedBy: "@").first?.capitalized
            ?? "there"
    }

    private var avatarInitial: String {
        String(displayName.prefix(1).uppercased())
    }

    private var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }

    private var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 0
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

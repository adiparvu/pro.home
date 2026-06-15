import SwiftUI
import MapKit

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
            let shouldCollapse = y < -30
            if shouldCollapse != tabBarVis.scrolledDown {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    tabBarVis.scrolledDown = shouldCollapse
                }
            }
        }
        .background(appBackground.ignoresSafeArea())
        .floatingSpeedDial(.home, bottomPadding: bottomSafeArea + 80)
        .navigationBarHidden(true)
        .onAppear { startPulse() }
        .task {
            if let lat = propertyService.primary?.latitude,
               let lon = propertyService.primary?.longitude {
                mapPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                ))
            }
        }
        .task(id: propertyService.primary?.id) {
            if let pid = propertyService.primary?.id {
                await zoneService.load(propertyId: pid)
            }
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack {
                NotificationsSettingsView()
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
            }
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
            // Avatar — tapping opens Edit Profile
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

            // Health score — glass circle matching the search/bell buttons
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

            // Global search
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

            // Notifications
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
                        router.selectedTab = .map
                        HapticFeedback.impact(.medium)
                    }
                }
                // Live Digital Twin preview — real zones drawn over satellite
                ForEach(zoneService.zones) { zone in
                    if zone.isDrawable {
                        MapPolygon(coordinates: zone.coordinates)
                            .foregroundStyle(zone.tint.opacity(0.28))
                            .stroke(zone.tint.opacity(0.9), lineWidth: 1.5)
                    }
                }
                // Fallback decorative sections only until real zones exist
                if zoneService.zones.isEmpty {
                    ForEach(sections) { section in
                        Annotation(section.name, coordinate: section.offset(from: propertyCoordinate)) {
                            PropertyPointMarker(section: section, isSelected: selectedSection?.id == section.id) {
                                router.selectedTab = .map
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
                    router.selectedTab = .map
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

    // MARK: - Widget Grid (dynamic — driven by WidgetPicker selection)

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
            ) { router.selectedTab = .analytics }

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
        case 80...: return Color(red: 0.20, green: 0.87, blue: 0.45)  // bright green
        case 60..<80: return Color(red: 0.55, green: 0.85, blue: 0.20) // lime / yellow-green
        case 40..<60: return Color(red: 1.0,  green: 0.78, blue: 0.05) // amber
        case 20..<40: return Color(red: 1.0,  green: 0.55, blue: 0.05) // orange
        case 10..<20: return Color(red: 1.0,  green: 0.27, blue: 0.12) // red-orange
        default:      return Color(red: 0.82, green: 0.05, blue: 0.12) // deep red
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
        return CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025)
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

// MARK: - Home Widget Card

struct HomeWidget: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconColor.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    Spacer()
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 16)
    }
}

// MARK: - Property Core Marker

struct PropertyCoreMarker: View {
    @Binding var pulsing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(pulsing ? 0.08 : 0.22))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulsing ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)

                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(pulsing ? 0.15 : 0.3))
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulsing ? 1.08 : 0.95)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2), value: pulsing)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.25, green: 0.92, blue: 0.5), Color(red: 0.1, green: 0.75, blue: 0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 42, height: 42)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.8), radius: 16)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.4), radius: 30)

                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Property Point Marker

struct PropertyPointMarker: View {
    let section: PropertySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(section.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                }
                Circle()
                    .fill(isSelected
                        ? LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(isSelected ? section.color : .white.opacity(0.3), lineWidth: 1.5))
                    .shadow(color: isSelected ? section.color.opacity(0.5) : .black.opacity(0.3), radius: isSelected ? 8 : 4)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thumbnail Card

struct ThumbnailCard: View {
    let section: PropertySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected
                            ? LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? section.color.opacity(0.5) : .white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: isSelected ? section.color.opacity(0.4) : .black.opacity(0.2), radius: isSelected ? 12 : 4)
                    Image(systemName: section.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                }
                Text(section.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Property Section model

struct PropertySection: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let latOffset: Double
    let lonOffset: Double

    func offset(from coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coord.latitude + latOffset * 0.0003,
            longitude: coord.longitude + lonOffset * 0.0003
        )
    }

    static let all: [PropertySection] = [
        PropertySection(name: "House",      icon: "house.fill",       color: Color(red: 0.35, green: 0.65, blue: 1.0),  latOffset:  1.2, lonOffset:  0.0),
        PropertySection(name: "Yard",      icon: "leaf.fill",        color: Color(red: 0.3,  green: 0.85, blue: 0.45), latOffset: -0.8, lonOffset:  0.9),
        PropertySection(name: "Garage",    icon: "car.fill",         color: Color(red: 0.9,  green: 0.65, blue: 0.2),  latOffset: -1.2, lonOffset: -0.5),
        PropertySection(name: "Garden",    icon: "tree.fill",        color: Color(red: 0.25, green: 0.75, blue: 0.35), latOffset:  0.5, lonOffset:  1.3),
        PropertySection(name: "Solar",     icon: "sun.max.fill",     color: Color(red: 1.0,  green: 0.85, blue: 0.2),  latOffset:  1.0, lonOffset: -1.2),
        PropertySection(name: "Gazebo",    icon: "umbrella.fill",    color: Color(red: 0.7,  green: 0.45, blue: 0.95), latOffset: -0.5, lonOffset:  1.5),
        PropertySection(name: "Pool",      icon: "drop.fill",        color: Color(red: 0.2,  green: 0.75, blue: 0.95), latOffset: -1.5, lonOffset:  0.8),
        PropertySection(name: "Utilities", icon: "bolt.fill",        color: Color(red: 1.0,  green: 0.55, blue: 0.2),  latOffset:  0.8, lonOffset: -1.5),
        PropertySection(name: "Projects",  icon: "hammer.fill",      color: Color(red: 0.95, green: 0.35, blue: 0.35), latOffset: -1.0, lonOffset: -1.3),
        PropertySection(name: "Documents", icon: "doc.fill",         color: Color(red: 0.55, green: 0.55, blue: 0.95), latOffset:  1.5, lonOffset:  0.6),
        PropertySection(name: "Inventory", icon: "shippingbox.fill", color: Color(red: 0.8,  green: 0.5,  blue: 0.3),  latOffset: -0.3, lonOffset: -1.8),
    ]
}

// MARK: - Health Score Card

struct HealthScoreCard: View {
    let score: Int
    let isLoading: Bool

    private var color: Color {
        score >= 80 ? Color(red: 0.25, green: 0.88, blue: 0.55)
            : score >= 55 ? Color.orange
            : Color.red
    }
    private var label: String {
        score >= 80 ? "Excellent" : score >= 60 ? "Good" : score >= 40 ? "Fair" : "Needs Attention"
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: isLoading ? 0 : CGFloat(score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.1, dampingFraction: 0.8), value: score)
                    VStack(spacing: 1) {
                        Text(isLoading ? "–" : "\(score)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("/ 100")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Health")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isLoading ? "Loading…" : label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                    Text(isLoading ? " " : score >= 80
                         ? "Everything looks on track."
                         : "Some tasks need attention.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Stat Card

struct DashStatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Dash Task Row

struct DashTaskRow: View {
    let task: MaintenanceTask

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.priorityColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.38) : Color.white)
                    .strikethrough(task.isCompleted, color: Color.primary.opacity(0.35))
                    .lineLimit(1)
                Text(task.dueDateDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(task.isOverdue ? .red.opacity(0.8) : Color.primary.opacity(0.38))
            }

            Spacer()

            Text(task.statusDisplay)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Finances Snapshot

struct FinancesSnapshotCard: View {
    let income: Double
    let expenses: Double
    let net: Double
    let symbol: String
    var isLoading: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Finances")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("This month")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                if isLoading {
                    HStack { Spacer(); ProgressView().tint(.white).scaleEffect(0.8); Spacer() }
                } else {
                    HStack(spacing: 0) {
                        FinStat(label: "Income", value: formatted(income), color: Color(red: 0.25, green: 0.88, blue: 0.55))
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 34)
                        FinStat(label: "Expenses", value: formatted(expenses), color: .orange)
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 34)
                        FinStat(label: "Net", value: formatted(net), color: net >= 0 ? .white : .red)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "\(symbol)%.0f", value)
    }
}

private struct FinStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared background

var appBackground: Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)
            : UIColor(red: 0.96, green: 0.96, blue: 0.985, alpha: 1)
    })
}

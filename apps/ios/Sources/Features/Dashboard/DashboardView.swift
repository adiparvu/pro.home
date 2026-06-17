import SwiftUI
import MapKit
import CoreLocation

// MARK: - Dashboard (Scrollable Home)

struct DashboardView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var taskService: TaskService
    @EnvironmentObject var propertyService: PropertyService
    @EnvironmentObject var financialService: FinancialService
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var familyService: FamilyService
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var deliveryService: DeliveryService

    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
    )
    @State var geocodedCoordinate: CLLocationCoordinate2D?
    @State private var selectedSection: PropertySection? = nil
    @State var pulsing = false
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
}

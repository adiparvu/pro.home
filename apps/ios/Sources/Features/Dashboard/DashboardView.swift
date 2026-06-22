import SwiftUI
import MapKit
import CoreLocation

// MARK: - Dashboard — matches dark mockup exactly

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
    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @EnvironmentObject var inventoryService: InventoryService
    @EnvironmentObject var contractorService: ContractorService
    @EnvironmentObject var proactiveEngine: ProactiveEngine

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
                // ── Header ──────────────────────────────────────────────
                dashHeader
                    .padding(.horizontal, 16)

                Spacer().frame(height: 14)

                // ── Aerial Hero Card ─────────────────────────────────────
                aerialHero
                    .padding(.horizontal, 16)

                Spacer().frame(height: 14)

                // ── Property Health Card ─────────────────────────────────
                propertyHealthCard
                    .padding(.horizontal, 16)

                // ── Proactive Insights ───────────────────────────────────
                if !proactiveEngine.activeInsights.isEmpty {
                    ProactiveInsightsStrip(engine: proactiveEngine)
                        .padding(.horizontal, 16)
                    Spacer().frame(height: 14)
                }

                Spacer().frame(height: 14)

                // ── Stats Strip ──────────────────────────────────────────
                dashStatsStrip
                    .padding(.horizontal, 16)

                Spacer().frame(height: 22)

                // ── Widget section ───────────────────────────────────────
                widgetSectionHeader
                    .padding(.horizontal, 16)
                Spacer().frame(height: 10)
                widgetGrid
                    .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
            .padding(.top, topSafeArea + 6)
            .trackTabScroll()
            .padding(.bottom, 20)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                           value: geo.frame(in: .named("dashScroll")).minY)
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
        .floatingSpeedDial(.home)
        .navigationBarHidden(true)
        .onAppear { startPulse() }
        .task(id: propertyService.primary?.id) { await resolveMapCoordinate() }
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
                .environmentObject(familyService)
                .environmentObject(financialService)
                .environmentObject(elementService)
                .environmentObject(router)
        }
        .sheet(isPresented: $showWidgetPicker) {
            WidgetPickerSheet()
                .environmentObject(appSettings)
        }
    }

    // MARK: - Header

    private var dashHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { HapticFeedback.impact(.light); showEditProfile = true } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.25, green: 0.82, blue: 0.48),
                                         Color(red: 0.18, green: 0.60, blue: 0.88)],
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
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        } else {
                            Text(avatarInitial)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(propertyService.primary?.name ?? "My Property")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.87, blue: 0.48))
                                .frame(width: 5, height: 5)
                            Text("Live")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(red: 0.20, green: 0.87, blue: 0.48))
                        }
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
                .frame(width: 36, height: 36)
                .glassCircle()
                .allowsHitTesting(false)
            }

            Button { HapticFeedback.impact(.light); showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()

            Button { HapticFeedback.impact(.light); showNotifications.toggle() } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
        }
    }

    // MARK: - Aerial Hero Card

    private var aerialHero: some View {
        ZStack(alignment: .bottomLeading) {
            AerialPropertyView(
                property: propertyService.primary,
                zones: zoneService.zones,
                elements: elementService.elements,
                cornerRadius: 20
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)

            if let score = propertyService.primary?.healthScore {
                PropertyHealthGauge(score: score, size: 82)
                    .padding(14)
            }

            Button {
                HapticFeedback.impact(.light)
                router.selectedTab = .digitalTwin
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let name = propertyService.primary?.name {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    if let addr = propertyService.primary?.addressLine1 {
                        Text(addr)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 6)
    }

    // MARK: - Property Health Card

    private var propertyHealthCard: some View {
        let score = propertyService.primary?.healthScore ?? 87
        let overdueTasks = taskService.overdueCount
        let tasksPct = taskService.tasks.isEmpty ? 0 :
            Int(Double(taskService.tasks.filter { $0.isCompleted }.count) / Double(taskService.tasks.count) * 100)
        return PropertyHealthDashCard(
            score: score,
            maintenancePct: min(100, max(0, score - 10)),
            utilitiesPct: min(100, max(0, score + 5)),
            securityPct: min(100, max(0, score - 3)),
            tasksPct: tasksPct
        )
    }

    // MARK: - Stats Strip

    private var dashStatsStrip: some View {
        DashStatsStrip(items: [
            .init(value: "\(zoneService.zones.count)", label: "Zones"),
            .init(value: "\(elementService.elements.count)", label: "Objects"),
            .init(value: "\(taskService.tasks.filter { !$0.isCompleted }.count)", label: "Tasks"),
            .init(value: "\(taskService.overdueCount)", label: "Alerts")
        ])
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
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<22: return "Good evening"
        default:      return "Good night"
        }
    }
}

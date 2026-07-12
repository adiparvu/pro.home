import SwiftUI
import MapKit
import CoreLocation

// MARK: - Dashboard — matches dark mockup exactly

struct DashboardView: View {
    @Environment(AuthService.self) var auth
    @Environment(TaskService.self) var taskService
    @Environment(PropertyService.self) var propertyService
    @Environment(FinancialService.self) var financialService
    @Environment(ProfileService.self) var profileService
    @Environment(DocumentService.self) var documentService
    @Environment(FamilyService.self) var familyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) var router
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) var plantService
    // Not private: DashboardWidgets.swift (extension, separate file) renders
    // the Deliveries widget from it.
    @Environment(DeliveryService.self) var deliveryService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(InventoryService.self) var inventoryService
    @Environment(ContractorService.self) var contractorService
    @Environment(SupplyService.self) var supplyService
    @Environment(PhotoJournalService.self) var photoJournalService
    @Environment(ProactiveEngine.self) var proactiveEngine

    @State var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
    )
    @State var geocodedCoordinate: CLLocationCoordinate2D?
    @State private var selectedSection: PropertySection? = nil
    @State var pulsing = false
    @State private var notificationService = NotificationService()
    // A single presentation slot. Multiple stacked `.sheet(isPresented:)` on one
    // view conflict in SwiftUI (only the last reliably presents), which is why
    // search / notifications / profile silently did nothing. One `.sheet(item:)`
    // driven by this enum fixes all of them.
    @State private var activeSheet: DashboardSheet?

    private enum DashboardSheet: Int, Identifiable {
        case notifications, editProfile, search, widgetPicker, healthDetail
        var id: Int { rawValue }
    }
    @State var sectionOrder: [HomeSectionType] = HomeSectionType.load()

    private let sections = PropertySection.all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────
                dashHeader
                    .padding(.horizontal, AppSpacing.lg)

                Spacer().frame(height: 14)

                // ── Smart Home (S2): rooms, scenes, device cards ─────────
                SmartHomeSection()
                    .padding(.horizontal, AppSpacing.lg)

                Spacer().frame(height: 14)

                // ── Aerial Hero Card ─────────────────────────────────────
                aerialHero
                    .padding(.horizontal, AppSpacing.lg)

                // ── Today: what needs you, actionable in place ───────────
                Spacer().frame(height: 14)
                todaySection
                    .padding(.horizontal, AppSpacing.lg)

                // ── Proactive Insights (fixed after hero) ────────────────
                if !proactiveEngine.activeInsights.isEmpty {
                    Spacer().frame(height: 14)
                    ProactiveInsightsStrip(engine: proactiveEngine)
                        .padding(.horizontal, AppSpacing.lg)
                }

                // ── Reorderable sections ──────────────────────────────────
                ForEach(sectionOrder) { section in
                    sectionView(section)
                }

                Spacer(minLength: 120)
            }
            .padding(.top, topSafeArea + 6)
            .trackTabScroll()
            .padding(.bottom, AppSpacing.xl)
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
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await notificationService.load(userId: uid)
            await notificationService.subscribeRealtime(userId: uid)
        }
        // Router integration: a route change closes whatever local sheet
        // (search / notifications / health) is still up so the new
        // destination can actually present. The router presents its own
        // notification center from MainTabView; the bell keeps this local one.
        .onChange(of: router.dismissGeneration) { _, _ in
            activeSheet = nil
        }
        .onChange(of: activeSheet) { _, sheet in
            router.hasLocalPresentation = (sheet != nil)
        }
        .onDisappear {
            // A tab switch mid-sheet must not leave the router thinking a
            // local presentation is still up (routes would park forever).
            if activeSheet == nil { router.hasLocalPresentation = false }
        }
        .sheet(item: $activeSheet, onDismiss: { router.drainPending() }) { sheet in
            switch sheet {
            case .notifications:
                NavigationStack {
                    NotificationCenterView(service: notificationService)
                        .environment(auth)
                        .environment(router)
                }
                .presentationDragIndicator(.visible)
            case .editProfile:
                NavigationStack {
                    EditProfileView()
                        .environment(profileService)
                }
            case .search:
                GlobalSearchSheet()
                    .environment(taskService)
                    .environment(documentService)
                    .environment(plantService)
                    .environment(deliveryService)
                    .environment(familyService)
                    .environment(financialService)
                    .environment(elementService)
                    .environment(router)
            case .widgetPicker:
                WidgetPickerSheet()
            case .healthDetail:
                let score = propertyService.primary?.healthScore ?? 87
                NavigationStack {
                    PropertyHealthDetailView(
                        score: score,
                        maintenancePct: min(100, max(0, score - 10)),
                        utilitiesPct: min(100, max(0, score + 5)),
                        securityPct: min(100, max(0, score - 3)),
                        tasksPct: taskService.tasks.isEmpty ? 0 :
                            Int(Double(taskService.tasks.filter { $0.isCompleted }.count) / Double(taskService.tasks.count) * 100),
                        narrative: healthNarrative
                    )
                }
            }
        }
    }

    // MARK: - Header

    private var dashHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateString)
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                // Composed from Texts so both parts resolve through the
                // in-app locale — never the device language.
                greetingTitle
                    .font(AppFont.scaled(26, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            Button { HapticFeedback.impact(.light); activeSheet = .search } label: {
                Image(systemName: "magnifyingglass")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel("Search")

            Button { HapticFeedback.impact(.light); activeSheet = .notifications } label: {
                Image(systemName: "bell.fill")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        // Numeric badge ONLY while there are unread
                        // notifications — no static status dots.
                        if notificationService.unreadCount > 0 {
                            Text(notificationService.unreadCount > 99
                                 ? "99+" : "\(notificationService.unreadCount)")
                                .font(AppFont.scaled(10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4.5).padding(.vertical, 1.5)
                                .background(Color.red, in: Capsule())
                                .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                                .offset(x: -2, y: 4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(notificationService.unreadCount > 0
                                ? "Notifications, new" : "Notifications")

            // The avatar goes straight to the Profile page itself — pushed,
            // so the dashboard stays underneath.
            Button {
                HapticFeedback.impact(.light)
                router.push(.profile)
            } label: {
                avatarCircle
            }
            .buttonStyle(.plain)
        }
    }

    /// One formatter for the app's lifetime — the header re-renders on
    /// every scroll tick, and DateFormatter construction is too expensive
    /// to pay per frame. Main-actor only, so mutating the locale is safe.
    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var dateString: String {
        let f = Self.headerFormatter
        // Follow the language chosen in the app, not the device.
        if f.locale != appSettings.appLocale { f.locale = appSettings.appLocale }
        return f.string(from: Date())
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.82, blue: 0.48),
                             Color(red: 0.18, green: 0.60, blue: 0.88)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            if let url = profileService.profile?.avatarUrl.flatMap(URL.init) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                    } else {
                        Text(avatarInitial)
                            .font(AppFont.scaled(15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text(avatarInitial)
                    .font(AppFont.scaled(15, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 42, height: 42)
    }

    // MARK: - Aerial background (drone photo or canvas illustration)

    @ViewBuilder private var aerialBackground: some View {
        if let primary = propertyService.primary {
            AerialCanvasView(
                property: primary,
                elements: elementService.elements,
                elementBadges: heroBadges,
                showNames: false
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
        } else {
            AerialPropertyView(
                property: propertyService.primary,
                zones: zoneService.zones,
                elements: elementService.elements,
                cornerRadius: 20
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Aerial Hero Card

    private var aerialHero: some View {
        ZStack(alignment: .bottomLeading) {
            aerialBackground
                // Decorative on the dashboard — never a tap target (and never
                // again a screen-wide invisible one).
                .allowsHitTesting(false)

            // The health story in one sentence, living on the photo itself.
            HeroStatusPill(
                todayCount: todayItems.count,
                healthScore: propertyService.primary?.healthScore ?? 87,
                onTap: { activeSheet = .healthDetail }
            )
            .padding(AppSpacing.md)

            Button {
                HapticFeedback.impact(.light)
                router.selectedTab = .digitalTwin
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand Digital Twin")
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let name = propertyService.primary?.name {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(name)
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white.opacity(0.9))
                    if let addr = propertyService.primary?.addressLine1 {
                        Text(addr)
                            .font(AppFont.scaled(10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 6)
    }

    // MARK: - Widget section header

    private var widgetSectionHeader: some View {
        HStack {
            Text("OVERVIEW")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            Spacer()
            // One entry point: the + opens the widget manager, which owns
            // adding, removing, resizing AND drag-reordering (the separate
            // reorder button duplicated it and is gone).
            Button {
                HapticFeedback.impact(.light)
                activeSheet = .widgetPicker
            } label: {
                Image(systemName: "plus")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel("Add widget")
        }
    }

    // MARK: - Section view (renders each reorderable section)

    @ViewBuilder
    private func sectionView(_ section: HomeSectionType) -> some View {
        switch section {
        case .healthCard, .statsStrip:
            // Retired from the home screen: health lives in the hero status
            // pill (tap → full detail) and the counters became the "Today"
            // card — numbers without actions don't earn dashboard space.
            EmptyView()

        case .widgets:
            Group {
                Spacer().frame(height: 22)
                widgetSectionHeader
                    .padding(.horizontal, AppSpacing.lg)
                Spacer().frame(height: 10)
                widgetGrid
                    .padding(.horizontal, AppSpacing.lg)
            }
        }
    }

    // MARK: - Greeting text

    private var greetingTitle: Text {
        let base = Text(greetingKey)
        return displayName.isEmpty ? base : base + Text(verbatim: ", \(displayName)")
    }

    private var greetingKey: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    // MARK: - Health narrative

    /// The score's story in one sentence, from real data — numbers without a
    /// story are noise; the story makes you act.
    private var healthNarrative: String? {
        var factors: [String] = []
        let overdue = taskService.overdueCount
        if overdue > 0 {
            factors.append(String(format: String(localized: "%d overdue tasks"), overdue))
        }
        let expiring = documentService.expiringDocs.count
        if expiring > 0 {
            factors.append(String(format: String(localized: "%d documents expiring"), expiring))
        }
        let poorShape = elementService.elements.filter {
            $0.technicalCondition == .poor || $0.technicalCondition == .critical
        }.count
        if poorShape > 0 {
            factors.append(String(format: String(localized: "%d elements in poor shape"), poorShape))
        }
        guard !factors.isEmpty else { return nil }
        return String(format: String(localized: "Pulling the score down: %@."),
                      factors.prefix(2).joined(separator: " · "))
    }

    // MARK: - Today

    private var todayItems: [TodayItem] {
        TodayFeed.items(tasks: taskService.tasks,
                        plants: plantService.plants,
                        deliveries: deliveryService.deliveries,
                        members: familyService.members)
    }

    /// Pulsing badges for today's located tasks — the day happens ON the map.
    private var heroBadges: [UUID: Color] {
        var badges: [UUID: Color] = [:]
        for item in todayItems {
            guard let elId = item.elementId else { continue }
            if item.urgent { badges[elId] = Color.brandDanger }
            else if badges[elId] == nil { badges[elId] = Color.brandWarning }
        }
        return badges
    }

    private var todaySection: some View {
        let items = todayItems
        return VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            TodayCard(
                items: Array(items.prefix(3)),
                overflowCount: max(0, items.count - 3),
                onComplete: { complete($0) },
                onOpen: { open($0) },
                onOverflow: { activeSheet = .notifications }
            )
        }
    }

    private func complete(_ item: TodayItem) {
        Task {
            // Let the checkmark animate before the row leaves the list.
            try? await Task.sleep(for: .milliseconds(450))
            switch item.kind {
            case .task(let t):  await taskService.toggleComplete(t)
            case .plant(let p): await plantService.markWatered(p)
            default: break
            }
        }
    }

    private func open(_ item: TodayItem) {
        HapticFeedback.impact(.light)
        switch item.kind {
        case .task(let t):
            router.selectedTab = .tasks
            router.deepLinkTaskId = t.id
        case .plant:
            router.push(.plants)
        case .delivery:
            router.push(.deliveries)
        case .birthday:
            router.push(.family)
        }
    }
}

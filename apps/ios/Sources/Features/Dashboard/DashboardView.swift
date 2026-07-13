import SwiftUI
import MapKit
import CoreLocation

// MARK: - Dashboard — the smart-home-first home tab (reference fidelity)
//
// Top to bottom: header, room/scene chips, the now-playing media card, the
// staggered device hero grid (always populated), and the user-configurable
// widgets. The classic dashboard sections (aerial hero, Today, insights)
// moved off this page by explicit product decision — only widgets survive.

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
    // Feeds the hero grid's "Next up" card (warranty deadlines are part of
    // the house agenda).
    @Environment(ApplianceService.self) private var applianceService

    @State var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
    )
    @State var geocodedCoordinate: CLLocationCoordinate2D?
    @State var pulsing = false
    @State private var notificationService = NotificationService()
    // A single presentation slot. Multiple stacked `.sheet(isPresented:)` on one
    // view conflict in SwiftUI (only the last reliably presents), which is why
    // search / notifications / profile silently did nothing. One `.sheet(item:)`
    // driven by this enum fixes all of them.
    @State private var activeSheet: DashboardSheet?

    private enum DashboardSheet: Int, Identifiable {
        case notifications, editProfile, hub, widgetPicker
        var id: Int { rawValue }
    }
    @State var sectionOrder: [HomeSectionType] = HomeSectionType.load()

    var body: some View {
        ZStack {
            // The warm smart-home backdrop: the property's real cover photo
            // blurred under a warm overlay, or the bronze fallback. This
            // page is deliberately dark-warm by design (the sanctioned
            // exception to dual-mode), so the content renders in the dark
            // scheme regardless of the system setting.
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            scrollContent
                .environment(\.colorScheme, .dark)
        }
        .floatingSpeedDial(.home)
        .navigationBarHidden(true)
        .task(id: propertyService.primary?.id) {
            if let pid = propertyService.primary?.id {
                await zoneService.load(propertyId: pid)
            }
            // Feed the temperature dial from the property's stored
            // coordinates. The shared PropertyWeather cache is UserDefaults —
            // not observable — so a write landing after the first render
            // never re-rendered the dial; WeatherKitService IS observable but
            // only the weather widget used to populate it. Refresh the cache
            // AND mirror into the observable service so the dial updates the
            // moment a reading lands. Both paths no-op when fresh.
            if let lat = propertyService.primary?.latitude,
               let lon = propertyService.primary?.longitude {
                await PropertyWeather.refreshIfStale(latitude: lat, longitude: lon)
                if WeatherKitService.shared.currentWeather == nil {
                    await WeatherKitService.shared.fetch(
                        for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
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
            case .hub:
                // The home hub (search lives inside it, unchanged). The
                // explicit environments are what GlobalSearchSheet — now
                // nested one level deeper — always received here.
                SmartHomeHubSheet()
                    .environment(taskService)
                    .environment(documentService)
                    .environment(plantService)
                    .environment(deliveryService)
                    .environment(familyService)
                    .environment(financialService)
                    .environment(elementService)
                    .environment(zoneService)
                    .environment(router)
            case .widgetPicker:
                WidgetPickerSheet()
            }
        }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────
                dashHeader
                    .padding(.horizontal, AppSpacing.lg)

                Spacer().frame(height: 14)

                // ── Smart Home (S2.6): room/scene chips, the now-playing
                //    media card, and the always-populated hero grid ────────
                SmartHomeSection(nextAgendaItem: nextAgendaItem)
                    .padding(.horizontal, AppSpacing.lg)

                // ── Widgets — the classic dashboard's one survivor here ──
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
    }

    // MARK: - Header

    /// The reference's airy smart-home header: the hamburger-style menu
    /// glyph on the left (a REAL control — it opens the home hub: search,
    /// devices, cameras, rooms, pairing), the small date beside it, bell +
    /// avatar on the right, and the LARGE light-weight two-line greeting
    /// beneath.
    private var dashHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            HStack(alignment: .center, spacing: 10) {
                Button { HapticFeedback.impact(.light); activeSheet = .hub } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.smartTextPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel(Text("hub_title"))

                Text(dateString)
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.smartTextSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button { HapticFeedback.impact(.light); activeSheet = .notifications } label: {
                    Image(systemName: "bell.fill")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.smartTextPrimary)
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
                .accessibilityLabel(Text("Notifications"))
                .accessibilityValue(Text(verbatim: notificationService.unreadCount > 0
                                         ? "\(notificationService.unreadCount)" : ""))

                // The avatar goes straight to the Profile page itself — pushed,
                // so the dashboard stays underneath.
                Button {
                    HapticFeedback.impact(.light)
                    router.push(.profile)
                } label: {
                    avatarCircle
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Profile"))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                // Composed from Texts so both parts resolve through the
                // in-app locale — never the device language. LIGHT weight —
                // the reference greeting is thin and airy.
                greetingTitle
                    .font(AppFont.scaled(38, weight: .light))
                    .foregroundStyle(Color.smartTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("sh_greeting_subtitle")
                    .font(AppFont.scaled(15, weight: .regular))
                    .foregroundStyle(Color.smartTextSecondary)
            }
            .accessibilityElement(children: .combine)
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

    // MARK: - Widget section header

    /// The widgets strip's header, dressed in the smart-home language:
    /// warm-white uppercase label (the section headers' voice on this
    /// page), and the "+" as a warm glass circle like the header controls.
    private var widgetSectionHeader: some View {
        HStack {
            Text("OVERVIEW")
                .font(AppFont.label)
                .kerning(1.1)
                .foregroundStyle(Color.smartTextSecondary)
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
                    .foregroundStyle(Color.smartTextPrimary)
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
            // Retired from the home screen (only the widgets section
            // survived the smart-home redesign); health lives in the
            // Digital Twin tab, counters in the widgets themselves.
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

    // MARK: - Next agenda item (feeds the hero grid's "Next up" card)

    /// The house agenda's next upcoming entry — at/after now, within the
    /// next 30 days — built from the exact services the in-app calendar
    /// reads, skipping completed tasks. Timed items compare against the
    /// clock; day-precision items count from the start of today.
    private var nextAgendaItem: AgendaItem? {
        let cal = Calendar.current
        let now = Date()
        guard let end = cal.date(byAdding: .day, value: 30, to: now) else { return nil }
        let startOfToday = cal.startOfDay(for: now)
        return HouseAgenda.items(
            in: now...end,
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members,
            financial: financialService.records, plants: plantService.plants,
            leases: Array(familyService.leases.values))
            .first { !$0.isCompleted && $0.date >= ($0.hasTime ? now : startOfToday) }
    }
}

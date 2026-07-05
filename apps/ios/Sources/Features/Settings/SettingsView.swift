import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ProfileService.self) private var profileService
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(AppSettings.self) private var appSettings
    @Environment(NotificationScheduler.self) private var notificationScheduler
    @Environment(BudgetService.self) private var budgetService
    @Environment(FamilyService.self) private var familyService
    @Environment(MessageService.self) private var messageService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(SupplyService.self) private var supplyService
    @Environment(PlantService.self) private var plantService
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PropertyValueService.self) private var propertyValueService
    @Environment(AppRouter.self) private var router
    @State private var showSignOut = false
    @State private var showRateAlert = false
    @State private var showAccountSwitch = false
    @State private var showAddAccount = false

    var body: some View {
        @Bindable var router = router
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                profileCard
                switchCard
                propertySectionGated
                familySection
                appSection
                supportSection
                signOutButton
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { tabBarVis.scrollOffset = 0 }
        .confirmationDialog("Sign out of PRVIO?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Thanks for using PRVIO! 🏠", isPresented: $showRateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rating will be available once the app launches on the App Store.")
        }
        .navigationDestination(isPresented: $router.showSuppliesView) {
            SuppliesView()
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        NavigationLink(destination:
            ProfileView()
                .environment(profileService)
                .environment(notificationScheduler)
                .environment(taskService)
                .environment(documentService)
        ) {
            GlassCard {
                HStack(spacing: 14) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                        Text(auth.session?.user.email ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var switchCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                Menu {
                    ForEach(propertyService.properties) { p in
                        Button {
                            propertyService.select(p)
                        } label: {
                            Label(p.name, systemImage: propertyService.primary?.id == p.id ? "checkmark.circle.fill" : "house.fill")
                        }
                    }
                    if propertyService.properties.isEmpty {
                        Text("No properties yet")
                    }
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "house.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Property")
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            if let name = propertyService.primary?.name {
                                Text(name)
                                    .font(AppFont.footnote).foregroundStyle(.primary)
                                    .lineLimit(1)
                            } else {
                                Text("No property")
                                    .font(AppFont.footnote).foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)

                Button { showAccountSwitch = true } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "person.circle.fill", color: .purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Account")
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            Text(auth.session?.user.email ?? "—")
                                .font(AppFont.footnote).foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showAccountSwitch) {
            AccountSwitcherSheet(showAddAccount: $showAddAccount)
                .environment(auth)
        }
        .sheet(isPresented: $showAddAccount) {
            AddAccountSheet()
                .environment(auth)
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let urlStr = profileService.profile?.avatarUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    avatarGradient
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
        } else {
            avatarGradient
                .frame(width: 52, height: 52)
        }
    }

    private var avatarGradient: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initial)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Sections

    // MARK: - Role-based property matrix
    //
    // Single source of truth for which property tools each role sees. Owners,
    // partners (and the fail-open default) get everything; a family adult gets
    // everything except landlord-only tools; residents and service providers get
    // a curated subset; guests get nothing. Feature order = display order.
    private enum PropertyFeature: CaseIterable {
        case myProperty, documents, plans, finances, inventory, supplies, plants,
             deliveries, utilities, contractors, analytics, report, tenants,
             appliances, photoJournal, seasonal, paint, propertyValue, guestMode, perspectives
    }

    private func allowed(_ f: PropertyFeature) -> Bool {
        switch propertyService.myRole {
        case "guest":
            return false
        case "tenant":
            return [.documents, .supplies, .plants, .deliveries, .utilities,
                    .contractors, .appliances, .photoJournal, .seasonal, .paint].contains(f)
        case "family_child", "family_teen":
            return [.supplies, .plants, .deliveries, .photoJournal, .seasonal].contains(f)
        case "service_provider":
            return [.documents, .contractors, .deliveries, .appliances,
                    .seasonal, .photoJournal].contains(f)
        case "adult":
            // Family adult: everything except the landlord-only tools.
            return f != .tenants && f != .guestMode && f != .propertyValue
        default:
            return true   // owner, partner, nil (fail-open)
        }
    }

    private var visibleFeatures: [PropertyFeature] { PropertyFeature.allCases.filter(allowed) }

    // MARK: Thematic hubs — the flat 20-row list, grouped by mental model.
    // Role gating stays per-feature: a hub only shows the rows its role allows,
    // and disappears entirely when none remain.
    private enum PropertyHub: CaseIterable, Hashable {
        case home, upkeep, moneyDocs, daily

        var label: LocalizedStringKey {
            switch self {
            case .home:      return "My Home"
            case .upkeep:    return "Items & Maintenance"
            case .moneyDocs: return "Money & Documents"
            case .daily:     return "Everyday"
            }
        }
        var icon: String {
            switch self {
            case .home:      return "house.fill"
            case .upkeep:    return "wrench.and.screwdriver.fill"
            case .moneyDocs: return "banknote.fill"
            case .daily:     return "cart.fill"
            }
        }
        var color: Color {
            switch self {
            case .home:      return .blue
            case .upkeep:    return .teal
            case .moneyDocs: return Color.brandSuccess
            case .daily:     return Color.brandSkyBlue
            }
        }
        var features: [PropertyFeature] {
            switch self {
            case .home:      return [.myProperty, .plans, .photoJournal, .perspectives,
                                     .propertyValue, .analytics, .report]
            case .upkeep:    return [.inventory, .appliances, .paint, .contractors,
                                     .seasonal, .utilities]
            case .moneyDocs: return [.finances, .documents, .tenants]
            case .daily:     return [.supplies, .plants, .deliveries]
            }
        }
    }

    private func hubFeatures(_ hub: PropertyHub) -> [PropertyFeature] {
        hub.features.filter(allowed)
    }

    @ViewBuilder private var propertySectionGated: some View {
        if !visibleFeatures.isEmpty {
            VStack(spacing: 14) {
                frequentShortcuts
                SettingsGroup(title: "Property") {
                    ForEach(PropertyHub.allCases, id: \.self) { hub in
                        if !hubFeatures(hub).isEmpty {
                            NavSettingsRow(icon: hub.icon, color: hub.color, label: hub.label) {
                                hubPage(hub)
                            }
                        }
                    }
                }
            }
        }
    }

    /// One-tap tiles for the pages used daily, so the hubs never add a hop
    /// to the routine.
    @ViewBuilder private var frequentShortcuts: some View {
        let shortcuts: [PropertyFeature] = [.documents, .finances, .inventory].filter(allowed)
        if !shortcuts.isEmpty {
            HStack(spacing: AppSpacing.sm) {
                ForEach(shortcuts, id: \.self) { f in
                    NavigationLink { propertyDestination(f) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: shortcutIcon(f))
                                .font(AppFont.subheadline)
                                .foregroundStyle(shortcutColor(f))
                            Text(shortcutLabel(f))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .liquidGlass(cornerRadius: AppRadius.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shortcutIcon(_ f: PropertyFeature) -> String {
        switch f {
        case .documents: return "doc.text.fill"
        case .finances:  return "banknote.fill"
        default:         return "shippingbox.fill"
        }
    }
    private func shortcutColor(_ f: PropertyFeature) -> Color {
        switch f {
        case .documents: return .orange
        case .finances:  return Color.brandSuccess
        default:         return .indigo
        }
    }
    private func shortcutLabel(_ f: PropertyFeature) -> LocalizedStringKey {
        switch f {
        case .documents: return "Documents"
        case .finances:  return "Finances"
        default:         return "Inventory"
        }
    }

    /// Destinations for the frequent-shortcut tiles (same views the hub rows
    /// push, including their section locks).
    @ViewBuilder private func propertyDestination(_ f: PropertyFeature) -> some View {
        switch f {
        case .documents:
            DocumentsView().environment(documentService).environment(propertyService)
                .sectionLock(.documents)
        case .finances:
            FinancesView().environment(financialService).environment(propertyService).environment(budgetService)
                .sectionLock(.finances)
        default:
            InventoryView()
                .sectionLock(.inventory)
        }
    }

    private func hubPage(_ hub: PropertyHub) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                SettingsGroup(title: hub.label) {
                    ForEach(hubFeatures(hub), id: \.self) { propertyRow($0) }
                }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text(hub.label))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func propertyRow(_ f: PropertyFeature) -> some View {
        switch f {
        case .myProperty:
            NavSettingsRow(icon: "house.fill", color: .blue, label: "My Property") {
                PropertySettingsView().environment(propertyService)
            }
        case .documents:
            NavSettingsRow(icon: "doc.text.fill", color: .orange, label: "Documents") {
                DocumentsView().environment(documentService).environment(propertyService)
                    .sectionLock(.documents)
            }
        case .plans:
            NavSettingsRow(icon: "cube.transparent.fill", color: .purple, label: "Plans & 3D") {
                BlueprintsView()
                    .sectionLock(.plans)
            }
        case .finances:
            NavSettingsRow(icon: "banknote.fill", color: Color.brandSuccess, label: "Finances") {
                FinancesView().environment(financialService).environment(propertyService).environment(budgetService)
                    .sectionLock(.finances)
            }
        case .inventory:
            NavSettingsRow(icon: "shippingbox.fill", color: .indigo, label: "Inventory") {
                InventoryView()
                    .sectionLock(.inventory)
            }
        case .supplies:
            NavSettingsRow(icon: "cart.fill", color: Color.brandSkyBlue, label: "Supplies") {
                SuppliesView().environment(supplyService).environment(propertyService)
            }
        case .plants:
            NavSettingsRow(icon: "leaf.fill", color: Color(red: 0.15, green: 0.80, blue: 0.40), label: "Plants") {
                PlantsView().environment(plantService).environment(propertyService)
            }
        case .deliveries:
            NavSettingsRow(icon: "shippingbox.fill", color: .orange, label: "Deliveries") {
                DeliveriesView().environment(deliveryService)
            }
        case .utilities:
            NavSettingsRow(icon: "bolt.fill", color: .yellow, label: "Utilities") {
                UtilityView()
            }
        case .contractors:
            NavSettingsRow(icon: "wrench.and.screwdriver.fill", color: .teal, label: "Contractors") {
                ContractorsView().environment(auth)
            }
        case .analytics:
            NavSettingsRow(icon: "chart.bar.xaxis", color: .purple, label: "Analytics") {
                AnalyticsView()
            }
        case .report:
            NavSettingsRow(icon: "doc.richtext.fill", color: .pink, label: "Property Report") {
                PropertyReportView().environment(taskService).environment(financialService).environment(documentService).environment(propertyService)
            }
        case .tenants:
            NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Tenants") {
                TenantManagementView().environment(familyService).environment(propertyService)
            }
        case .appliances:
            NavSettingsRow(icon: "washer.fill", color: Color.brandPrimaryBlue, label: "Appliances") {
                AppliancesView().environment(applianceService).environment(propertyService)
            }
        case .photoJournal:
            NavSettingsRow(icon: "camera.fill", color: Color(red: 0.85, green: 0.35, blue: 0.6), label: "Photo Journal") {
                PhotoJournalView().environment(photoJournalService).environment(propertyService)
            }
        case .seasonal:
            NavSettingsRow(icon: "calendar.badge.checkmark", color: Color(red: 0.25, green: 0.75, blue: 0.45), label: "Seasonal Checklists") {
                SeasonalChecklistView()
            }
        case .paint:
            NavSettingsRow(icon: "paintpalette.fill", color: Color.brandWarning, label: "Paint Colors") {
                PaintColorsView().environment(paintColorService).environment(propertyService)
            }
        case .propertyValue:
            NavSettingsRow(icon: "chart.line.uptrend.xyaxis", color: Color(red: 0.35, green: 0.75, blue: 0.55), label: "Property Value") {
                PropertyValueView().environment(propertyValueService).environment(propertyService).environment(currencyService).environment(appSettings)
            }
        case .guestMode:
            NavSettingsRow(icon: "square.and.arrow.up.fill", color: .teal, label: "Guest Mode") {
                GuestModeView().environment(propertyService).environment(familyService)
            }
        case .perspectives:
            NavSettingsRow(icon: "square.3.layers.3d.fill", color: Color.brandSkyBlue, label: "Perspectives") {
                PropertyPerspectivesView().environment(propertyService).environment(taskService).environment(documentService).environment(financialService).environment(familyService).environment(applianceService).environment(router)
            }
        }
    }

    // Only owners/partners (or the fail-open default) manage the household roster.
    private var canManageMembers: Bool {
        switch propertyService.myRole {
        case nil, "owner", "partner", "adult": return true
        default: return false
        }
    }

    private var familySection: some View {
        SettingsGroup(title: "People & Access") {
            if canManageMembers {
                NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Members") {
                    MembersHubView()
                        .environment(familyService)
                        .environment(propertyService)
                }
            }
            if allowed(.guestMode) {
                NavSettingsRow(icon: "square.and.arrow.up.fill", color: .teal, label: "Guest Mode") {
                    GuestModeView().environment(propertyService).environment(familyService)
                }
            }
            NavSettingsRow(icon: "bubble.left.and.bubble.right.fill", color: .blue, label: "Chat") {
                Group {
                    if propertyService.primary?.id != nil {
                        ChatSettingsView()
                            .environment(propertyService)
                            .environment(familyService)
                            .environment(profileService)
                            .environment(messageService)
                    } else {
                        SettingsPlaceholder(icon: "bubble.left.and.bubble.right.fill", title: "Chat", description: "Adaugă o proprietate pentru a putea trimite mesaje.")
                    }
                }
            }
            // Cross-app messaging lives inside the Chat settings page — no need
            // for a duplicate row here.
        }
    }

    // MARK: - Role-based App-section gating
    //
    // Some App-section rows configure the property "power" features (access
    // keys, third-party integrations, action shortcuts) and shouldn't appear for
    // low-privilege roles. The purely-personal rows (Appearance, Language,
    // Activity, App Icon, Live Activities, Siri) stay visible to everyone.
    private enum AppFeature { case liveActivities, floatingButtons, nfcKeys, integrations }

    private func allowedApp(_ f: AppFeature) -> Bool {
        switch propertyService.myRole {
        case "guest", "family_child", "family_teen":
            return false                       // no property power tools
        case "tenant":
            // A resident tracks their own activities, configures shortcuts and
            // may hold an access key, but doesn't wire up account integrations.
            return f == .liveActivities || f == .floatingButtons || f == .nfcKeys
        case "service_provider":
            return f == .liveActivities || f == .floatingButtons
        default:
            return true                        // owner, partner, adult, nil (fail-open)
        }
    }

    private var appSection: some View {
        VStack(spacing: 14) {
            SettingsGroup(title: "Personalization") {
                NavSettingsRow(icon: "paintbrush.fill", color: .pink, label: "Appearance") {
                    AppearanceView()
                        .environment(appSettings)
                        .environment(auth)
                        .environment(currencyService)
                }
                NavSettingsRow(icon: "globe", color: .blue, label: "Language") {
                    LanguageSettingsView()
                        .environment(appSettings)
                }
                NavSettingsRow(icon: "app.fill", color: .purple, label: "App Icon") {
                    AppIconPickerView()
                }
                if allowedApp(.liveActivities) {
                    NavSettingsRow(icon: "bolt.badge.clock.fill", color: .blue, label: "Live Activities") {
                        LiveActivitySettingsView()
                    }
                }
                if allowedApp(.floatingButtons) {
                    NavSettingsRow(icon: "plus.circle.fill", color: .orange, label: "Floating Buttons") {
                        QuickActionsSettingsView()
                            .environment(appSettings)
                    }
                }
            }

            SettingsGroup(title: "Automation & Connections") {
                NavSettingsRow(icon: "mic.fill", color: Color.brandPurple, label: "Siri & Shortcuts") {
                    SiriShortcutsView()
                }
                if allowedApp(.nfcKeys) {
                    NavSettingsRow(icon: "wave.3.right.circle.fill", color: Color(red: 0.15, green: 0.65, blue: 0.85), label: "NFC Keys") {
                        NFCWalletView()
                    }
                }
                if allowedApp(.integrations) {
                    NavSettingsRow(icon: "puzzlepiece.fill", color: .yellow, label: "Integrations") {
                        IntegrationsView()
                            .environment(taskService)
                            .environment(propertyService)
                            .environment(familyService)
                    }
                }
            }
        }
    }

    private var supportSection: some View {
        SettingsGroup(title: "Support") {
            NavSettingsRow(icon: "clock.arrow.circlepath", color: .teal, label: "Activity") {
                ActivityFeedView()
                    .environment(financialService)
                    .environment(documentService)
                    .environment(familyService)
                    .environment(appSettings)
                    .environment(taskService)
                    .environment(applianceService)
                    .environment(plantService)
            }
            NavSettingsRow(icon: "phone.fill", color: .red, label: "Emergency Contacts") {
                EmergencyContactsView()
            }
            NavSettingsRow(icon: "questionmark.circle.fill", color: .cyan, label: "Help & FAQ") {
                HelpFAQView()
            }
            TapSettingsRow(icon: "star.fill", color: .yellow, label: "Rate App") {
                showRateAlert = true
            }
            InfoSettingsRow(icon: "info.circle.fill", color: .gray, label: "Version", value: appVersion)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button { showSignOut = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(AppFont.body)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.red.opacity(0.22), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        profileService.profile?.preferredName
            ?? auth.session?.user.email?.components(separatedBy: "@").first?.capitalized
            ?? "User"
    }
    private var initial: String { String(displayName.prefix(1)).uppercased() }
}

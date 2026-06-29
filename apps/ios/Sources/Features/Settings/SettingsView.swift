import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var notificationScheduler: NotificationScheduler
    @EnvironmentObject private var budgetService: BudgetService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var deliveryService: DeliveryService
    @EnvironmentObject private var applianceService: ApplianceService
    @EnvironmentObject private var photoJournalService: PhotoJournalService
    @EnvironmentObject private var paintColorService: PaintColorService
    @EnvironmentObject private var propertyValueService: PropertyValueService
    @EnvironmentObject private var router: AppRouter
    @State private var showSignOut = false
    @State private var showRateAlert = false
    @State private var showAccountSwitch = false
    @State private var showAddAccount = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                profileCard
                switchCard
                propertySection
                familySection
                appSection
                supportSection
                signOutButton
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
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
                .environmentObject(profileService)
                .environmentObject(notificationScheduler)
                .environmentObject(taskService)
                .environmentObject(documentService)
        ) {
            GlassCard {
                HStack(spacing: 14) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(auth.session?.user.email ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.5))
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
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                            if let name = propertyService.primary?.name {
                                Text(name)
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                    .lineLimit(1)
                            } else {
                                Text("No property")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)

                Button { showAccountSwitch = true } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "person.circle.fill", color: .purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Account")
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                            Text(auth.session?.user.email ?? "—")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showAccountSwitch) {
            AccountSwitcherSheet(showAddAccount: $showAddAccount)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showAddAccount) {
            AddAccountSheet()
                .environmentObject(auth)
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

    private var propertySection: some View {
        SettingsGroup(title: "Property") {
            NavSettingsRow(icon: "house.fill", color: .blue, label: "My Property") {
                PropertySettingsView()
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "doc.text.fill", color: .orange, label: "Documents") {
                DocumentsView()
                    .environmentObject(documentService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "cube.transparent.fill", color: .purple, label: "Plans & 3D") {
                BlueprintsView()
            }
            NavSettingsRow(icon: "banknote.fill", color: Color(red: 0.3, green: 0.85, blue: 0.5), label: "Finances") {
                FinancesView()
                    .environmentObject(financialService)
                    .environmentObject(propertyService)
                    .environmentObject(budgetService)
            }
            NavSettingsRow(icon: "shippingbox.fill", color: .indigo, label: "Inventory") {
                InventoryView()
            }
            NavSettingsRow(icon: "cart.fill", color: Color(red: 0.35, green: 0.65, blue: 1.0), label: "Supplies") {
                SuppliesView()
                    .environmentObject(supplyService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "leaf.fill", color: Color(red: 0.15, green: 0.80, blue: 0.40), label: "Plants") {
                PlantsView()
                    .environmentObject(plantService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "shippingbox.fill", color: .orange, label: "Deliveries") {
                DeliveriesView()
                    .environmentObject(deliveryService)
            }
            NavSettingsRow(icon: "bolt.fill", color: .yellow, label: "Utilities") {
                UtilityView()
            }
            NavSettingsRow(icon: "wrench.and.screwdriver.fill", color: .teal, label: "Contractors") {
                ContractorsView()
                    .environmentObject(auth)
            }
            NavSettingsRow(icon: "chart.bar.xaxis", color: .purple, label: "Analytics") {
                AnalyticsView()
            }
            NavSettingsRow(icon: "doc.richtext.fill", color: .pink, label: "Property Report") {
                PropertyReportView()
                    .environmentObject(taskService)
                    .environmentObject(financialService)
                    .environmentObject(documentService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Tenants") {
                TenantManagementView()
                    .environmentObject(familyService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "washer.fill", color: Color(red: 0.2, green: 0.55, blue: 0.95), label: "Appliances") {
                AppliancesView()
                    .environmentObject(applianceService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "camera.fill", color: Color(red: 0.85, green: 0.35, blue: 0.6), label: "Photo Journal") {
                PhotoJournalView()
                    .environmentObject(photoJournalService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "calendar.badge.checkmark", color: Color(red: 0.25, green: 0.75, blue: 0.45), label: "Seasonal Checklists") {
                SeasonalChecklistView()
            }
            NavSettingsRow(icon: "paintpalette.fill", color: Color(red: 0.95, green: 0.45, blue: 0.15), label: "Paint Colors") {
                PaintColorsView()
                    .environmentObject(paintColorService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "chart.line.uptrend.xyaxis", color: Color(red: 0.35, green: 0.75, blue: 0.55), label: "Property Value") {
                PropertyValueView()
                    .environmentObject(propertyValueService)
                    .environmentObject(propertyService)
                    .environmentObject(currencyService)
                    .environmentObject(appSettings)
            }
            NavSettingsRow(icon: "square.and.arrow.up.fill", color: .teal, label: "Guest Mode") {
                GuestModeView()
                    .environmentObject(propertyService)
                    .environmentObject(familyService)
            }
            NavSettingsRow(icon: "square.3.layers.3d.fill", color: Color(red: 0.35, green: 0.55, blue: 1.0), label: "Perspectives") {
                PropertyPerspectivesView()
                    .environmentObject(propertyService)
                    .environmentObject(taskService)
                    .environmentObject(documentService)
                    .environmentObject(financialService)
                    .environmentObject(familyService)
                    .environmentObject(applianceService)
                    .environmentObject(router)
            }
        }
    }

    private var familySection: some View {
        SettingsGroup(title: "Family & Chat") {
            NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Family Members") {
                FamilyView()
                    .environmentObject(familyService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "eyes", color: Color(red: 0.35, green: 0.2, blue: 0.85), label: "Supervision") {
                SupervisionView()
                    .environmentObject(familyService)
            }
            NavSettingsRow(icon: "bubble.left.and.bubble.right.fill", color: .blue, label: "Chat") {
                Group {
                    if propertyService.primary?.id != nil {
                        ConversationsView()
                    } else {
                        SettingsPlaceholder(icon: "bubble.left.and.bubble.right.fill", title: "Chat", description: "Adaugă o proprietate pentru a putea trimite mesaje.")
                    }
                }
            }
        }
    }

    private var appSection: some View {
        SettingsGroup(title: "App") {
            NavSettingsRow(icon: "paintbrush.fill", color: .pink, label: "Appearance") {
                AppearanceView()
                    .environmentObject(appSettings)
                    .environmentObject(auth)
                    .environmentObject(currencyService)
            }
            NavSettingsRow(icon: "globe", color: .blue, label: "Language") {
                LanguageSettingsView()
                    .environmentObject(appSettings)
            }
            NavSettingsRow(icon: "clock.arrow.circlepath", color: .teal, label: "Activity") {
                ActivityFeedView()
                    .environmentObject(financialService)
                    .environmentObject(documentService)
                    .environmentObject(familyService)
                    .environmentObject(appSettings)
                    .environmentObject(taskService)
                    .environmentObject(applianceService)
                    .environmentObject(plantService)
            }
            NavSettingsRow(icon: "app.fill", color: .purple, label: "App Icon") {
                AppIconPickerView()
            }
            NavSettingsRow(icon: "bolt.badge.clock.fill", color: .blue, label: "Live Activities") {
                LiveActivitySettingsView()
            }
            NavSettingsRow(icon: "plus.circle.fill", color: .orange, label: "Floating Buttons") {
                QuickActionsSettingsView()
                    .environmentObject(appSettings)
            }
            NavSettingsRow(icon: "mic.fill", color: Color(red: 0.55, green: 0.35, blue: 0.95), label: "Siri & Shortcuts") {
                SiriShortcutsView()
            }
            NavSettingsRow(icon: "wave.3.right.circle.fill", color: Color(red: 0.15, green: 0.65, blue: 0.85), label: "NFC Keys") {
                NFCWalletView()
            }
            NavSettingsRow(icon: "puzzlepiece.fill", color: .yellow, label: "Integrations") {
                IntegrationsView()
                    .environmentObject(taskService)
                    .environmentObject(propertyService)
                    .environmentObject(familyService)
            }
        }
    }

    private var supportSection: some View {
        SettingsGroup(title: "Support") {
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
            .font(.system(size: 15, weight: .medium))
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

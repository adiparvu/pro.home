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
                propertySection
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

    private var propertySection: some View {
        SettingsGroup(title: "Property") {
            NavSettingsRow(icon: "house.fill", color: .blue, label: "My Property") {
                PropertySettingsView()
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "doc.text.fill", color: .orange, label: "Documents") {
                DocumentsView()
                    .environment(documentService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "cube.transparent.fill", color: .purple, label: "Plans & 3D") {
                BlueprintsView()
            }
            NavSettingsRow(icon: "banknote.fill", color: Color.brandSuccess, label: "Finances") {
                FinancesView()
                    .environment(financialService)
                    .environment(propertyService)
                    .environment(budgetService)
            }
            NavSettingsRow(icon: "shippingbox.fill", color: .indigo, label: "Inventory") {
                InventoryView()
            }
            NavSettingsRow(icon: "cart.fill", color: Color.brandSkyBlue, label: "Supplies") {
                SuppliesView()
                    .environment(supplyService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "leaf.fill", color: Color(red: 0.15, green: 0.80, blue: 0.40), label: "Plants") {
                PlantsView()
                    .environment(plantService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "shippingbox.fill", color: .orange, label: "Deliveries") {
                DeliveriesView()
                    .environment(deliveryService)
            }
            NavSettingsRow(icon: "bolt.fill", color: .yellow, label: "Utilities") {
                UtilityView()
            }
            NavSettingsRow(icon: "wrench.and.screwdriver.fill", color: .teal, label: "Contractors") {
                ContractorsView()
                    .environment(auth)
            }
            NavSettingsRow(icon: "chart.bar.xaxis", color: .purple, label: "Analytics") {
                AnalyticsView()
            }
            NavSettingsRow(icon: "doc.richtext.fill", color: .pink, label: "Property Report") {
                PropertyReportView()
                    .environment(taskService)
                    .environment(financialService)
                    .environment(documentService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Tenants") {
                TenantManagementView()
                    .environment(familyService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "washer.fill", color: Color.brandPrimaryBlue, label: "Appliances") {
                AppliancesView()
                    .environment(applianceService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "camera.fill", color: Color(red: 0.85, green: 0.35, blue: 0.6), label: "Photo Journal") {
                PhotoJournalView()
                    .environment(photoJournalService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "calendar.badge.checkmark", color: Color(red: 0.25, green: 0.75, blue: 0.45), label: "Seasonal Checklists") {
                SeasonalChecklistView()
            }
            NavSettingsRow(icon: "paintpalette.fill", color: Color.brandWarning, label: "Paint Colors") {
                PaintColorsView()
                    .environment(paintColorService)
                    .environment(propertyService)
            }
            NavSettingsRow(icon: "chart.line.uptrend.xyaxis", color: Color(red: 0.35, green: 0.75, blue: 0.55), label: "Property Value") {
                PropertyValueView()
                    .environment(propertyValueService)
                    .environment(propertyService)
                    .environment(currencyService)
                    .environment(appSettings)
            }
            NavSettingsRow(icon: "square.and.arrow.up.fill", color: .teal, label: "Guest Mode") {
                GuestModeView()
                    .environment(propertyService)
                    .environment(familyService)
            }
            NavSettingsRow(icon: "square.3.layers.3d.fill", color: Color.brandSkyBlue, label: "Perspectives") {
                PropertyPerspectivesView()
                    .environment(propertyService)
                    .environment(taskService)
                    .environment(documentService)
                    .environment(financialService)
                    .environment(familyService)
                    .environment(applianceService)
                    .environment(router)
            }
        }
    }

    private var familySection: some View {
        SettingsGroup(title: "Family & Chat") {
            NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Members") {
                MembersHubView()
                    .environment(familyService)
                    .environment(propertyService)
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
            NavSettingsRow(icon: "arrow.left.arrow.right.circle.fill", color: .green, label: "Cross-app messaging") {
                InterAppChatView()
            }
        }
    }

    private var appSection: some View {
        SettingsGroup(title: "App") {
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
            NavSettingsRow(icon: "app.fill", color: .purple, label: "App Icon") {
                AppIconPickerView()
            }
            NavSettingsRow(icon: "bolt.badge.clock.fill", color: .blue, label: "Live Activities") {
                LiveActivitySettingsView()
            }
            NavSettingsRow(icon: "plus.circle.fill", color: .orange, label: "Floating Buttons") {
                QuickActionsSettingsView()
                    .environment(appSettings)
            }
            NavSettingsRow(icon: "mic.fill", color: Color.brandPurple, label: "Siri & Shortcuts") {
                SiriShortcutsView()
            }
            NavSettingsRow(icon: "wave.3.right.circle.fill", color: Color(red: 0.15, green: 0.65, blue: 0.85), label: "NFC Keys") {
                NFCWalletView()
            }
            NavSettingsRow(icon: "puzzlepiece.fill", color: .yellow, label: "Integrations") {
                IntegrationsView()
                    .environment(taskService)
                    .environment(propertyService)
                    .environment(familyService)
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

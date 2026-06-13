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
    @State private var showSignOut = false
    @State private var showRateAlert = false
    @State private var showAccountSwitch = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                profileCard
                switchCard
                propertySection
                familySection
                notificationsSection
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
                            Text("Proprietate")
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                            Text(propertyService.primary?.name ?? "Nicio proprietate")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                .lineLimit(1)
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
                            Text("Cont")
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
        .confirmationDialog("Schimbă contul", isPresented: $showAccountSwitch, titleVisibility: .visible) {
            Button("Deconectare", role: .destructive) { showSignOut = true }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Pentru a schimba contul, deconectează-te și autentifică-te cu alt cont.")
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
            NavSettingsRow(icon: "bolt.fill", color: .yellow, label: "Utilities") {
                UtilityView()
            }
            NavSettingsRow(icon: "wrench.and.screwdriver.fill", color: .teal, label: "Contractors") {
                ContractorsView()
                    .environmentObject(auth)
            }
            NavSettingsRow(icon: "doc.richtext.fill", color: .pink, label: "Property Report") {
                PropertyReportView()
                    .environmentObject(taskService)
                    .environmentObject(financialService)
                    .environmentObject(documentService)
                    .environmentObject(propertyService)
            }
            NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Tenants") {
                SettingsPlaceholder(icon: "person.2.fill", title: "Tenants", description: "Manage tenant profiles, leases, and communications.")
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
            NavSettingsRow(icon: "bubble.left.and.bubble.right.fill", color: .blue, label: "Family Chat") {
                Group {
                    if let propId = propertyService.primary?.id {
                        ChatView()
                            .environmentObject(familyService)
                            .environmentObject(messageService)
                    } else {
                        SettingsPlaceholder(icon: "bubble.left.and.bubble.right.fill", title: "Family Chat", description: "Add a property first to start chatting.")
                    }
                }
            }
        }
    }

    private var notificationsSection: some View {
        SettingsGroup(title: "Notifications") {
            NavSettingsRow(icon: "bell.fill", color: .red, label: "Notification Preferences") {
                NotificationsSettingsView()
                    .environmentObject(notificationScheduler)
                    .environmentObject(taskService)
                    .environmentObject(documentService)
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
            NavSettingsRow(icon: "puzzlepiece.fill", color: .yellow, label: "Integrations") {
                IntegrationsView()
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

// MARK: - Settings Group (iOS 26/27 liquid glass)

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.38))
                .padding(.leading, 8)

            VStack(spacing: 0) { content }
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [.white.opacity(0.14), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(LinearGradient(
                                    colors: [.white.opacity(0.32), .white.opacity(0.06)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ), lineWidth: 0.7)
                        }
                }
                .shadow(color: .black.opacity(0.10), radius: 18, y: 4)
        }
    }
}

// MARK: - Row Variants

struct NavSettingsRow<D: View>: View {
    let icon: String
    let color: Color
    let label: String
    @ViewBuilder let destination: () -> D

    var body: some View {
        NavigationLink(destination: destination()) {
            rowInner(chevron: true)
        }
        .buttonStyle(.plain)
        rowDivider
    }

    private func rowInner(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.4)
            .padding(.leading, 52)
    }
}

struct TapSettingsRow: View {
    let icon: String
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon, color: color)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

struct ToggleSettingsRow: View {
    let icon: String
    let color: Color
    let label: String
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $value)
                .labelsHidden()
                .tint(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

struct InfoSettingsRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.38))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Colored Icon Badge (iOS 26/27 squircle gradient)

struct ColoredIconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.45), radius: 4, y: 2)
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Settings Placeholder

struct SettingsPlaceholder: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Coming soon")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.07), in: Capsule())
            Spacer()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

// MARK: - General settings
//
// One home for the app's cross-cutting settings — the pages that aren't about
// a single property feature: Members, look-and-feel (Appearance, Language,
// Apple Watch, Live Activities, Floating Buttons) and automation/connections
// (Siri, NFC keys, Integrations). Settings' top level shows a single "General"
// row into here, so the root list stays short. Role gating mirrors SettingsView
// exactly, so nothing a role couldn't see before becomes reachable here.

struct GeneralSettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(FamilyService.self) private var familyService
    @Environment(CurrencyService.self) private var currencyService

    // MARK: Role gating (same rules as SettingsView)

    private var canManageMembers: Bool {
        guard let role = propertyService.role else { return true }   // still loading
        return role.canManageMembers
    }

    private enum AppFeature { case liveActivities, floatingButtons, nfcKeys, integrations }

    private func allowedApp(_ f: AppFeature) -> Bool {
        guard let role = propertyService.role else { return true }   // still loading
        switch role {
        case .guest, .familyChild, .familyTeen:
            return false                       // no property power tools
        case .tenant:
            return f == .liveActivities || f == .floatingButtons || f == .nfcKeys
        case .serviceProvider:
            return f == .liveActivities || f == .floatingButtons
        case .owner, .partner, .familyAdult, .familyElderly:
            return true
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if canManageMembers {
                    SettingsGroup(title: "People & Access") {
                        NavSettingsRow(icon: "person.2.fill", color: .purple, label: "Members") {
                            MembersHubView()
                                .environment(familyService)
                                .environment(propertyService)
                        }
                    }
                }

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
                    NavSettingsRow(icon: "applewatch", color: .teal, label: "Apple Watch") {
                        WatchSettingsView()
                    }
                    if allowedApp(.liveActivities) {
                        NavSettingsRow(icon: "bolt.badge.clock.fill", color: .blue, label: "Live Activities") {
                            LiveActivitiesHubView()
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
                        NavSettingsRow(icon: "wave.3.right.circle.fill",
                                       color: Color(red: 0.15, green: 0.65, blue: 0.85), label: "NFC Keys") {
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

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.large)
    }
}

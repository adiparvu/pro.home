import SwiftUI

final class TabBarVisibility: ObservableObject {
    @Published var isHidden = false
    @Published var scrolledDown = false
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum AppTab: String, CaseIterable {
    case home, map, tasks, analytics, assistant, settings

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .map:       return "map.fill"
        case .tasks:     return "checklist"
        case .analytics: return "chart.bar.xaxis"
        case .assistant: return "sparkles"
        case .settings:  return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home:      return "Home"
        case .map:       return "Hartă"
        case .tasks:     return "Tasks"
        case .analytics: return "Analytics"
        case .assistant: return "Assistant"
        case .settings:  return "Settings"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var taskService = TaskService()
    @StateObject private var propertyService = PropertyService()
    @StateObject private var profileService = ProfileService()
    @StateObject private var financialService = FinancialService()
    @StateObject private var documentService = DocumentService()
    @StateObject private var notificationScheduler = NotificationScheduler()
    @StateObject private var budgetService = BudgetService()
    @StateObject private var familyService = FamilyService()
    @StateObject private var messageService = MessageService()
    @StateObject private var currencyService = CurrencyService()
    @StateObject private var elementService = PropertyElementService()
    @StateObject private var tabBarVis = TabBarVisibility()
    @StateObject private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { DashboardView() }
                .tabItem { Label(AppTab.home.label, systemImage: AppTab.home.icon) }
                .tag(AppTab.home)

            NavigationStack { PropertyMapView() }
                .tabItem { Label(AppTab.map.label, systemImage: AppTab.map.icon) }
                .tag(AppTab.map)

            NavigationStack { TasksView() }
                .tabItem { Label(AppTab.tasks.label, systemImage: AppTab.tasks.icon) }
                .badge(taskService.overdueCount)
                .tag(AppTab.tasks)

            NavigationStack { AnalyticsView() }
                .tabItem { Label(AppTab.analytics.label, systemImage: AppTab.analytics.icon) }
                .tag(AppTab.analytics)

            NavigationStack { SettingsView() }
                .tabItem { Label(AppTab.settings.label, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: $router.showARIA) {
            NavigationStack {
                ARIAView(onDismiss: { router.showARIA = false })
                    .environmentObject(propertyService)
                    .environmentObject(familyService)
                    .environmentObject(profileService)
            }
        }
        .sheet(isPresented: $router.showAddTask) { AddTaskView() }
        .sheet(isPresented: $router.showChat) { NavigationStack { ChatView() } }
        .sheet(isPresented: $router.showAddExpense) { AddFinancialView { await financialService.load() } }
        .sheet(isPresented: $router.showInventoryScan) { NavigationStack { InventoryView(autoScan: true) } }
        .sheet(isPresented: $router.showInventoryAdd) { NavigationStack { InventoryView(autoAdd: true) } }
        .environmentObject(router)
        .environmentObject(tabBarVis)
        .environmentObject(taskService)
        .environmentObject(propertyService)
        .environmentObject(profileService)
        .environmentObject(financialService)
        .environmentObject(documentService)
        .environmentObject(notificationScheduler)
        .environmentObject(budgetService)
        .environmentObject(familyService)
        .environmentObject(messageService)
        .environmentObject(currencyService)
        .environmentObject(elementService)
        .task {
            await currencyService.refresh()
            await propertyService.load()
            await taskService.load()
            await financialService.load()
            await documentService.load()
            await familyService.load()
            if let uid = auth.session?.user.id {
                await profileService.load(userId: uid)
                if let profile = profileService.profile {
                    appSettings.loadFromProfile(profile)
                }
            }
            await notificationScheduler.reschedule(
                tasks: taskService.tasks,
                documents: documentService.documents
            )
            if let propId = propertyService.primary?.id {
                await messageService.load(propertyId: propId)
            }
        }
        .onChange(of: profileService.profile) { _, profile in
            if let profile, let s = auth.session {
                AccountsStore.shared.save(
                    session: s,
                    displayName: profile.preferredName,
                    avatarUrl: profile.avatarUrl
                )
            }
        }
        .onChange(of: auth.session?.user.id) { oldId, newId in
            guard let newId, newId != oldId else { return }
            Task {
                await propertyService.load()
                await taskService.load()
                await financialService.load()
                await documentService.load()
                await familyService.load()
                await profileService.load(userId: newId)
                if let profile = profileService.profile {
                    appSettings.loadFromProfile(profile)
                }
                if let propId = propertyService.primary?.id {
                    await messageService.load(propertyId: propId)
                }
            }
        }
        .onChange(of: router.selectedTab) { _, _ in
            if tabBarVis.scrolledDown { tabBarVis.scrolledDown = false }
        }
    }

}

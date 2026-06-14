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
    case home, map, tasks, analytics, settings

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .map:       return "map.fill"
        case .tasks:     return "checklist"
        case .analytics: return "chart.bar.xaxis"
        case .settings:  return "person.crop.circle.fill"
        }
    }
}

// MARK: - Custom animated tab bar

private struct AnimatedTabBar: View {
    @Binding var selected: AppTab
    @Binding var bounceTab: AppTab?
    let overdueCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    HapticFeedback.selection()
                    bounceTab = tab
                    selected = tab
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22, weight: tab == selected ? .semibold : .regular))
                            .symbolEffect(.bounce, value: bounceTab == tab)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(tab == selected ? Color.primary : Color.primary.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .contentTransition(.symbolEffect(.replace))

                        if tab == .tasks && overdueCount > 0 {
                            Text(overdueCount < 10 ? "\(overdueCount)" : "9+")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                                .offset(x: 4, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

// MARK: - Main tab view

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
    @StateObject private var zoneService = PropertyZoneService()
    @StateObject private var supplyService = SupplyService()
    @StateObject private var stickerService = StickerService()
    @StateObject private var plantService = PlantService()
    @StateObject private var deliveryService = DeliveryService()
    @StateObject private var tabBarVis = TabBarVisibility()
    @EnvironmentObject private var router: AppRouter

    @State private var bounceTab: AppTab? = nil

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { DashboardView() }
                .tabItem { Image(systemName: AppTab.home.icon) }
                .tag(AppTab.home)

            NavigationStack { DigitalTwinView() }
                .tabItem { Image(systemName: AppTab.map.icon) }
                .tag(AppTab.map)

            NavigationStack { TasksView() }
                .tabItem { Image(systemName: AppTab.tasks.icon) }
                .tag(AppTab.tasks)

            NavigationStack { AnalyticsView() }
                .tabItem { Image(systemName: AppTab.analytics.icon) }
                .tag(AppTab.analytics)

            NavigationStack { SettingsView() }
                .tabItem { Image(systemName: AppTab.settings.icon) }
                .tag(AppTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnimatedTabBar(
                selected: $router.selectedTab,
                bounceTab: $bounceTab,
                overdueCount: taskService.overdueCount
            )
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
        .sheet(isPresented: $router.showAddSupply) {
            AddSupplyItemSheet(list: nil, editingItem: nil)
                .environmentObject(supplyService)
                .environmentObject(propertyService)
        }
        .sheet(isPresented: $router.showWaterPlant) {
            NavigationStack {
                PlantsView()
                    .environmentObject(plantService)
                    .environmentObject(propertyService)
            }
        }
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
        .environmentObject(zoneService)
        .environmentObject(supplyService)
        .environmentObject(stickerService)
        .environmentObject(plantService)
        .environmentObject(deliveryService)
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
            if let propId = propertyService.primary?.id {
                await supplyService.load(propertyId: propId)
                await plantService.load(propertyId: propId)
            }
            writeWidgetSnapshot()
            updateDynamicShortcuts()
        }
        .onChange(of: propertyService.primary?.id) { _, newPropId in
            guard let newPropId else { return }
            Task {
                await supplyService.load(propertyId: newPropId)
                await plantService.load(propertyId: newPropId)
                writeWidgetSnapshot()
                updateDynamicShortcuts()
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
                if let propId = propertyService.primary?.id {
                    await supplyService.load(propertyId: propId)
                    await plantService.load(propertyId: propId)
                }
                writeWidgetSnapshot()
                updateDynamicShortcuts()
            }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            bounceTab = newTab
            if tabBarVis.scrolledDown { tabBarVis.scrolledDown = false }
        }
    }

    // MARK: Widget + Dynamic Shortcuts

    private func writeWidgetSnapshot() {
        var snapshot = PRVIOWidgetSnapshot()
        snapshot.overdueTaskCount = taskService.overdueCount
        snapshot.openTaskCount = taskService.tasks.filter { !$0.isCompleted }.count
        snapshot.plantsNeedingWater = plantService.plantsNeedingWater.count
        snapshot.plantNames = Array(plantService.plantsNeedingWater.prefix(3).map(\.name))
        snapshot.activeDeliveryCount = deliveryService.activeDeliveries.count
        snapshot.propertyName = propertyService.primary?.name
        SharedDataStore.write(snapshot)
    }

    private func updateDynamicShortcuts() {
        var items: [UIApplicationShortcutItem] = []
        if let plant = plantService.plantsNeedingWater.first {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.plants",
                localizedTitle: "Udă: \(plant.name)",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "drop.fill"),
                userInfo: nil
            ))
        }
        if let task = taskService.tasks.first(where: { !$0.isCompleted }) {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.addtask",
                localizedTitle: task.title,
                localizedSubtitle: "Sarcină",
                icon: UIApplicationShortcutIcon(systemImageName: "checklist"),
                userInfo: nil
            ))
        }
        if deliveryService.activeDeliveries.count > 0 {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.shopping",
                localizedTitle: "\(deliveryService.activeDeliveries.count) livrări active",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "shippingbox.fill"),
                userInfo: nil
            ))
        }
        UIApplication.shared.shortcutItems = items
    }

}

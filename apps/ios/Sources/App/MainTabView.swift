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

// MARK: - Scroll-direction tracker (Instagram-style tab hide)

struct TabScrollDetector: ViewModifier {
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    private let threshold: CGFloat = 32

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                let goingDown = offset < -threshold
                guard goingDown != tabBarVis.scrolledDown else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    tabBarVis.scrolledDown = goingDown
                }
            }
    }
}

extension View {
    /// Place this on the *content* inside a ScrollView to auto-hide the tab bar on scroll down.
    func trackTabScroll() -> some View { modifier(TabScrollDetector()) }
}

// MARK: - Custom animated tab bar

private struct AnimatedTabBar: View {
    @Binding var selected: AppTab
    @Binding var bounceTab: AppTab?
    let overdueCount: Int
    let bottomPad: CGFloat
    let scrolledDown: Bool

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
                            .scaleEffect(tab == selected ? 1.12 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
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
        .liquidGlass(cornerRadius: 32)
        .padding(.horizontal, 24)
        .padding(.bottom, bottomPad)
        .scaleEffect(scrolledDown ? 0.88 : 1.0)
        .opacity(scrolledDown ? 0 : 1)
        .offset(y: scrolledDown ? 80 : 0)
        .allowsHitTesting(!scrolledDown)
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

    // Reads the device's home-indicator safe area from UIKit so the pill
    // always sits above the gesture zone regardless of device model.
    private var deviceBottomSafe: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        // ZStack instead of TabView to avoid the iOS 26 system UITabBar
        // appearing alongside our custom AnimatedTabBar. All tabs are kept
        // alive in the hierarchy; only the selected one is interactive.
        ZStack {
            NavigationStack { DashboardView() }
                .opacity(router.selectedTab == .home ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .home)

            NavigationStack { DigitalTwinView() }
                .opacity(router.selectedTab == .map ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .map)

            NavigationStack { TasksView() }
                .opacity(router.selectedTab == .tasks ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .tasks)

            NavigationStack { AnalyticsView() }
                .opacity(router.selectedTab == .analytics ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .analytics)

            NavigationStack { SettingsView() }
                .opacity(router.selectedTab == .settings ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .settings)
        }
        .coordinateSpace(name: "scroll")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnimatedTabBar(
                selected: $router.selectedTab,
                bounceTab: $bounceTab,
                overdueCount: taskService.overdueCount,
                bottomPad: 8,
                scrolledDown: tabBarVis.scrolledDown
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
            notificationScheduler.registerCategories()
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
            await indexSpotlight()
            await notificationScheduler.schedulePlantWateringNotifications(plantService.plants)
        }
        .onChange(of: propertyService.primary?.id) { _, newPropId in
            guard let newPropId else { return }
            Task {
                await supplyService.load(propertyId: newPropId)
                await plantService.load(propertyId: newPropId)
                writeWidgetSnapshot()
                updateDynamicShortcuts()
                await indexSpotlight()
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
        .onReceive(NotificationCenter.default.publisher(for: .prvioProcessPending)) { _ in
            processPendingIntentActions()
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

        // Write entity catalogs for App Intents
        SharedDataStore.writeTaskCatalog(
            taskService.tasks.map { TaskCatalogEntry(id: $0.id, title: $0.title, priority: $0.priority, isCompleted: $0.isCompleted) }
        )
        SharedDataStore.writePlantCatalog(
            plantService.plants.map { PlantCatalogEntry(id: $0.id, name: $0.name, emoji: $0.emoji, needsWatering: $0.needsWatering) }
        )
    }

    private func indexSpotlight() async {
        await SpotlightService.shared.indexAll(
            tasks: taskService.tasks,
            plants: plantService.plants,
            lists: supplyService.lists,
            items: supplyService.items,
            docs: documentService.documents
        )
    }

    private func processPendingIntentActions() {
        let waterIds = SharedDataStore.popPendingWaterings()
        for id in waterIds {
            if let plant = plantService.plants.first(where: { $0.id == id }) {
                Task { await plantService.markWatered(plant) }
            }
        }
        let completeIds = SharedDataStore.popPendingCompletions()
        for id in completeIds {
            if let task = taskService.tasks.first(where: { $0.id == id }), !task.isCompleted {
                Task { await taskService.toggleComplete(task) }
            }
        }
        if !waterIds.isEmpty || !completeIds.isEmpty {
            writeWidgetSnapshot()
        }
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

import SwiftUI
import WidgetKit

final class TabBarVisibility: ObservableObject {
    @Published var isHidden = false
    @Published var scrollOffset: CGFloat = 0

    // 0 = fully shown, 1 = fully hidden — drives continuous zoom-out
    var hideProgress: CGFloat {
        if isHidden { return 1.0 }
        let start: CGFloat = -28
        let end: CGFloat = -110
        guard scrollOffset < start else { return 0 }
        return min((scrollOffset - start) / (end - start), 1.0)
    }

    var scrolledDown: Bool { hideProgress > 0.55 }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum AppTab: String, CaseIterable {
    case home, digitalTwin, tasks, chat, settings

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .digitalTwin: return "building.2.fill"
        case .tasks:       return "checklist"
        case .chat:        return "bubble.left.and.bubble.right.fill"
        case .settings:    return "person.crop.circle.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home:        return "house"
        case .digitalTwin: return "building.2"
        case .tasks:       return "checklist"
        case .chat:        return "bubble.left.and.bubble.right"
        case .settings:    return "person.crop.circle"
        }
    }
}

// MARK: - Scroll-direction tracker (Instagram-style tab hide)

struct TabScrollDetector: ViewModifier {
    @EnvironmentObject private var tabBarVis: TabBarVisibility

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
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
                    tabBarVis.scrollOffset = offset
                }
            }
    }
}

extension View {
    func trackTabScroll() -> some View { modifier(TabScrollDetector()) }
}

// MARK: - Threads / Liquid Glass tab bar

private struct AnimatedTabBar: View {
    @Binding var selected: AppTab
    @Binding var bounceTab: AppTab?
    let overdueCount: Int
    let bottomPad: CGFloat
    let hideProgress: CGFloat   // 0 = shown, 1 = hidden

    @EnvironmentObject private var profileService: ProfileService

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    HapticFeedback.selection()
                    bounceTab = tab
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { selected = tab }
                } label: {
                    tabItem(tab)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, bottomPad)
        .background {
            if #available(iOS 26, *) {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .scaleEffect(1.0 - hideProgress * 0.08, anchor: .bottom)
        .opacity(max(0, 1.0 - hideProgress * 2.2))
        .offset(y: hideProgress * 90)
        .allowsHitTesting(hideProgress < 0.45)
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = tab == selected
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                iconView(tab, isSelected: isSelected)
                    .font(.system(size: 23, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.33))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: bounceTab == tab)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)

                Circle()
                    .fill(Color.primary)
                    .frame(width: isSelected ? 4 : 0, height: isSelected ? 4 : 0)
                    .opacity(isSelected ? 0.7 : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
            }

            if tab == .tasks && overdueCount > 0 {
                Text(overdueCount < 10 ? "\(overdueCount)" : "9+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .offset(x: 8, y: -1)
            }
        }
    }

    @ViewBuilder
    private func iconView(_ tab: AppTab, isSelected: Bool) -> some View {
        if tab == .settings, let urlStr = profileService.profile?.avatarUrl,
           let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(
                            isSelected ? Color.primary : Color.primary.opacity(0.25),
                            lineWidth: isSelected ? 2.5 : 1.5
                        ))
                } else {
                    Image(systemName: isSelected ? tab.icon : tab.inactiveIcon)
                }
            }
            .frame(width: 26, height: 26)
        } else {
            Image(systemName: isSelected ? tab.icon : tab.inactiveIcon)
        }
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
    @StateObject private var applianceService = ApplianceService()
    @StateObject private var photoJournalService = PhotoJournalService()
    @StateObject private var paintColorService = PaintColorService()
    @StateObject private var propertyValueService = PropertyValueService()
    @StateObject private var tabBarVis = TabBarVisibility()
    @EnvironmentObject private var router: AppRouter

    @State private var bounceTab: AppTab? = nil

    var body: some View {
        ZStack {
            NavigationStack { DashboardView() }
                .opacity(router.selectedTab == .home ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .home)

            NavigationStack { DigitalTwinView() }
                .opacity(router.selectedTab == .digitalTwin ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .digitalTwin)

            NavigationStack { TasksView() }
                .opacity(router.selectedTab == .tasks ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .tasks)

            NavigationStack { ChatView() }
                .opacity(router.selectedTab == .chat ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .chat)

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
                bottomPad: 6,
                hideProgress: tabBarVis.hideProgress
            )
            .environmentObject(profileService)
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
        .environmentObject(applianceService)
        .environmentObject(photoJournalService)
        .environmentObject(paintColorService)
        .environmentObject(propertyValueService)
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
                await applianceService.load(propertyId: propId)
                await photoJournalService.load(propertyId: propId)
                await paintColorService.load(propertyId: propId)
                await propertyValueService.load(propertyId: propId)
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
                await applianceService.load(propertyId: newPropId)
                await photoJournalService.load(propertyId: newPropId)
                await paintColorService.load(propertyId: newPropId)
                await propertyValueService.load(propertyId: newPropId)
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
                    await applianceService.load(propertyId: propId)
                    await photoJournalService.load(propertyId: propId)
                    await paintColorService.load(propertyId: propId)
                    await propertyValueService.load(propertyId: propId)
                }
                writeWidgetSnapshot()
                updateDynamicShortcuts()
            }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            bounceTab = newTab
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                tabBarVis.scrollOffset = 0
            }
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

        SharedDataStore.writeTaskCatalog(
            taskService.tasks.map { TaskCatalogEntry(id: $0.id, title: $0.title, priority: $0.priority, isCompleted: $0.isCompleted) }
        )
        SharedDataStore.writePlantCatalog(
            plantService.plants.map { PlantCatalogEntry(id: $0.id, name: $0.name, emoji: $0.emoji, needsWatering: $0.needsWatering) }
        )
        WidgetCenter.shared.reloadAllTimelines()
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
        // iOS displays at most 4 items total (dynamic + static from Info.plist).
        // We set all 4 dynamically so content is always data-driven and contextual.
        var items: [UIApplicationShortcutItem] = []

        // 1. Urgent/overdue task — highest priority signal
        if let task = taskService.tasks.first(where: { $0.isOverdue }) {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.addtask",
                localizedTitle: task.title,
                localizedSubtitle: "Overdue task",
                icon: UIApplicationShortcutIcon(systemImageName: "exclamationmark.circle.fill")
            ))
        } else if let task = taskService.tasks.first(where: { !$0.isCompleted }) {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.addtask",
                localizedTitle: task.title,
                localizedSubtitle: "Next task",
                icon: UIApplicationShortcutIcon(systemImageName: "checklist")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.addtask",
                localizedTitle: "New Task",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle.fill")
            ))
        }

        // 2. Plant needing water — contextual
        if let plant = plantService.plantsNeedingWater.first {
            let subtitle = plantService.plantsNeedingWater.count > 1
                ? "\(plantService.plantsNeedingWater.count) need water"
                : "Needs water"
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.plants",
                localizedTitle: plant.name,
                localizedSubtitle: subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: "drop.fill")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.plants",
                localizedTitle: "My Plants",
                localizedSubtitle: plantService.plants.isEmpty ? nil : "All watered",
                icon: UIApplicationShortcutIcon(systemImageName: "leaf.fill")
            ))
        }

        // 3. Active delivery or shopping list
        if deliveryService.activeDeliveries.count > 0 {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.shopping",
                localizedTitle: "Active Deliveries",
                localizedSubtitle: "\(deliveryService.activeDeliveries.count) in transit",
                icon: UIApplicationShortcutIcon(systemImageName: "shippingbox.fill")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.shopping",
                localizedTitle: "Shopping List",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "cart.fill")
            ))
        }

        // 4. Family Chat
        items.append(UIApplicationShortcutItem(
            type: "com.prvio.action.chat",
            localizedTitle: "Family Chat",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right.fill")
        ))

        UIApplication.shared.shortcutItems = items
    }
}

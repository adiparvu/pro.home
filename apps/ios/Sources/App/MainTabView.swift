import SwiftUI
import WidgetKit

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
    @StateObject private var receiptService = ReceiptService()
    @StateObject private var stickerService = StickerService()
    @StateObject private var plantService = PlantService()
    @StateObject private var deliveryService = DeliveryService()
    @StateObject private var applianceService = ApplianceService()
    @StateObject private var inventoryService = InventoryService()
    @StateObject private var photoJournalService = PhotoJournalService()
    @StateObject private var paintColorService = PaintColorService()
    @StateObject private var propertyValueService = PropertyValueService()
    @StateObject private var contractorService = ContractorService()
    @StateObject private var proactiveEngine = ProactiveEngine()
    @StateObject private var tabBarVis = TabBarVisibility()
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { DashboardView() }
                .tabItem { Image(systemName: "house.fill") }
                .tag(AppTab.home)

            NavigationStack { PropertyTabView() }
                .tabItem { Image(systemName: "square.stack.3d.up.fill") }
                .tag(AppTab.digitalTwin)

            NavigationStack { TasksView() }
                .tabItem { Image(systemName: "checklist") }
                .tag(AppTab.tasks)
                .badge(taskService.overdueCount > 0 ? taskService.overdueCount : 0)

            NavigationStack {
                AIInsightsView()
                    .environmentObject(taskService)
                    .environmentObject(elementService)
                    .environmentObject(zoneService)
                    .environmentObject(plantService)
                    .environmentObject(propertyService)
                    .environmentObject(tabBarVis)
                    .environmentObject(router)
            }
            .tabItem { Image(systemName: "sparkles") }
            .tag(AppTab.chat)

            NavigationStack { SettingsView() }
                .tabItem { Image(systemName: "person.crop.circle.fill") }
                .tag(AppTab.settings)
        }
        .toolbar(tabBarVis.isHidden ? .hidden : .automatic, for: .tabBar)
        .fullScreenCover(isPresented: $router.showARIA) {
            NavigationStack {
                ARIAView(onDismiss: { router.showARIA = false })
                    .environmentObject(propertyService)
                    .environmentObject(familyService)
                    .environmentObject(profileService)
                    .environmentObject(taskService)
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
        .sheet(isPresented: $router.showFamilyChat) {
            NavigationStack {
                ChatView()
                    .environmentObject(familyService)
                    .environmentObject(propertyService)
                    .environmentObject(messageService)
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
        .environmentObject(receiptService)
        .environmentObject(stickerService)
        .environmentObject(plantService)
        .environmentObject(deliveryService)
        .environmentObject(applianceService)
        .environmentObject(inventoryService)
        .environmentObject(photoJournalService)
        .environmentObject(paintColorService)
        .environmentObject(propertyValueService)
        .environmentObject(contractorService)
        .environmentObject(proactiveEngine)
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
            await contractorService.load()
            if let propId = propertyService.primary?.id {
                await deliveryService.load(propertyId: propId)
                await supplyService.load(propertyId: propId)
                await receiptService.load(propertyId: propId)
                await plantService.load(propertyId: propId)
                await applianceService.load(propertyId: propId)
                await photoJournalService.load(propertyId: propId)
                await paintColorService.load(propertyId: propId)
                await propertyValueService.load(propertyId: propId)
                await inventoryService.load(propertyId: propId)
                await budgetService.load(propertyId: propId)
            }
            writeWidgetSnapshot()
            updateDynamicShortcuts()
            await indexSpotlight()
            await notificationScheduler.schedulePlantWateringNotifications(plantService.plants)
            proactiveEngine.analyze(appliances: applianceService.appliances, elements: elementService.elements)
            ProactiveEngine.cacheForBackground(appliances: applianceService.appliances, elements: elementService.elements)
        }
        .onChange(of: propertyService.primary?.id) { _, newPropId in
            guard let newPropId else { return }
            Task {
                await deliveryService.load(propertyId: newPropId)
                await supplyService.load(propertyId: newPropId)
                await receiptService.load(propertyId: newPropId)
                await plantService.load(propertyId: newPropId)
                await applianceService.load(propertyId: newPropId)
                await photoJournalService.load(propertyId: newPropId)
                await paintColorService.load(propertyId: newPropId)
                await propertyValueService.load(propertyId: newPropId)
                await inventoryService.load(propertyId: newPropId)
                await budgetService.load(propertyId: newPropId)
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
                    await deliveryService.load(propertyId: propId)
                    await supplyService.load(propertyId: propId)
                    await receiptService.load(propertyId: propId)
                    await plantService.load(propertyId: propId)
                    await applianceService.load(propertyId: propId)
                    await photoJournalService.load(propertyId: propId)
                    await paintColorService.load(propertyId: propId)
                    await propertyValueService.load(propertyId: propId)
                    await inventoryService.load(propertyId: propId)
                    await budgetService.load(propertyId: propId)
                }
                writeWidgetSnapshot()
                updateDynamicShortcuts()
            }
        }
        .onChange(of: router.selectedTab) { _, _ in
            tabBarVis.scrollOffset = 0
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

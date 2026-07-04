import SwiftUI
import WidgetKit

// MARK: - Main tab view

struct MainTabView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppSettings.self) private var appSettings
    @State private var taskService = TaskService()
    @State private var propertyService = PropertyService()
    @State private var profileService = ProfileService()
    @State private var financialService = FinancialService()
    @State private var documentService = DocumentService()
    @State private var notificationScheduler = NotificationScheduler()
    @State private var budgetService = BudgetService()
    @State private var familyService = FamilyService()
    @State private var messageService = MessageService()
    @State private var currencyService = CurrencyService()
    @State private var elementService = PropertyElementService()
    @State private var zoneService = PropertyZoneService()
    @State private var supplyService = SupplyService()
    @State private var receiptService = ReceiptService()
    @State private var stickerService = StickerService()
    @State private var plantService = PlantService()
    @State private var deliveryService = DeliveryService()
    @State private var applianceService = ApplianceService()
    @State private var inventoryService = InventoryService()
    @State private var photoJournalService = PhotoJournalService()
    @State private var paintColorService = PaintColorService()
    @State private var propertyValueService = PropertyValueService()
    @State private var contractorService = ContractorService()
    @State private var directMessageService = DirectMessageService()
    @State private var presenceService = PresenceService()
    @State private var proactiveEngine = ProactiveEngine()
    @State private var tabBarVis = TabBarVisibility()
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        let visibleTabs = AppTab.visible(for: propertyService.myRole)
        return TabView(selection: $router.selectedTab) {
            if visibleTabs.contains(.home) {
                NavigationStack { DashboardView() }
                    .tabItem { Image(systemName: "house.fill") }
                    .tag(AppTab.home)
            }

            if visibleTabs.contains(.digitalTwin) {
                NavigationStack { PropertyTabView() }
                    .tabItem { Image(systemName: "square.stack.3d.up.fill") }
                    .tag(AppTab.digitalTwin)
            }

            if visibleTabs.contains(.tasks) {
                NavigationStack { TasksView() }
                    .tabItem { Image(systemName: "checklist") }
                    .tag(AppTab.tasks)
                    .badge(taskService.overdueCount > 0 ? taskService.overdueCount : 0)
            }

            NavigationStack {
                ConversationsView()
                    .environment(messageService)
                    .environment(directMessageService)
                    .environment(presenceService)
                    .environment(familyService)
                    .environment(propertyService)
                    .environment(profileService)
                    .environment(stickerService)
                    .environment(tabBarVis)
                    .environment(router)
            }
            .tabItem { Image(systemName: "bubble.left.and.bubble.right.fill") }
            .tag(AppTab.chat)

            NavigationStack { SettingsView() }
                .tabItem { Image(systemName: "person.crop.circle.fill") }
                .tag(AppTab.settings)
        }
        .toolbar(tabBarVis.isHidden ? .hidden : .automatic, for: .tabBar)
        .fullScreenCover(isPresented: $router.showARIA) {
            NavigationStack {
                ARIAView(onDismiss: { router.showARIA = false })
                    .environment(propertyService)
                    .environment(familyService)
                    .environment(profileService)
                    .environment(taskService)
            }
        }
        .sheet(isPresented: $router.showAddTask) { AddTaskView() }
        .sheet(isPresented: $router.showAddExpense) { AddFinancialView { await financialService.load() } }
        .sheet(isPresented: $router.showInventoryScan) { NavigationStack { InventoryView(autoScan: true) } }
        .sheet(isPresented: $router.showInventoryAdd) { NavigationStack { InventoryView(autoAdd: true) } }
        .sheet(isPresented: $router.showInventoryView) { NavigationStack { InventoryView() } }
        .sheet(isPresented: $router.showAddSupply) {
            AddSupplyItemSheet(list: nil, editingItem: nil)
                .environment(supplyService)
                .environment(propertyService)
        }
        .sheet(isPresented: $router.showWaterPlant) {
            NavigationStack {
                PlantsView()
                    .environment(plantService)
                    .environment(propertyService)
            }
        }
        .sheet(isPresented: $router.showFamilyChat) {
            NavigationStack {
                ConversationsView()
                    .environment(messageService)
                    .environment(directMessageService)
                    .environment(presenceService)
                    .environment(familyService)
                    .environment(propertyService)
                    .environment(profileService)
                    .environment(stickerService)
                    .environment(tabBarVis)
                    .environment(router)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showDocuments) {
            NavigationStack {
                DocumentsView()
                    .environment(documentService)
                    .environment(propertyService)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showFamily) {
            NavigationStack {
                FamilyView()
                    .environment(familyService)
                    .environment(propertyService)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showContractors) {
            NavigationStack {
                ContractorsView()
                    .environment(contractorService)
                    .environment(propertyService)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showDeliveries) {
            NavigationStack {
                DeliveriesView()
                    .environment(deliveryService)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showFinances) {
            NavigationStack {
                FinancesView()
                    .environment(financialService)
                    .environment(propertyService)
                    .environment(budgetService)
                    .environment(currencyService)
                    .environment(appSettings)
                    .environment(tabBarVis)
            }
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonAddTask)) { _ in
            router.showAddTask = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonWaterPlants)) { _ in
            router.showWaterPlant = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonOpenARIA)) { _ in
            router.showARIA = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonOpenDigitalTwin)) { _ in
            router.selectedTab = .digitalTwin
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonScanNFC)) { _ in
            guard NFCScanService.isSupported else { return }
            NFCScanService.shared.scan(prompt: "Apropie iPhone-ul de tag-ul NFC") { _ in }
        }
        .environment(router)
        .environment(tabBarVis)
        .environment(taskService)
        .environment(propertyService)
        .environment(profileService)
        .environment(financialService)
        .environment(documentService)
        .environment(notificationScheduler)
        .environment(budgetService)
        .environment(familyService)
        .environment(messageService)
        .environment(currencyService)
        .environment(elementService)
        .environment(zoneService)
        .environment(supplyService)
        .environment(receiptService)
        .environment(stickerService)
        .environment(plantService)
        .environment(deliveryService)
        .environment(applianceService)
        .environment(inventoryService)
        .environment(photoJournalService)
        .environment(paintColorService)
        .environment(propertyValueService)
        .environment(contractorService)
        .environment(directMessageService)
        .environment(presenceService)
        .environment(proactiveEngine)
        .task {
            await currencyService.refresh()
            await propertyService.load()
            await propertyService.loadMyRole()
            redirectIfTabHidden()
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
            // Live Activities: property context + the "Start When App Opens" /
            // "Start on a Schedule" preferences, now that data is loaded.
            LiveActivityService.shared.propertyName = propertyService.primary?.name ?? ""
            LiveActivityService.shared.evaluateAutoStart(
                deliveries: deliveryService.deliveries, tasks: taskService.tasks)
            proactiveEngine.analyze(appliances: applianceService.appliances, elements: elementService.elements)
            ProactiveEngine.cacheForBackground(appliances: applianceService.appliances, elements: elementService.elements)
        }
        .task {
            // Presence heartbeat: advertise ourselves and refresh members' status
            // on a slow cadence while the app is foregrounded.
            while !Task.isCancelled {
                await pulsePresence()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Beat immediately on foreground so we don't read as offline after a
            // background gap; drop the live channel while backgrounded.
            if phase == .active { Task { await pulsePresence() } }
            else if phase == .background { Task { await presenceService.unsubscribe() } }
        }
        .onChange(of: propertyService.primary?.id) { _, newPropId in
            guard let newPropId else { return }
            Task {
                await propertyService.loadMyRole()
                redirectIfTabHidden()
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

    /// If the selected tab isn't available to the current role (e.g. a guest on
    /// the Home tab), fall back to Chat, which every role can see.
    private func redirectIfTabHidden() {
        if !AppTab.visible(for: propertyService.myRole).contains(router.selectedTab) {
            router.selectedTab = .chat
        }
    }

    /// One presence beat: stamp our own heartbeat, then refresh the property's
    /// statuses. No-op until we have a property, a session, and a display name.
    private func pulsePresence() async {
        guard let pid = propertyService.primary?.id,
              let uid = auth.session?.user.id else { return }
        let name = profileService.profile?.preferredName
            ?? profileService.profile?.fullName ?? ""
        guard !name.isEmpty else { return }
        // subscribe() is idempotent per property, so this both establishes the
        // live channel once and self-heals if the primary property changed.
        await presenceService.subscribe(propertyId: pid)
        await presenceService.heartbeat(propertyId: pid, userId: uid, userName: name)
        await presenceService.load(propertyId: pid)
    }

    private func writeWidgetSnapshot() {
        var snapshot = PRVIOWidgetSnapshot()
        snapshot.overdueTaskCount = taskService.overdueCount
        snapshot.openTaskCount = taskService.tasks.filter { !$0.isCompleted }.count
        snapshot.plantsNeedingWater = plantService.plantsNeedingWater.count
        snapshot.plantNames = Array(plantService.plantsNeedingWater.prefix(3).map(\.name))
        snapshot.activeDeliveryCount = deliveryService.activeDeliveries.count
        snapshot.propertyName = propertyService.primary?.name
        snapshot.pendingSupplyCount = supplyService.totalPending
        snapshot.unreadMessages = messageService.unreadCount
        snapshot.propertyHealthScore = propertyService.primary?.healthScore
        snapshot.criticalTaskTitle = taskService.tasks.first { $0.isOverdue && !$0.isCompleted }?.title
        let upcoming = taskService.tasks
            .filter { !$0.isCompleted && !$0.isOverdue && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? "") < ($1.dueDate ?? "") }
            .first
        snapshot.nextMaintenanceTitle = upcoming?.title
        snapshot.nextMaintenanceDue = upcoming?.dueDateDisplay
        SharedDataStore.write(snapshot)

        SharedDataStore.writeTaskCatalog(
            taskService.tasks.map { TaskCatalogEntry(id: $0.id, title: $0.title, priority: $0.priority,
                                                     isCompleted: $0.isCompleted, isOverdue: $0.isOverdue) }
        )
        SharedDataStore.writePlantCatalog(
            plantService.plants.map { PlantCatalogEntry(id: $0.id, name: $0.name, emoji: $0.emoji, needsWatering: $0.needsWatering) }
        )
        SharedDataStore.writeSupplyCatalog(
            supplyService.items.map { SupplyCatalogEntry(id: $0.id, name: $0.name, isCompleted: $0.isCompleted) }
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
        let supplyIds = SharedDataStore.popPendingSupplyChecks()
        for id in supplyIds {
            if let item = supplyService.items.first(where: { $0.id == id }), !item.isCompleted {
                Task { await supplyService.toggleComplete(item) }
            }
        }
        if !waterIds.isEmpty || !completeIds.isEmpty || !supplyIds.isEmpty {
            writeWidgetSnapshot()
        }
    }

    private func updateDynamicShortcuts() {
        // iOS displays at most 4 items total (dynamic + static from Info.plist).
        // We set all 4 dynamically so content is always data-driven and contextual.
        var items: [UIApplicationShortcutItem] = []

        // 1. Urgent/overdue task — highest priority signal. Showing a task's
        // title must open THAT task, so its id rides along in the type string
        // (userInfo doesn't survive our cold-launch UserDefaults hand-off).
        if let task = taskService.tasks.first(where: { $0.isOverdue }) {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.opentask:\(task.id.uuidString)",
                localizedTitle: task.title,
                localizedSubtitle: String(localized: "Overdue task"),
                icon: UIApplicationShortcutIcon(systemImageName: "exclamationmark.circle.fill")
            ))
        } else if let task = taskService.tasks.first(where: { !$0.isCompleted }) {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.opentask:\(task.id.uuidString)",
                localizedTitle: task.title,
                localizedSubtitle: String(localized: "Next task"),
                icon: UIApplicationShortcutIcon(systemImageName: "checklist")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.addtask",
                localizedTitle: String(localized: "New Task"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle.fill")
            ))
        }

        // 2. Plant needing water — contextual
        if let plant = plantService.plantsNeedingWater.first {
            let subtitle = plantService.plantsNeedingWater.count > 1
                ? String(format: String(localized: "%d need water"), plantService.plantsNeedingWater.count)
                : String(localized: "Needs water")
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.plants",
                localizedTitle: plant.name,
                localizedSubtitle: subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: "drop.fill")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.plants",
                localizedTitle: String(localized: "My Plants"),
                localizedSubtitle: plantService.plants.isEmpty ? nil : String(localized: "All watered"),
                icon: UIApplicationShortcutIcon(systemImageName: "leaf.fill")
            ))
        }

        // 3. Active delivery or shopping list — each opens its OWN screen
        // (the deliveries variant previously landed on the shopping form).
        if deliveryService.activeDeliveries.count > 0 {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.deliveries",
                localizedTitle: String(localized: "Active Deliveries"),
                localizedSubtitle: String(format: String(localized: "%d in transit"), deliveryService.activeDeliveries.count),
                icon: UIApplicationShortcutIcon(systemImageName: "shippingbox.fill")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.prvio.action.shopping",
                localizedTitle: String(localized: "Shopping List"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "cart.fill")
            ))
        }

        // 4. Family Chat
        items.append(UIApplicationShortcutItem(
            type: "com.prvio.action.chat",
            localizedTitle: String(localized: "Family Chat"),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right.fill")
        ))

        UIApplication.shared.shortcutItems = items
    }
}

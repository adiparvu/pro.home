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
    @State private var pantryService = PantryService()
    @State private var receiptService = ReceiptService()
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
    @State private var notificationService = NotificationService()
    @State private var tabBarVis = TabBarVisibility()
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        let visibleTabs = AppTab.visible(for: propertyService.myRole)
        return TabView(selection: $router.selectedTab) {
            if visibleTabs.contains(.home) {
                // Family sees the household dashboard; outsiders (tenant) get
                // the personal space — the family surfaces are RLS-empty for
                // them, so the dashboard would render broken.
                NavigationStack(path: path(for: .home)) {
                    routedRoot {
                        if propertyService.isFamilyMember {
                            DashboardView()
                        } else {
                            PersonalSpaceHome()
                        }
                    }
                }
                .tabItem { Image(systemName: "house.fill") }
                .tag(AppTab.home)
            }

            if visibleTabs.contains(.digitalTwin) {
                NavigationStack(path: path(for: .digitalTwin)) { routedRoot { PropertyTabView() } }
                    .tabItem { Image(systemName: "square.stack.3d.up.fill") }
                    .tag(AppTab.digitalTwin)
            }

            if visibleTabs.contains(.tasks) {
                NavigationStack(path: path(for: .tasks)) { routedRoot { TasksView() } }
                    .tabItem { Image(systemName: "checklist") }
                    .tag(AppTab.tasks)
                    .badge(taskService.overdueCount > 0 ? taskService.overdueCount : 0)
            }

            NavigationStack(path: path(for: .chat)) {
                routedRoot {
                    ConversationsView()
                        .environment(messageService)
                        .environment(directMessageService)
                        .environment(presenceService)
                        .environment(familyService)
                        .environment(propertyService)
                        .environment(profileService)
                        .environment(tabBarVis)
                        .environment(router)
                }
            }
            .tabItem { Image(systemName: "bubble.left.and.bubble.right.fill") }
            .tag(AppTab.chat)

            NavigationStack(path: path(for: .settings)) { routedRoot { SettingsView() } }
                .tabItem { Image(systemName: "person.crop.circle.fill") }
                .tag(AppTab.settings)
        }
        .toolbar(tabBarVis.isHidden ? .hidden : .automatic, for: .tabBar)
        .fullScreenCover(item: $router.activeCover,
                         onDismiss: { router.drainPending() }) { destination in
            routedCover(destination)
        }
        .sheet(item: $router.activeDestination,
               onDismiss: { router.drainPending() }) { destination in
            routedSheet(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonAddTask)) { _ in
            router.activeDestination = .newTask
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonWaterPlants)) { _ in
            router.navigate(to: .plants(id: nil))
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonOpenARIA)) { _ in
            router.navigate(to: .aria)
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
        .environment(notificationService)
        .environment(budgetService)
        .environment(familyService)
        .environment(messageService)
        .environment(currencyService)
        .environment(elementService)
        .environment(zoneService)
        .environment(supplyService)
        .environment(pantryService)
        .environment(receiptService)
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
            WatchSyncService.shared.activate()
            // Now that the user is signed in, make sure the device is registered
            // for push (requests permission the first time) — without a device
            // token the backend has nowhere to deliver chat notifications.
            PushTokenService.ensureRegistered()
            await reloadWorld(reason: .coldStart)
            // Reminders checked off while the app was closed complete their
            // linked tasks now that the task list is loaded.
            await taskService.syncFromReminders()
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
            if phase == .active {
                Task { await pulsePresence() }
                // A reminder ticked in the Reminders app while we were in the
                // background completes its linked task on return.
                Task { await taskService.syncFromReminders() }
                // Any household member who changed their photo while we were
                // away shows their new avatar the moment we return.
                MemberDirectory.shared.refreshSoon()
            }
            else if phase == .background {
                Task { await presenceService.unsubscribe() }
                // Widgets must always show the state you left the app in —
                // refresh the shared snapshot on every trip to the background.
                writeWidgetSnapshot()
                updateDynamicShortcuts()
            }
        }
        .onChange(of: propertyService.primary?.id) { _, newPropId in
            // Switching property is a full context switch: the role, every
            // property-scoped module, the group chat and the glanceable
            // surfaces all re-point at the newly selected home — only the
            // person-level things (profile, appearance, accounts) survive.
            guard newPropId != nil else { return }
            Task { await reloadWorld(reason: .propertySwitch) }
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
            Task { await reloadWorld(reason: .accountSwitch(userId: newId)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prvioOpenChat)) { _ in
            // A chat push was tapped: land on the chat tab; the conversation
            // list drains the stored target and opens the right thread.
            router.selectedTab = .chat
        }
        .onChange(of: router.selectedTab) { _, _ in
            tabBarVis.scrollOffset = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .prvioProcessPending)) { _ in
            processPendingIntentActions()
        }
    }

    // MARK: - Routed navigation
    //
    // The HIG split, wired app-wide: content modules PUSH onto the active
    // tab's stack (destinations — large title, edge-swipe back), while
    // self-contained tasks PRESENT (one sheet slot + one cover slot, which
    // can never race themselves).

    /// Binding into the router's per-tab pushed-pages path.
    private func path(for tab: AppTab) -> Binding<[AppRouter.RoutedDestination]> {
        Binding(get: { router.tabPaths[tab] ?? [] },
                set: { router.tabPaths[tab] = $0 })
    }

    /// Registers the routed content pages on a tab's stack root.
    private func routedRoot<Root: View>(@ViewBuilder _ root: () -> Root) -> some View {
        root().navigationDestination(for: AppRouter.RoutedDestination.self) { destination in
            routedPage(destination)
        }
    }

    /// Content modules, pushed. Services arrive through the environment the
    /// tab stacks already live in — same as any NavigationLink in the app.
    @ViewBuilder
    private func routedPage(_ destination: AppRouter.RoutedDestination) -> some View {
        switch destination {
        case .finances:
            FinancesView()
        case .documents:
            DocumentsView()
        case .inventory:
            InventoryView()
        case .family:
            FamilyView()
        case .contractors:
            ContractorsView()
        case .deliveries:
            DeliveriesView()
        case .supplies:
            SuppliesView()
        case .pantry:
            PantryView()
        case .cameras:
            CamerasView()
        case .paintColors:
            PaintColorsView()
        case .photoJournal:
            PhotoJournalView()
        case .plants:
            PlantsView()
        case .profile:
            ProfileView()
        case .emergency:
            EmergencyModeView()
        case .iotHub:
            IoTHubView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func routedCover(_ destination: AppRouter.RoutedDestination) -> some View {
        switch destination {
        case .aria:
            NavigationStack {
                ARIAView(onDismiss: { router.activeCover = nil })
                    .environment(propertyService)
                    .environment(familyService)
                    .environment(profileService)
                    .environment(taskService)
            }
        // Cameras / scanners present full-screen — a camera must never float as
        // a sheet with the page showing through behind it. The inventory
        // scanner also used to stack as a SECOND sheet on top of the inventory
        // module when opened from Control Center / Shortcuts; full-screen here
        // (plus a full-screen internal scanner) removes the stacked-sheet look.
        case .receiptScan:
            // Camera OCR receipt scanner (its own NavigationStack, with Cancel).
            // Receipt + property services are required; supply/pantry are read
            // optionally for shopping-list sync from the ambient environment.
            ReceiptScannerView()
                .environment(receiptService)
                .environment(propertyService)
        case .inventoryScan:
            NavigationStack { InventoryView(autoScan: true) }
        case .inventoryAdd:
            NavigationStack { InventoryView(autoAdd: true) }
        default:
            EmptyView()
        }
    }

    /// Self-contained tasks, presented modally (the HIG's modality rule) —
    /// content modules push via routedPage instead.
    @ViewBuilder
    private func routedSheet(_ destination: AppRouter.RoutedDestination) -> some View {
        switch destination {
        case .newTask:
            AddTaskView()
        case .addExpense:
            AddFinancialView { await financialService.load() }
        case .addSupply:
            AddSupplyItemSheet(list: nil, editingItem: nil)
                .environment(supplyService)
                .environment(propertyService)
        case .notifications:
            NavigationStack {
                NotificationCenterView(service: notificationService)
                    .environment(auth)
                    .environment(router)
            }
            .presentationDragIndicator(.visible)
        case .notificationsChat:
            NavigationStack {
                NotificationCenterView(service: notificationService, initialFilter: "chat")
                    .environment(auth)
                    .environment(router)
            }
            .presentationDragIndicator(.visible)
        default:
            // Content modules never land in the sheet slot; ARIA is always
            // cover-presented (routedCover).
            EmptyView()
        }
    }

    // MARK: Widget + Dynamic Shortcuts

    /// If the selected tab isn't available to the current role (e.g. a guest on
    /// the Home tab), fall back to Chat, which every role can see.
    // MARK: - The one startup / context-switch orchestration
    //
    // Cold start, property switch and account switch used to carry three
    // hand-copied ~25-call load blocks that drifted apart (the account path
    // had quietly lost contractors, Spotlight and notification rescheduling).
    // One method, one order, three entry reasons — the paths can't diverge.

    private enum ReloadReason {
        case coldStart
        case propertySwitch
        case accountSwitch(userId: UUID)
    }

    private func reloadWorld(reason: ReloadReason) async {
        // Phase 1 — identity: property list + role decide the tab layout and
        // every property-scoped load below.
        switch reason {
        case .coldStart:
            // Currency + profile are independent; overlap them with the
            // property resolution.
            async let currency: Void = currencyService.refresh()
            async let profile: Void = loadProfileAndSettings()
            await propertyService.load()
            await propertyService.loadMyRole()
            redirectIfTabHidden()
            // The tab layout is settled: buffered cold-launch routes (widget
            // taps, quick actions, deep links) can present without being
            // overridden by the initial mount.
            router.markReady()
            _ = await (currency, profile)
        case .accountSwitch(let userId):
            await propertyService.load()
            await propertyService.loadMyRole()
            redirectIfTabHidden()
            await profileService.load(userId: userId)
            if let profile = profileService.profile {
                appSettings.loadFromProfile(profile)
            }
        case .propertySwitch:
            await propertyService.loadMyRole()
            redirectIfTabHidden()
        }

        // Phase 2 — data. Independent network I/O fanned out with async let:
        // the round-trips overlap instead of paying their sum, and every
        // service decodes off the main actor (PropertyRepo).
        let propId = propertyService.primary?.id
        async let tasksLoad: Void = taskService.load()
        async let financialLoad: Void = financialService.load()
        async let documentsLoad: Void = documentService.load()
        async let familyLoad: Void = familyService.load()
        async let contractorLoad: Void = contractorService.load()
        async let chatNameLoad: Void = propertyService.loadGroupChatName()
        await tasksLoad; await financialLoad; await documentsLoad
        await familyLoad; await contractorLoad; await chatNameLoad

        if let propId {
            async let messagesLoad: Void = messageService.load(propertyId: propId)
            async let deliveriesLoad: Void = deliveryService.load(propertyId: propId)
            async let suppliesLoad: Void = supplyService.load(propertyId: propId)
            async let receiptsLoad: Void = receiptService.load(propertyId: propId)
            async let plantsLoad: Void = plantService.load(propertyId: propId)
            async let appliancesLoad: Void = applianceService.load(propertyId: propId)
            async let journalLoad: Void = photoJournalService.load(propertyId: propId)
            async let paintLoad: Void = paintColorService.load(propertyId: propId)
            async let valueLoad: Void = propertyValueService.load(propertyId: propId)
            async let inventoryLoad: Void = inventoryService.load(propertyId: propId)
            async let budgetLoad: Void = budgetService.load(propertyId: propId)
            await messagesLoad; await deliveriesLoad; await suppliesLoad
            await receiptsLoad; await plantsLoad; await appliancesLoad
            await journalLoad; await paintLoad; await valueLoad
            await inventoryLoad; await budgetLoad
        }

        // Phase 3 — glanceable surfaces, always in the same order.
        // Apple Weather first (1h App-Group cache) so the snapshot written
        // below already carries it to the watch.
        if let lat = propertyService.primary?.latitude,
           let lon = propertyService.primary?.longitude {
            await PropertyWeather.refreshIfStale(latitude: lat, longitude: lon)
        }
        notificationScheduler.registerCategories()
        await notificationScheduler.reschedule(
            tasks: taskService.tasks,
            documents: documentService.documents
        )
        writeWidgetSnapshot()
        updateDynamicShortcuts()
        await indexSpotlight()
        await notificationScheduler.schedulePlantWateringNotifications(plantService.plants)
        await notificationScheduler.scheduleCelebrations(
            accountCreatedAt: profileService.profile?.createdAt,
            birthDate: profileService.profile?.birthDate)
        await notificationScheduler.scheduleMonthlyRecap()
        LiveActivityService.shared.propertyName = propertyService.primary?.name ?? ""
        if case .coldStart = reason {
            // "Start When App Opens" belongs to launch, not to context switches.
            LiveActivityService.shared.evaluateAutoStart(
                deliveries: deliveryService.deliveries, tasks: taskService.tasks)
        }
        proactiveEngine.analyze(appliances: applianceService.appliances, elements: elementService.elements,
                                records: financialService.records, tasks: taskService.tasks)
        ProactiveEngine.cacheForBackground(appliances: applianceService.appliances, elements: elementService.elements)
    }

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

    private func loadProfileAndSettings() async {
        guard let uid = auth.session?.user.id else { return }
        await profileService.load(userId: uid)
        if let profile = profileService.profile {
            appSettings.loadFromProfile(profile)
        }
    }

    private func writeWidgetSnapshot() {
        // The wrist mirrors the phone, so it must obey the same role boundary:
        // an outsider (tenant/guest/worker) gets strictly their own surfaces —
        // their tasks (already RLS-scoped) and their chat — never the family's
        // plants, pantry, deliveries, budget, insight, streak or health score.
        // Defense in depth on top of server RLS, not a substitute for it.
        let family = propertyService.isFamilyMember
        var snapshot = PRVIOWidgetSnapshot()
        snapshot.overdueTaskCount = taskService.overdueCount
        snapshot.openTaskCount = taskService.tasks.filter { !$0.isCompleted }.count
        snapshot.plantsNeedingWater = family ? plantService.plantsNeedingWater.count : 0
        snapshot.plantNames = family ? Array(plantService.plantsNeedingWater.prefix(3).map(\.name)) : []
        snapshot.activeDeliveryCount = family ? deliveryService.activeDeliveries.count : 0
        snapshot.propertyName = propertyService.primary?.name
        snapshot.pendingSupplyCount = family ? supplyService.totalPending : 0
        snapshot.unreadMessages = propertyService.primary.map {
            messageService.groupUnread(propertyId: $0.id, myId: supabase.auth.currentSession?.user.id)
        } ?? 0
        snapshot.propertyHealthScore = family ? propertyService.primary?.healthScore : nil
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
            family ? plantService.plants.map { PlantCatalogEntry(id: $0.id, name: $0.name, emoji: $0.emoji, needsWatering: $0.needsWatering, healthScore: $0.healthScore) } : []
        )
        SharedDataStore.writeSupplyCatalog(
            family ? supplyService.items.map { SupplyCatalogEntry(id: $0.id, name: $0.name, isCompleted: $0.isCompleted) } : []
        )
        SharedDataStore.writeDeliveryCatalog(
            family ? deliveryService.activeDeliveries.map {
                DeliveryCatalogEntry(id: $0.id, title: $0.description, carrier: $0.carrier,
                                     status: $0.status, eta: $0.expectedDisplay)
            } : []
        )
        SharedDataStore.writePantryCatalog(
            family ? pantryService.items.prefix(24).map {
                PantryCatalogEntry(id: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit)
            } : []
        )
        // Context for in-app intents (Shortcuts "send message to chat").
        SharedDataStore.setContext(propertyId: propertyService.primary?.id,
                                   myName: profileService.profile?.preferredName)
        // Wrist extras: the property pin, the engine's freshest insight, and
        // Apple Weather for the property (whatever the cache holds — the
        // refresh runs in the startup orchestration).
        // Insight, streak and budget are family intelligence — an outsider's
        // wrist gets none of them (weather and the property pin stay: they
        // describe the place the person lives or works at, not the family).
        let topInsight = family ? proactiveEngine.insights.first { !$0.isDismissed } : nil
        let weather = PropertyWeather.cached()
        // The house streak: consecutive verified all-clear days.
        let streak = family ? SharedDataStore.updateHouseStreak(
            allClear: snapshot.overdueTaskCount == 0 && snapshot.plantsNeedingWater == 0) : nil
        // This month's spending for the wrist — household currency only, so
        // the number is honest (a EUR bill never inflates a RON total).
        let householdCurrency = financialService.currency
        let monthSpent = financialService.currentMonthRecords
            .filter { $0.type == "expense" && $0.currency == householdCurrency }
            .reduce(0) { $0 + $1.amount }
        let budgetLimit = budgetService.totalBudget()
        SharedDataStore.writeWatchExtras(SharedDataStore.WatchExtras(
            latitude: propertyService.primary?.latitude,
            longitude: propertyService.primary?.longitude,
            insightTitle: topInsight?.title,
            insightBody: topInsight?.body,
            weatherTemp: weather?.temp,
            weatherSymbol: weather?.symbol,
            weatherLo: weather?.lo,
            weatherHi: weather?.hi,
            weatherAdvisory: weather?.advisory,
            streakDays: streak,
            budgetSpent: (family && !financialService.records.isEmpty) ? monthSpent : nil,
            budgetLimit: (family && budgetLimit > 0) ? budgetLimit : nil,
            budgetCurrency: (family && !financialService.records.isEmpty) ? householdCurrency : nil))
        // Stamp the snapshot with the owning account + role scope so every push
        // is attributable — the watch clears itself if a payload arrives for a
        // different (or no) account, and self-limits to personal surfaces for an
        // outsider. Written before currentWatchPayload() reads it.
        SharedDataStore.writeAccountStamp(userId: auth.session?.user.id.uuidString,
                                          isFamily: propertyService.isFamilyMember)
        // The watch renders the same state the widgets do — one push, in the
        // same breath as the snapshot write, so the two can never diverge.
        if let payload = SharedDataStore.currentWatchPayload() {
            WatchSyncService.shared.push(payload)
        }
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
        // Smart-home commands the watch queued (toggle relay / open garage) —
        // executed against the real device by IoTService.perform.
        IoTService.shared.drainPendingWatchCommands()
        // "Start emergency mode" pinned from the wrist — raise the real
        // Emergency Live Activity now that the app is foreground.
        if SharedDataStore.consumePendingEmergencyStart() {
            LiveActivityService.shared.startEmergency()
        }
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
        let chatReplies = SharedDataStore.popPendingChatReplies()
        for reply in chatReplies {
            if let propId = propertyService.primary?.id {
                let name = profileService.profile?.preferredName
                    ?? profileService.profile?.fullName ?? ""
                Task {
                    do {
                        try await messageService.send(propertyId: propId,
                                                      senderName: name, body: reply)
                    } catch {
                        // Never lose a notification quick-reply to a silent drop:
                        // requeue it so the next foreground beat retries, instead
                        // of the `try?` swallow the send pipeline removed elsewhere.
                        SharedDataStore.appendPendingChatReply(reply)
                    }
                }
            }
        }
        let watchTaskTitles = SharedDataStore.popPendingWatchTasks()
        for title in watchTaskTitles {
            if let propId = propertyService.primary?.id {
                Task {
                    try? await taskService.addTask(NewTaskPayload(
                        propertyId: propId, title: title, description: nil,
                        dueDate: nil, priority: "medium", category: "maintenance",
                        assigneeIds: [], assigneeNames: []))
                }
            }
        }
        let supplyIds = SharedDataStore.popPendingSupplyChecks()
        for id in supplyIds {
            if let item = supplyService.items.first(where: { $0.id == id }), !item.isCompleted {
                Task { await supplyService.toggleComplete(item) }
            }
        }
        // Deliveries marked received from the Live Activity island.
        let deliveredIds = SharedDataStore.popPendingDeliveryReceived()
        for id in deliveredIds {
            if let delivery = deliveryService.deliveries.first(where: { $0.id == id }),
               delivery.status != "delivered" {
                Task { await deliveryService.markDelivered(delivery) }
            }
        }
        // Wrist pantry consumption: every queued tap is one unit off the
        // stock. Taps on the same item collapse into ONE adjustment — two
        // separate adjust(-1) calls would both start from the same stale
        // quantity and lose a unit.
        let pantryConsumeIds = SharedDataStore.popPendingPantryConsumes()
        let consumeCounts = Dictionary(pantryConsumeIds.map { ($0, 1) }, uniquingKeysWith: +)
        for (id, count) in consumeCounts {
            if let item = pantryService.items.first(where: { $0.id == id }) {
                Task { await pantryService.adjust(item, by: -Double(count)) }
            }
        }
        // The watch's work session, mirrored into the Dynamic Island. This
        // runs on the foreground beat — exactly when the system allows a
        // Live Activity to start; the original start date keeps the elapsed
        // time truthful however late the mirror appears.
        if let event = SharedDataStore.consumePendingSessionEvent() {
            if let start = event.start {
                // Adopt the wrist-started session into the one authority so the
                // phone's banner/row timer light up with the true elapsed time;
                // start() also raises the Dynamic Island mirror.
                WorkSessionStore.shared.start(
                    taskId: start.taskId, title: start.title, startedAt: start.startedAt)
            } else if event.isEnd {
                // Finish from the wrist banks the time and completes the task.
                if let done = WorkSessionStore.shared.finish(),
                   let task = taskService.tasks.first(where: { $0.id == done.taskId }),
                   !task.isCompleted {
                    Task { await taskService.toggleComplete(task) }
                }
            }
        }
        if !waterIds.isEmpty || !completeIds.isEmpty || !supplyIds.isEmpty
            || !watchTaskTitles.isEmpty || !chatReplies.isEmpty || !pantryConsumeIds.isEmpty
            || !deliveredIds.isEmpty {
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

        // 4. Chat
        items.append(UIApplicationShortcutItem(
            type: "com.prvio.action.chat",
            localizedTitle: String(localized: "Chat"),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right.fill")
        ))

        UIApplication.shared.shortcutItems = items
    }
}

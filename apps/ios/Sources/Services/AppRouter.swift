import SwiftUI
import Observation

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    // Global quick-action presentations (handled at the MainTabView level).
    var showARIA = false
    var showAddTask = false
    var showFamilyChat = false
    var showAddExpense = false
    var showInventoryScan = false
    var showInventoryAdd = false
    var showInventoryView = false
    var showAddSupply = false
    var showWaterPlant = false
    var showSuppliesView = false
    var showDocuments = false
    var showFamily = false
    var showContractors = false
    var showFinances = false
    var showDeliveries = false
    var showPaintColors = false
    var showPhotoJournal = false
    var showProfile = false
    var showNotifications = false

    // Deep link destinations
    var deepLinkTaskId: UUID?
    var deepLinkPlantId: UUID?

    // MARK: - Single navigation authority
    //
    // Widgets, quick actions, notifications and deep links all funnel
    // through `navigate(to:)`. It closes whatever a previous entry point
    // left open, lets the dismissal settle, then presents the destination —
    // otherwise SwiftUI silently drops the second presentation and the tap
    // "does nothing".

    /// Every full-screen destination an external entry point can request.
    enum AppRoute: Equatable {
        case home, tasks(id: UUID?), newTask, plants(id: UUID?), supplies,
             deliveries, chat, scan, receipts, notifications, aria, twin,
             settings, documents, finances, inventory, family, profile
    }

    /// Bumped on every close-all — screens that own local sheets (Dashboard's
    /// search / notifications / health) observe it and dismiss theirs too.
    private(set) var dismissGeneration = 0

    /// Set by screens while one of their local sheets is up, so `navigate`
    /// knows a settle delay is needed even though no routed flag is active.
    var hasLocalPresentation = false

    private var anyPresentationActive: Bool {
        showARIA || showAddTask || showFamilyChat || showAddExpense ||
        showInventoryScan || showInventoryAdd || showInventoryView ||
        showAddSupply || showWaterPlant || showSuppliesView || showDocuments ||
        showFamily || showContractors || showFinances || showDeliveries ||
        showPaintColors || showPhotoJournal || showProfile || showNotifications ||
        hasLocalPresentation
    }

    /// Dismisses every routed presentation, so the next one has the stage.
    func closeAllPresentations() {
        showARIA = false; showAddTask = false; showFamilyChat = false
        showAddExpense = false; showInventoryScan = false; showInventoryAdd = false
        showInventoryView = false; showAddSupply = false; showWaterPlant = false
        showSuppliesView = false; showDocuments = false; showFamily = false
        showContractors = false; showFinances = false; showDeliveries = false
        showPaintColors = false; showPhotoJournal = false; showProfile = false
        showNotifications = false
        dismissGeneration &+= 1
    }

    func navigate(to route: AppRoute) {
        let mustSettle = anyPresentationActive
        closeAllPresentations()
        guard mustSettle else { apply(route); return }
        // A new sheet presented while the old one is still animating out is
        // dropped by SwiftUI — give the dismissal a beat to finish.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.apply(route)
        }
    }

    private func apply(_ route: AppRoute) {
        switch route {
        case .home:
            selectedTab = .home
        case .tasks(let id):
            selectedTab = .tasks
            deepLinkTaskId = id
        case .newTask:
            selectedTab = .tasks
            showAddTask = true
        case .plants(let id):
            selectedTab = .home
            deepLinkPlantId = id
            showWaterPlant = true
        case .supplies:
            selectedTab = .settings
            showSuppliesView = true
        case .deliveries:
            showDeliveries = true
        case .chat:
            selectedTab = .chat
        case .scan:
            showInventoryScan = true
        case .receipts:
            showAddExpense = true
        case .notifications:
            selectedTab = .home
            showNotifications = true
        case .aria:
            showARIA = true
        case .twin:
            selectedTab = .digitalTwin
        case .settings:
            selectedTab = .settings
        case .documents:
            showDocuments = true
        case .finances:
            showFinances = true
        case .inventory:
            showInventoryView = true
        case .family:
            showFamily = true
        case .profile:
            selectedTab = .settings
            showProfile = true
        }
    }

    func perform(_ action: DashboardQuickAction) {
        switch action {
        case .aria:       showARIA = true
        case .finances:   Task { try? await Task.sleep(for: .milliseconds(250)); self.selectedTab = .settings }
        case .newTask:    showAddTask = true
        case .chat:       showFamilyChat = true
        case .addExpense: showAddExpense = true
        case .scan:       showInventoryScan = true
        case .addItem:    showInventoryAdd = true
        case .addSupply:  showAddSupply = true
        case .waterPlant: showWaterPlant = true
        case .documents:  showDocuments = true
        case .deliveries: showDeliveries = true
        case .digitalTwin: selectedTab = .digitalTwin
        }
    }

    func handle(deepLink url: URL) {
        guard url.scheme == "prvio" else { return }
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let pathId = pathComponents.first.flatMap(UUID.init(uuidString:))
        switch host {
        case "", "home", "dashboard":
            navigate(to: .home)
        case "tasks":
            navigate(to: pathComponents.first == "new" ? .newTask : .tasks(id: pathId))
        case "plants":
            navigate(to: .plants(id: pathId))
        case "shopping", "supplies":
            navigate(to: .supplies)
        case "deliveries", "packages":
            navigate(to: .deliveries)
        case "chat":
            navigate(to: .chat)
        case "scan":
            navigate(to: .scan)
        case "receipts":
            navigate(to: .receipts)
        case "alerts", "notifications":
            navigate(to: .notifications)
        case "aria", "ai":
            navigate(to: .aria)
        case "twin", "map":
            navigate(to: .twin)
        case "settings":
            navigate(to: .settings)
        case "documents":
            navigate(to: .documents)
        case "finances":
            navigate(to: .finances)
        case "inventory":
            navigate(to: .inventory)
        case "family", "members":
            navigate(to: .family)
        case "profile":
            navigate(to: .profile)
        default:
            break
        }
    }

    /// Routes a tapped in-app notification to the thing it's about.
    /// Prefers the typed module + resource id; falls back to parsing the
    /// action_url path the DB triggers write ("/maintenance/<id>", …).
    func handle(notificationModule module: String?, actionUrl: String?, resourceId: UUID?) {
        let id = resourceId ?? Self.firstUUID(in: actionUrl ?? "")
        switch module ?? "" {
        case "chat":                    navigate(to: .chat)
        case "maintenance", "tasks":    navigate(to: .tasks(id: id))
        case "garden", "plants":        navigate(to: .plants(id: id))
        case "documents", "document":   navigate(to: .documents)
        case "inventory":               navigate(to: .inventory)
        case "finance", "finances":     navigate(to: .finances)
        case "delivery", "deliveries":  navigate(to: .deliveries)
        case "family", "members":       navigate(to: .family)
        case "aria":                    navigate(to: .aria)
        case "security":                navigate(to: .settings)
        default:                        navigate(to: .home)
        }
    }

    private static func firstUUID(in path: String) -> UUID? {
        path.split(separator: "/").lazy.compactMap { UUID(uuidString: String($0)) }.first
    }

    func handle(quickActionType type: String) {
        // "opentask" carries the task id in the type string ("…opentask:<uuid>")
        // because userInfo doesn't survive the cold-launch UserDefaults hand-off.
        if type.hasPrefix("com.prvio.action.opentask") {
            let id = type.split(separator: ":").last.flatMap { UUID(uuidString: String($0)) }
            navigate(to: .tasks(id: id))
            return
        }
        switch type {
        case "com.prvio.action.addtask":    navigate(to: .newTask)
        case "com.prvio.action.plants":     navigate(to: .plants(id: nil))
        case "com.prvio.action.shopping":
            // The list, not the add-item form — the shortcut says "Shopping List".
            navigate(to: .supplies)
        case "com.prvio.action.deliveries": navigate(to: .deliveries)
        case "com.prvio.action.chat":       navigate(to: .chat)
        case "com.prvio.action.scan":       navigate(to: .scan)
        default: break
        }
    }

    func handle(userActivity activity: NSUserActivity) {
        if activity.activityType == "CSSearchableItemActionType" {
            guard let id = activity.userInfo?["kCSSearchableItemActivityIdentifier"] as? String else { return }
            if id.hasPrefix("task-"), let uuid = UUID(uuidString: String(id.dropFirst(5))) {
                navigate(to: .tasks(id: uuid))
            } else if id.hasPrefix("plant-"), let uuid = UUID(uuidString: String(id.dropFirst(6))) {
                navigate(to: .plants(id: uuid))
            }
        } else if let tab = activity.userInfo?["tab"] as? String {
            switch tab {
            case "tasks": navigate(to: .tasks(id: nil))
            case "chat":  navigate(to: .chat)
            default: break
            }
        }
    }
}

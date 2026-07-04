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

    // Deep link destinations
    var deepLinkTaskId: UUID?
    var deepLinkPlantId: UUID?

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
        switch host {
        case "", "home", "dashboard":
            selectedTab = .home
        case "tasks":
            selectedTab = .tasks
            if pathComponents.first == "new" {
                showAddTask = true
            } else if let idStr = pathComponents.first, let id = UUID(uuidString: idStr) {
                deepLinkTaskId = id
            }
        case "plants":
            selectedTab = .home
            showWaterPlant = true
            if let idStr = pathComponents.first, let id = UUID(uuidString: idStr) {
                deepLinkPlantId = id
            }
        case "shopping", "supplies":
            selectedTab = .settings
            showSuppliesView = true
        case "deliveries", "packages":
            showDeliveries = true
        case "chat":
            selectedTab = .chat
        case "scan":
            showInventoryScan = true
        case "receipts":
            showAddExpense = true
        case "alerts", "notifications":
            selectedTab = .home
        case "aria", "ai":
            showARIA = true
        case "twin", "map":
            selectedTab = .digitalTwin
        case "settings":
            selectedTab = .settings
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
        case "chat":
            selectedTab = .chat
        case "maintenance":
            selectedTab = .tasks
            deepLinkTaskId = id
        case "garden":
            selectedTab = .home
            showWaterPlant = true
            deepLinkPlantId = id
        case "documents", "document":
            showDocuments = true
        case "inventory":
            showInventoryView = true
        case "finance":
            showFinances = true
        case "delivery", "deliveries":
            showDeliveries = true
        case "family":
            showFamily = true
        case "aria":
            showARIA = true
        case "security":
            selectedTab = .settings
        default:
            selectedTab = .home
        }
    }

    private static func firstUUID(in path: String) -> UUID? {
        path.split(separator: "/").lazy.compactMap { UUID(uuidString: String($0)) }.first
    }

    func handle(quickActionType type: String) {
        // "opentask" carries the task id in the type string ("…opentask:<uuid>")
        // because userInfo doesn't survive the cold-launch UserDefaults hand-off.
        if type.hasPrefix("com.prvio.action.opentask") {
            selectedTab = .tasks
            if let idStr = type.split(separator: ":").last, let id = UUID(uuidString: String(idStr)) {
                deepLinkTaskId = id
            }
            return
        }
        switch type {
        case "com.prvio.action.addtask":    showAddTask = true
        case "com.prvio.action.plants":     showWaterPlant = true
        case "com.prvio.action.shopping":
            // The list, not the add-item form — the shortcut says "Shopping List".
            selectedTab = .settings
            showSuppliesView = true
        case "com.prvio.action.deliveries": showDeliveries = true
        case "com.prvio.action.chat":       selectedTab = .chat
        case "com.prvio.action.scan":       showInventoryScan = true
        default: break
        }
    }

    func handle(userActivity activity: NSUserActivity) {
        if activity.activityType == "CSSearchableItemActionType" {
            guard let id = activity.userInfo?["kCSSearchableItemActivityIdentifier"] as? String else { return }
            if id.hasPrefix("task-"), let uuid = UUID(uuidString: String(id.dropFirst(5))) {
                selectedTab = .tasks
                deepLinkTaskId = uuid
            } else if id.hasPrefix("plant-"), let uuid = UUID(uuidString: String(id.dropFirst(6))) {
                deepLinkPlantId = uuid
                showWaterPlant = true
            }
        } else if let tab = activity.userInfo?["tab"] as? String {
            switch tab {
            case "tasks": selectedTab = .tasks
            case "chat":  selectedTab = .chat
            default: break
            }
        }
    }
}

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

    func handle(quickActionType type: String) {
        switch type {
        case "com.prvio.action.addtask":  showAddTask = true
        case "com.prvio.action.plants":   showWaterPlant = true
        case "com.prvio.action.shopping": showAddSupply = true
        case "com.prvio.action.chat":     selectedTab = .chat
        case "com.prvio.action.scan":     showInventoryScan = true
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

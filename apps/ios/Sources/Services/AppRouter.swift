import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .home

    // Global quick-action presentations (handled at the MainTabView level).
    @Published var showARIA = false
    @Published var showAddTask = false
    @Published var showChat = false
    @Published var showAddExpense = false
    @Published var showInventoryScan = false
    @Published var showInventoryAdd = false
    @Published var showAddSupply = false
    @Published var showWaterPlant = false

    // Deep link destinations
    @Published var deepLinkTaskId: UUID?
    @Published var deepLinkPlantId: UUID?

    func perform(_ action: DashboardQuickAction) {
        switch action {
        case .aria:       showARIA = true
        case .finances:   DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.selectedTab = .analytics }
        case .newTask:    showAddTask = true
        case .chat:       showChat = true
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
        case "tasks":
            selectedTab = .tasks
            if pathComponents.first == "new" {
                showAddTask = true
            } else if let idStr = pathComponents.first, let id = UUID(uuidString: idStr) {
                deepLinkTaskId = id
            }
        case "plants":
            showWaterPlant = true
            if let idStr = pathComponents.first, let id = UUID(uuidString: idStr) {
                deepLinkPlantId = id
            }
        case "shopping", "supplies":
            break
        case "chat":
            showChat = true
        case "scan":
            showInventoryScan = true
        case "receipts":
            showAddExpense = true
        default:
            break
        }
    }

    func handle(quickActionType type: String) {
        switch type {
        case "com.prvio.action.addtask":  showAddTask = true
        case "com.prvio.action.plants":   showWaterPlant = true
        case "com.prvio.action.shopping": showAddSupply = true
        case "com.prvio.action.chat":     showChat = true
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
            case "tasks":     selectedTab = .tasks
            case "analytics": selectedTab = .analytics
            default: break
            }
        }
    }
}

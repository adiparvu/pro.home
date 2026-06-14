import SwiftUI

/// App-wide navigation/coordination so any page's floating button can
/// perform any quick action (switch tabs, present global sheets).
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

    func perform(_ action: DashboardQuickAction) {
        switch action {
        case .aria:
            showARIA = true
        case .finances:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.selectedTab = .analytics }
        case .newTask:
            showAddTask = true
        case .chat:
            showChat = true
        case .addExpense:
            showAddExpense = true
        case .scan:
            showInventoryScan = true
        case .addItem:
            showInventoryAdd = true
        }
    }
}

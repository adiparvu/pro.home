import AppIntents

struct PRVIOShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Create task in \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "New task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: WaterPlantIntent(),
            phrases: [
                "Water plant in \(.applicationName)",
                "Mark plant as watered in \(.applicationName)"
            ],
            shortTitle: "Water plants",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: OpenShoppingListIntent(),
            phrases: [
                "Open shopping list in \(.applicationName)",
                "Shopping list in \(.applicationName)"
            ],
            shortTitle: "Shopping",
            systemImageName: "cart.fill"
        )
        AppShortcut(
            intent: OpenChatIntent(),
            phrases: [
                "Open family chat in \(.applicationName)",
                "Family chat in \(.applicationName)"
            ],
            shortTitle: "Family chat",
            systemImageName: "message.fill"
        )
    }
}

import AppIntents

struct PRVIOShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Create task in \(.applicationName)",
                "New task in \(.applicationName)",
                "Adaugă sarcină în \(.applicationName)",
                "Sarcină nouă în \(.applicationName)"
            ],
            shortTitle: "New task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: WaterPlantIntent(),
            phrases: [
                "Water plant in \(.applicationName)",
                "Udă planta în \(.applicationName)",
                "Marchează udat în \(.applicationName)"
            ],
            shortTitle: "Water plants",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: OpenShoppingListIntent(),
            phrases: [
                "Open shopping list in \(.applicationName)",
                "Deschide cumpărăturile în \(.applicationName)",
                "Listă cumpărături în \(.applicationName)"
            ],
            shortTitle: "Shopping",
            systemImageName: "cart.fill"
        )
        AppShortcut(
            intent: OpenChatIntent(),
            phrases: [
                "Open family chat in \(.applicationName)",
                "Deschide chat-ul în \(.applicationName)",
                "Chat familie în \(.applicationName)"
            ],
            shortTitle: "Family chat",
            systemImageName: "message.fill"
        )
    }
}

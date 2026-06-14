import AppIntents

struct PRVIOShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Create task in \(.applicationName)",
                "Adaugă sarcină în \(.applicationName)",
                "Sarcină nouă în \(.applicationName)"
            ],
            shortTitle: "Sarcină nouă",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: WaterPlantIntent(),
            phrases: [
                "Water plant in \(.applicationName)",
                "Udă planta în \(.applicationName)",
                "Marchează udat în \(.applicationName)"
            ],
            shortTitle: "Udă plante",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: OpenShoppingListIntent(),
            phrases: [
                "Open shopping list in \(.applicationName)",
                "Deschide cumpărăturile în \(.applicationName)",
                "Listă cumpărături \(.applicationName)"
            ],
            shortTitle: "Cumpărături",
            systemImageName: "cart.fill"
        )
        AppShortcut(
            intent: OpenChatIntent(),
            phrases: [
                "Open family chat in \(.applicationName)",
                "Deschide chat-ul în \(.applicationName)",
                "Chat familie \(.applicationName)"
            ],
            shortTitle: "Chat familie",
            systemImageName: "message.fill"
        )
    }
}

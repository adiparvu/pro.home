import AppIntents

// All phrases are written in English (the catalog keys) and localized to
// Romanian in Resources/AppShortcuts.xcstrings — without that catalog Siri
// only matched the literal strings below, so a Romanian device couldn't
// invoke most shortcuts by voice.
struct PRVIOShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PRVIOActionButtonIntent(),
            phrases: [
                "Quick action in \(.applicationName)",
                "Run my \(.applicationName) action"
            ],
            shortTitle: "PRVIO Quick Action",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Create task in \(.applicationName)",
                "New task in \(.applicationName)",
                "Add task in \(.applicationName)"
            ],
            shortTitle: "New Task",
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
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete task in \(.applicationName)",
                "Mark task done in \(.applicationName)"
            ],
            shortTitle: "Complete task",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: CheckSupplyItemIntent(),
            phrases: [
                "Check off item in \(.applicationName)",
                "Mark item as bought in \(.applicationName)"
            ],
            shortTitle: "Check off item",
            systemImageName: "cart.badge.minus"
        )
        AppShortcut(
            intent: ShowPlantsIntent(),
            phrases: [
                "Open plants in \(.applicationName)",
                "Show plants in \(.applicationName)"
            ],
            shortTitle: "Open Plants",
            systemImageName: "leaf.fill"
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
                "Open chat in \(.applicationName)",
                "Chat in \(.applicationName)"
            ],
            shortTitle: "Chat",
            systemImageName: "message.fill"
        )
        AppShortcut(
            intent: OpenDashboardIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open \(.applicationName) home",
                "Show \(.applicationName) dashboard"
            ],
            shortTitle: "Open PRVIO",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: AskARIAIntent(),
            phrases: [
                "Ask ARIA in \(.applicationName)",
                "Open AI assistant in \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Ask ARIA",
            systemImageName: "sparkles"
        )
    }
}

// MARK: - Open Dashboard Intent

struct OpenDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Dashboard"
    static var description = IntentDescription("Opens the PRVIO home dashboard")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.setIntentFlag("prvio.intent.openDashboard")
        return .result()
    }
}

// MARK: - Ask ARIA Intent

struct AskARIAIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask ARIA"
    static var description = IntentDescription("Opens the PRVIO AI assistant")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.setIntentFlag("prvio.intent.openARIA")
        return .result()
    }
}

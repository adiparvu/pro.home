import AppIntents

// MARK: - PRVIO App Shortcuts
// Donates intents to Siri, Spotlight, and the iOS Smart Stack widget suggestion engine.
// The system uses these to proactively surface the relevant widget at the right moment.

struct PRVIOAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Create a task in \(.applicationName)",
                "New task in \(.applicationName)",
                "Add task in \(.applicationName)"
            ],
            shortTitle: "New Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: ShowPlantsIntent(),
            phrases: [
                "Open plants in \(.applicationName)",
                "Check plants in \(.applicationName)",
                "Show plants in \(.applicationName)"
            ],
            shortTitle: "Open Plants",
            systemImageName: "leaf.fill"
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
        UserDefaults.standard.set(true, forKey: "prvio.intent.openDashboard")
        return .result()
    }
}

// MARK: - Ask ARIA Intent

struct AskARIAIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask ARIA"
    static var description = IntentDescription("Opens the PRVIO AI assistant")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "prvio.intent.openARIA")
        return .result()
    }
}

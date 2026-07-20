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
        // Note: Apple caps a provider at 10 App Shortcuts. The garage control
        // takes the slot the redundant "Open PRVIO dashboard" phrase held —
        // tapping the app icon already opens the dashboard, and OpenDashboard-
        // Intent remains usable from the Shortcuts app.
        AppShortcut(
            intent: OpenGarageIntent(),
            phrases: [
                "Open the garage in \(.applicationName)",
                "\(.applicationName) open the garage",
                "Open the gate in \(.applicationName)"
            ],
            shortTitle: "Open Garage",
            systemImageName: "door.garage.open"
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

// MARK: - Siri: open the garage
//
// Lives here in the app-only shortcuts file, NOT in ControlIntents.swift —
// that file is also compiled into the widget extension, which does not link
// IoTService, so referencing it there breaks the extension build. "Hey Siri,
// open the garage" resolves the first cover actuator in the user's own smart
// home and issues the real open command through the same IoTService.perform
// the app and watch use. No cover configured → an honest spoken "nothing to
// open", never a fake success.

struct OpenGarageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the garage"
    static let description = IntentDescription(
        "Opens the first garage or gate in your PRVIO smart home.")
    // The device write is a network call — it doesn't need the app on screen.
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let covers = IoTService.shared.actuators.filter { $0.kind == .cover }
        guard let cover = covers.first else {
            return .result(dialog: "There's no garage or gate set up in PRVIO.")
        }
        IoTService.shared.perform(.open, on: cover)
        return .result(dialog: "Opening \(cover.name).")
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

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - The one control launch intent
//
// Control Center buttons run in the widget extension. A bare `OpenURLIntent`
// as the button action has proven unreliable at actually launching the app
// on newer iOS — the documented pattern is an intent that declares
// `openAppWhenRun` and RETURNS an OpenURLIntent, which the system executes
// in the app's context. One intent, parameterized by destination, backs
// every control.

@available(iOS 18.0, *)
struct OpenPRVIODestination: AppIntent {
    static let title: LocalizedStringResource = "Open PRVIO"
    static let openAppWhenRun: Bool = true
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Destination")
    var path: String?

    init() {}
    init(path: String?) { self.path = path }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "prvio://\(path ?? "")") ?? URL(string: "prvio://")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Open App Control

@available(iOS 18.0, *)
struct OpenAppControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.open") {
            ControlWidgetButton(action: OpenPRVIODestination(path: nil)) {
                Label("PRVIO", systemImage: "house.fill")
            }
        }
        .displayName("PRVIO")
        .description("Open PRVIO.")
    }
}

// MARK: - Add Task Control

@available(iOS 18.0, *)
struct AddTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.addtask") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "tasks/new")) {
                Label("New Task", systemImage: "checklist.checked")
            }
        }
        .displayName("New Task")
        .description("Quickly add a new task in PRVIO.")
    }
}

// MARK: - Open Chat Control

@available(iOS 18.0, *)
struct OpenChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.chat") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "chat")) {
                Label("Chat", systemImage: "message.fill")
            }
        }
        .displayName("Chat")
        .description("Open the chat in PRVIO.")
    }
}

// MARK: - Shopping List Control

@available(iOS 18.0, *)
struct ShoppingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.shopping") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "shopping")) {
                Label("Shopping", systemImage: "cart.fill")
            }
        }
        .displayName("Shopping")
        .description("Open the shopping list in PRVIO.")
    }
}

// MARK: - Scan Receipt Control

@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.scan") {
            // prvio://receipts opens the expense/receipt capture flow —
            // prvio://scan would open the inventory object scanner instead.
            ControlWidgetButton(action: OpenPRVIODestination(path: "receipts")) {
                Label("Scan Receipt", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scan Receipt")
        .description("Quickly scan a receipt in PRVIO.")
    }
}

// MARK: - My Plants Control

@available(iOS 18.0, *)
struct PlantsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.plants") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "plants")) {
                Label("My Plants", systemImage: "leaf.fill")
            }
        }
        .displayName("My Plants")
        .description("Open your plants in PRVIO.")
    }
}

// MARK: - Deliveries Control

@available(iOS 18.0, *)
struct DeliveriesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.deliveries") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "deliveries")) {
                Label("Deliveries", systemImage: "shippingbox.fill")
            }
        }
        .displayName("Deliveries")
        .description("Open your deliveries in PRVIO.")
    }
}

// MARK: - Finances Control

@available(iOS 18.0, *)
struct FinancesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.finances") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "finances")) {
                Label("Finances", systemImage: "chart.pie.fill")
            }
        }
        .displayName("Finances")
        .description("Open your finances in PRVIO.")
    }
}

// MARK: - Documents Control

@available(iOS 18.0, *)
struct DocumentsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.documents") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "documents")) {
                Label("Documents", systemImage: "folder.fill")
            }
        }
        .displayName("Documents")
        .description("Open your documents in PRVIO.")
    }
}

// MARK: - Digital Twin Control

@available(iOS 18.0, *)
struct DigitalTwinControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.twin") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "twin")) {
                Label("Digital Twin", systemImage: "square.stack.3d.up.fill")
            }
        }
        .displayName("Digital Twin")
        .description("Open the property map in PRVIO.")
    }
}

// MARK: - Assistant Control

@available(iOS 18.0, *)
struct AssistantControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.aria") {
            ControlWidgetButton(action: OpenPRVIODestination(path: "ai")) {
                Label("AI Assistant", systemImage: "sparkles")
            }
        }
        .displayName("AI Assistant")
        .description("Ask your assistant in PRVIO.")
    }
}

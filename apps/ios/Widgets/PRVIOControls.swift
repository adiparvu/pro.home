import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Control Center launch plumbing
//
// Control Center buttons run in the widget extension, and history here is
// littered with approaches that LOOKED right and didn't launch anything on
// device: a bare OpenURLIntent, then openAppWhenRun + .result(opensIntent:).
// The mechanism Apple actually documents for controls that open the app is
// an `OpenIntent` whose `target` is an AppEnum — the SYSTEM performs the
// launch, no flags involved. Routing stays on the App Group hand-off the
// widget buttons already use (drained on every activation, deduped in the
// router), so the destination survives even a cold start.

@available(iOS 18.0, *)
enum PRVIODestination: String, AppEnum {
    case home, newTask, chat, shopping, receipts, plants,
         deliveries, finances, documents, twin, aria

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PRVIO Destination"

    static let caseDisplayRepresentations: [PRVIODestination: DisplayRepresentation] = [
        .home:       "PRVIO",
        .newTask:    "New Task",
        .chat:       "Chat",
        .shopping:   "Shopping",
        .receipts:   "Scan Receipt",
        .plants:     "My Plants",
        .deliveries: "Deliveries",
        .finances:   "Finances",
        .documents:  "Documents",
        .twin:       "Digital Twin",
        .aria:       "AI Assistant",
    ]

    /// The prvio:// host/path the router resolves.
    var path: String {
        switch self {
        case .home:       return ""
        case .newTask:    return "tasks/new"
        case .chat:       return "chat"
        case .shopping:   return "shopping"
        case .receipts:   return "receipts"
        case .plants:     return "plants"
        case .deliveries: return "deliveries"
        case .finances:   return "finances"
        case .documents:  return "documents"
        case .twin:       return "twin"
        case .aria:       return "ai"
        }
    }
}

@available(iOS 18.0, *)
struct OpenPRVIODestination: OpenIntent {
    static let title: LocalizedStringResource = "Open PRVIO"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Destination")
    var target: PRVIODestination

    init() {
        target = .home
    }

    init(_ destination: PRVIODestination) {
        target = destination
    }

    func perform() async throws -> some IntentResult {
        // The system opens the app (OpenIntent semantics); we only park where
        // it should land. Drained on activation, deduped in the router.
        SharedDataStore.setControlPath(target.path)
        return .result()
    }
}

// MARK: - Open App Control

@available(iOS 18.0, *)
struct OpenAppControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.open") {
            ControlWidgetButton(action: OpenPRVIODestination(.home)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.newTask)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.chat)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.shopping)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.receipts)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.plants)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.deliveries)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.finances)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.documents)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.twin)) {
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
            ControlWidgetButton(action: OpenPRVIODestination(.aria)) {
                Label("AI Assistant", systemImage: "sparkles")
            }
        }
        .displayName("AI Assistant")
        .description("Ask your assistant in PRVIO.")
    }
}

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Add Task Control

@available(iOS 18.0, *)
struct AddTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.addtask") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://tasks/new")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://chat")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://shopping")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://receipts")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://plants")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://deliveries")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://finances")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://documents")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://twin")!)) {
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
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://ai")!)) {
                Label("AI Assistant", systemImage: "sparkles")
            }
        }
        .displayName("AI Assistant")
        .description("Ask your assistant in PRVIO.")
    }
}

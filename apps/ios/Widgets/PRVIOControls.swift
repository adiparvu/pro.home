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

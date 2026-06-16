import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Add Task Control

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

struct OpenChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.chat") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://chat")!)) {
                Label("Family Chat", systemImage: "message.fill")
            }
        }
        .displayName("Family Chat")
        .description("Open the family chat in PRVIO.")
    }
}

// MARK: - Shopping List Control

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

struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.scan") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "prvio://scan")!)) {
                Label("Scan Receipt", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scan Receipt")
        .description("Quickly scan a receipt in PRVIO.")
    }
}

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Add Task Control

struct AddTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.addtask") {
            ControlWidgetButton(action: OpenURLIntent(url: URL(string: "prvio://tasks/new")!)) {
                Label("Sarcină nouă", systemImage: "checklist.checked")
            }
        }
        .displayName("Sarcină nouă")
        .description("Adaugă rapid o sarcină nouă în PRVIO.")
    }
}

// MARK: - Open Chat Control

struct OpenChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.chat") {
            ControlWidgetButton(action: OpenURLIntent(url: URL(string: "prvio://chat")!)) {
                Label("Chat familie", systemImage: "message.fill")
            }
        }
        .displayName("Chat familie")
        .description("Deschide chat-ul familiei în PRVIO.")
    }
}

// MARK: - Shopping List Control

struct ShoppingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.shopping") {
            ControlWidgetButton(action: OpenURLIntent(url: URL(string: "prvio://shopping")!)) {
                Label("Cumpărături", systemImage: "cart.fill")
            }
        }
        .displayName("Cumpărături")
        .description("Deschide lista de cumpărături în PRVIO.")
    }
}

// MARK: - Scan Receipt Control

struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.scan") {
            ControlWidgetButton(action: OpenURLIntent(url: URL(string: "prvio://scan")!)) {
                Label("Scanează bon", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scanează bon")
        .description("Scanează rapid un bon de casă în PRVIO.")
    }
}

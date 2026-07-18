import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Open App Control

@available(iOS 18.0, *)
struct OpenAppControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.prvio.control.open") {
            ControlWidgetButton(action: OpenPRVIODestination(.home)) {
                // Control Center controls only render SF Symbols, not the raster
                // brand mark (which showed the system's broken-image "?"). Per
                // the owner's call: text only, no generic-house glyph. A branded
                // glyph here would need a custom SF Symbol (.symbolset from SVG).
                Text("PRVIO")
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

// MARK: - Smart Device Toggle (real state, configurable — iOS 18)
//
// Unlike every launch-button control above, this one is BOUND to a device:
// long-press Control Center → configure → pick any relay from the same
// actuator catalog the watch face reads. The provider reports the device's
// current on/off, and the toggle flips it through the wrist's own pending
// pipeline (optimistic echo now, real device write on the app's next beat).

@available(iOS 18.0, *)
struct ActuatorToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.prvio.control.device",
                                      provider: ActuatorControlProvider()) { value in
            ControlWidgetToggle(value.name,
                                isOn: value.isOn,
                                action: ToggleActuatorIntent(actuator: value.entity)) { isOn in
                Label(isOn ? "On" : "Off",
                      systemImage: isOn ? "power.circle.fill" : "power.circle")
            }
        }
        .displayName("Smart Device")
        .description("Toggle a PRVIO smart device.")
    }
}

@available(iOS 18.0, *)
struct ActuatorControlProvider: AppIntentControlValueProvider {
    struct Value {
        var name: String
        var isOn: Bool
        var entity: ActuatorEntity?
    }

    func previousValue(configuration: SelectActuatorControlIntent) -> Value {
        resolve(configuration)
    }

    func currentValue(configuration: SelectActuatorControlIntent) async throws -> Value {
        resolve(configuration)
    }

    /// The chosen relay's live catalog row; the first relay when none is
    /// configured; an honest inert placeholder when the home has no relays.
    private func resolve(_ configuration: SelectActuatorControlIntent) -> Value {
        let relays = SharedDataStore.readActuatorCatalog().filter { $0.kind == "relay" }
        let chosen = configuration.actuator
            .flatMap { selected in relays.first { $0.id == selected.id } }
            ?? relays.first
        guard let chosen else {
            return Value(name: String(localized: "control_no_device"), isOn: false, entity: nil)
        }
        return Value(name: chosen.name,
                     isOn: chosen.isOn ?? false,
                     entity: ActuatorEntity(id: chosen.id, name: chosen.name))
    }
}

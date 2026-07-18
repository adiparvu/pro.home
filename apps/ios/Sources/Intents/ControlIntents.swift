import AppIntents
import Foundation

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

// MARK: - Actuator toggle (real state in Control Center, iOS 18)
//
// The flagship ControlWidget capability: a toggle BOUND to a device's real
// on/off state, not a launch button. The entity list is the same actuator
// catalog the watch face reads (App Group); flipping the toggle parks the
// command on the exact pending pipeline the wrist uses (drained on the
// app's next active beat) and echoes the state optimistically so Control
// Center reflects the tap instantly.

@available(iOS 18.0, *)
struct ActuatorEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Smart Device")
    static let defaultQuery = ActuatorEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 18.0, *)
struct ActuatorEntityQuery: EntityQuery {
    /// Only relays make honest toggles; covers speak open/close/stop.
    private func relays() -> [ActuatorEntity] {
        SharedDataStore.readActuatorCatalog()
            .filter { $0.kind == "relay" }
            .map { ActuatorEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [UUID]) async throws -> [ActuatorEntity] {
        relays().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ActuatorEntity] {
        relays()
    }

    func defaultResult() async -> ActuatorEntity? {
        relays().first
    }
}

@available(iOS 18.0, *)
struct SelectActuatorControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Select Device"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Device")
    var actuator: ActuatorEntity?
}

@available(iOS 18.0, *)
struct ToggleActuatorIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Device"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Device")
    var actuator: ActuatorEntity?

    @Parameter(title: "On")
    var value: Bool

    init() {}

    init(actuator: ActuatorEntity?) {
        self.actuator = actuator
    }

    func perform() async throws -> some IntentResult {
        guard let actuator else { return .result() }
        // Same contract as a wrist toggle: park the real command for the
        // app's next active beat, echo the state so the control reads true
        // to the tap right away.
        SharedDataStore.appendPendingIoTCommand(actuatorId: actuator.id,
                                                command: value ? "on" : "off")
        SharedDataStore.applyLocalActuatorState(id: actuator.id, isOn: value)
        return .result()
    }
}

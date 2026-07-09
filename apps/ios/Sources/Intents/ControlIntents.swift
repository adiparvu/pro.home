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

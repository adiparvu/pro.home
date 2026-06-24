import AppIntents
import SwiftUI

// MARK: - Action Button (Side Button) — iPhone 15 Pro / 16 series
// Registered as the shortcut for the programmable Action Button.

struct PRVIOActionButtonIntent: AppIntent {
    static var title: LocalizedStringResource = "Open PRVIO Quick Action"
    static var description = IntentDescription("Opens the PRVIO quick action selector for instant access to tasks, plants, and AI assistant.")

    static var openAppWhenRun: Bool = true

    // The action the user configured in Settings → Action Button
    @Parameter(title: "Action", default: .addTask)
    var action: ActionButtonActionType

    @MainActor
    func perform() async throws -> some IntentResult {
        switch action {
        case .addTask:
            NotificationCenter.default.post(name: .actionButtonAddTask, object: nil)
        case .waterPlants:
            NotificationCenter.default.post(name: .actionButtonWaterPlants, object: nil)
        case .openARIA:
            NotificationCenter.default.post(name: .actionButtonOpenARIA, object: nil)
        case .scanNFC:
            NotificationCenter.default.post(name: .actionButtonScanNFC, object: nil)
        case .openDigitalTwin:
            NotificationCenter.default.post(name: .actionButtonOpenDigitalTwin, object: nil)
        }
        return .result()
    }
}

enum ActionButtonActionType: String, AppEnum {
    case addTask
    case waterPlants
    case openARIA
    case scanNFC
    case openDigitalTwin

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "PRVIO Action"
    static var caseDisplayRepresentations: [ActionButtonActionType: DisplayRepresentation] = [
        .addTask:         .init(title: "Add Task",           image: .init(systemName: "plus.circle.fill")),
        .waterPlants:     .init(title: "Water Plants",       image: .init(systemName: "drop.fill")),
        .openARIA:        .init(title: "Open AI Assistant",  image: .init(systemName: "sparkles")),
        .scanNFC:         .init(title: "Scan NFC Tag",       image: .init(systemName: "wave.3.right")),
        .openDigitalTwin: .init(title: "Digital Twin",       image: .init(systemName: "square.3.layers.3d")),
    ]
}

// MARK: - Notification names for Action Button routing

extension Notification.Name {
    static let actionButtonAddTask       = Notification.Name("prvio.actionButton.addTask")
    static let actionButtonWaterPlants   = Notification.Name("prvio.actionButton.waterPlants")
    static let actionButtonOpenARIA      = Notification.Name("prvio.actionButton.openARIA")
    static let actionButtonScanNFC       = Notification.Name("prvio.actionButton.scanNFC")
    static let actionButtonOpenDigitalTwin = Notification.Name("prvio.actionButton.openDigitalTwin")
}

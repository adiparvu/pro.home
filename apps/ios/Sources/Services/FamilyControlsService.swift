import Foundation
import FamilyControls
import ManagedSettings
import Combine

@MainActor
final class FamilyControlsService: ObservableObject {
    static let shared = FamilyControlsService()

    @Published var isAuthorized = false
    @Published var authorizationStatus: FamilyControls.AuthorizationStatus = .notDetermined

    private let center = AuthorizationCenter.shared
    private let store = ManagedSettingsStore()

    private init() {
        authorizationStatus = center.authorizationStatus
        isAuthorized = center.authorizationStatus == .approved
    }

    // Request Family Controls authorization (requires device with managed child account)
    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(for: .individual)
            isAuthorized = true
            authorizationStatus = .approved
        } catch {
            isAuthorized = false
            authorizationStatus = .denied
        }
    }

    func revokeAuthorization() {
        center.revokeAuthorization { _ in }
        isAuthorized = false
        authorizationStatus = .notDetermined
    }

    // MARK: - App restrictions (example: lock destructive actions)

    func lockDestructiveActions() {
        guard isAuthorized else { return }
        // TODO: Apply ManagedSettingsStore restrictions to prevent child accounts
        // from deleting zones, documents, and other critical data.
        // Requires ActivitySelection UI (a system picker) which must be triggered
        // from an explicit user action — cannot run silently in the background.
        // store.application.blockedApplications = selectedApps
    }
}

import Foundation
import FamilyControls
import ManagedSettings
import Combine

@MainActor
final class FamilyControlsService: ObservableObject {
    static let shared = FamilyControlsService()

    @Published var isAuthorized = false
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined

    private let center = AuthorizationCenter.shared
    private let store = ManagedSettingsStore()

    private init() {
        authorizationStatus = center.authorizationStatus
        isAuthorized = center.authorizationStatus == .approved
    }

    enum AuthorizationStatus {
        case notDetermined, approved, denied
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
        // In a real implementation, use ActivitySelection + ManagedSettings
        // to prevent deletion of zones, documents, etc. for child accounts.
        // The ManagedSettingsStore controls what apps and content are accessible.
    }
}

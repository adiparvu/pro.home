import Foundation
import HomeKit
import Observation

@MainActor
@Observable
final class HomeKitService: NSObject {
    static let shared = HomeKitService()

    var homes: [HMHome] = []
    var accessories: [HMAccessory] = []
    var isAuthorized = false
    var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined

    private var _manager: HMHomeManager?

    // Lazily resolved only after requestAccess() — avoids triggering the HomeKit
    // permission dialog when the provisioning profile lacks the HomeKit capability.
    private var manager: HMHomeManager {
        if let m = _manager { return m }
        let m = HMHomeManager()
        m.delegate = self
        _manager = m
        return m
    }

    private override init() {
        super.init()
    }

    var primaryHome: HMHome? {
        // HMHomeManager.primaryHome was deprecated (iOS 16.1) with no
        // replacement; use the first configured home instead.
        _manager?.homes.first
    }

    func requestAccess() {
        _ = manager.homes
    }

    var currentAuthorizationStatus: Bool {
        isAuthorized
    }

    func allAccessories() -> [HMAccessory] {
        manager.homes.flatMap(\.accessories)
    }

    func accessories(ofCategory category: HMAccessoryCategory) -> [HMAccessory] {
        allAccessories().filter { $0.category.categoryType == category.categoryType }
    }

    // Returns on/off state for a lightbulb or switch
    func isOn(_ accessory: HMAccessory) -> Bool {
        let characteristic = accessory.services
            .flatMap(\.characteristics)
            .first { $0.characteristicType == HMCharacteristicTypePowerState }
        return (characteristic?.value as? Bool) ?? false
    }

    func toggle(_ accessory: HMAccessory) async throws {
        guard let characteristic = accessory.services
            .flatMap(\.characteristics)
            .first(where: { $0.characteristicType == HMCharacteristicTypePowerState })
        else { return }
        let current = (characteristic.value as? Bool) ?? false
        try await characteristic.writeValue(!current)
    }

    /// Explicit power write — the smart-home dashboard's card toggles set a
    /// known state rather than flipping whatever happens to be cached.
    func setPower(_ accessory: HMAccessory, on: Bool) async throws {
        guard let characteristic = accessory.services
            .flatMap(\.characteristics)
            .first(where: { $0.characteristicType == HMCharacteristicTypePowerState })
        else { return }
        try await characteristic.writeValue(on)
    }

    func thermostatTarget(_ accessory: HMAccessory) -> Double? {
        accessory.services
            .flatMap(\.characteristics)
            .first { $0.characteristicType == HMCharacteristicTypeTargetTemperature }
            .flatMap { $0.value as? Double }
    }

    // MARK: - Cameras & scenes (Cameras page)

    /// Accessories exposing a camera profile (video doorbells, HomeKit
    /// cameras). Computed from the delegate-mirrored `homes` array — never
    /// touches the lazy `manager`, so merely rendering a view that reads
    /// this cannot trigger the HomeKit permission prompt.
    var cameraAccessories: [HMAccessory] {
        homes.flatMap(\.accessories).filter { accessory in
            accessory.profiles.contains { $0 is HMCameraProfile }
        }
    }

    /// User-defined scenes with at least one action, per home (built-in
    /// empty placeholders would render as dead chips).
    func actionSets(in home: HMHome) -> [HMActionSet] {
        home.actionSets.filter { !$0.actions.isEmpty }
    }

    /// Runs a HomeKit scene — a real HMActionSet execution, not a mock.
    func execute(_ actionSet: HMActionSet, in home: HMHome) async throws {
        try await home.executeActionSet(actionSet)
    }
}

extension HomeKitService: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.homes = manager.homes
            self.accessories = manager.homes.flatMap(\.accessories)
            self.isAuthorized = manager.authorizationStatus == .authorized
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func homeManagerDidUpdatePrimaryHome(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.homes = manager.homes
        }
    }
}

import Foundation
import HomeKit
import Combine

@MainActor
final class HomeKitService: NSObject, ObservableObject {
    static let shared = HomeKitService()

    @Published var homes: [HMHome] = []
    @Published var accessories: [HMAccessory] = []
    @Published var isAuthorized = false
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined

    private lazy var manager: HMHomeManager = {
        let m = HMHomeManager()
        m.delegate = self
        return m
    }()

    private override init() {
        super.init()
        // manager is intentionally NOT accessed here — HMHomeManager must only
        // be created on explicit user action to avoid a crash when the
        // provisioning profile lacks the HomeKit entitlement.
    }

    var primaryHome: HMHome? { manager.primaryHome }

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

    func thermostatTarget(_ accessory: HMAccessory) -> Double? {
        accessory.services
            .flatMap(\.characteristics)
            .first { $0.characteristicType == HMCharacteristicTypeTargetTemperature }
            .flatMap { $0.value as? Double }
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

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

    // MARK: - Characteristic reads/writes (Smart Home S3)
    //
    // The device hero page's controls. Each helper resolves the accessory's
    // characteristic fresh, so a control only ever acts on what the device
    // genuinely exposes — the capability set gated the UI, these gate the act.

    private func characteristic(_ type: String, of accessory: HMAccessory) -> HMCharacteristic? {
        accessory.services.flatMap(\.characteristics).first { $0.characteristicType == type }
    }

    /// Brightness in percent (0–100), nil when the device has none.
    func brightness(_ accessory: HMAccessory) -> Int? {
        characteristic(HMCharacteristicTypeBrightness, of: accessory)?.value as? Int
    }

    func setBrightness(_ accessory: HMAccessory, percent: Int) async throws {
        guard let c = characteristic(HMCharacteristicTypeBrightness, of: accessory) else { return }
        try await c.writeValue(max(0, min(100, percent)))
    }

    /// Hue in degrees (0–360), nil when the bulb isn't color-capable.
    func hue(_ accessory: HMAccessory) -> Double? {
        characteristic(HMCharacteristicTypeHue, of: accessory)?.value as? Double
    }

    /// Writes hue (0–360) and full saturation — the hero page's spectrum
    /// slider picks a color, not a pastel ramp; brightness stays separate.
    func setHue(_ accessory: HMAccessory, degrees: Double) async throws {
        if let h = characteristic(HMCharacteristicTypeHue, of: accessory) {
            try await h.writeValue(max(0, min(360, degrees)))
        }
        if let s = characteristic(HMCharacteristicTypeSaturation, of: accessory) {
            try await s.writeValue(100.0)
        }
    }

    /// The room's measured temperature from the thermostat itself, nil when
    /// it doesn't report one.
    func currentTemperature(_ accessory: HMAccessory) -> Double? {
        characteristic(HMCharacteristicTypeCurrentTemperature, of: accessory)?.value as? Double
    }

    func setTargetTemperature(_ accessory: HMAccessory, celsius: Double) async throws {
        guard let c = characteristic(HMCharacteristicTypeTargetTemperature, of: accessory) else { return }
        try await c.writeValue(celsius)
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

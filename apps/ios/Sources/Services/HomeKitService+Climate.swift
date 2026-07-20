import Foundation
import HomeKit

// MARK: - Climate characteristics (Climate page)
//
// Read/write for the thermostat's heating/cooling MODE and the home's
// humidity reading — added as an extension so the frozen HomeKitService.swift
// stays untouched. Same discipline as the S3 helpers there: each call
// resolves the characteristic fresh from what the accessory genuinely
// exposes, and reads never touch the lazy manager (only the
// delegate-mirrored `homes`), so rendering can't trigger the permission
// prompt.

extension HomeKitService {
    /// `HMCharacteristicTypeTargetHeatingCoolingState` values, as HomeKit
    /// defines them (`HMCharacteristicValueHeatingCooling`).
    enum ClimateMode: Int {
        case off = 0
        case heat = 1
        case cool = 2
        case auto = 3
    }

    private func climateCharacteristic(_ type: String,
                                       of accessory: HMAccessory) -> HMCharacteristic? {
        accessory.services.flatMap(\.characteristics).first { $0.characteristicType == type }
    }

    /// The thermostat's commanded mode, nil when the accessory has none.
    func targetHeatingCoolingMode(_ accessory: HMAccessory) -> ClimateMode? {
        guard let value = climateCharacteristic(HMCharacteristicTypeTargetHeatingCooling,
                                                of: accessory)?.value as? Int
        else { return nil }
        return ClimateMode(rawValue: value)
    }

    /// Writes the thermostat's mode; no-op for accessories without the
    /// characteristic (the UI only offers modes when a thermostat exists).
    func setTargetHeatingCoolingMode(_ accessory: HMAccessory,
                                     mode: ClimateMode) async throws {
        guard let c = climateCharacteristic(HMCharacteristicTypeTargetHeatingCooling,
                                            of: accessory) else { return }
        try await c.writeValue(mode.rawValue)
    }

    /// The accessory's own relative-humidity reading (0–100 %), when it
    /// reports one.
    func currentRelativeHumidity(_ accessory: HMAccessory) -> Double? {
        let value = climateCharacteristic(HMCharacteristicTypeCurrentRelativeHumidity,
                                          of: accessory)?.value
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    /// The first humidity reading anywhere in the user's homes — the
    /// climate page's "Humid" mode shows it. Computed from the
    /// delegate-mirrored `homes`; nil when no accessory reports humidity
    /// (the UI says so instead of inventing a number).
    func firstHumidityReading() -> Double? {
        for home in homes {
            for accessory in home.accessories {
                if let value = currentRelativeHumidity(accessory) { return value }
            }
        }
        return nil
    }
}

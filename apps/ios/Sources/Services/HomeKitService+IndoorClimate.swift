import Foundation
import HomeKit

// MARK: - Indoor climate readings (Smart Control R3)
//
// On-demand indoor temperature (and humidity, when the same accessory
// reports it) from EVERY reachable HomeKit accessory that exposes a
// currentTemperature characteristic — added as an extension so the frozen
// HomeKitService.swift stays untouched (the HomeKitService+Rooms pattern).
//
// Read discipline:
// - Targets resolve from the delegate-mirrored `homes` (never the lazy
//   manager), so calling this can't trigger the HomeKit permission prompt.
// - Each characteristic gets a fresh `readValue` fanned out concurrently
//   (TaskGroup), each raced against a short timeout — one dead accessory
//   can never hold the refresh (or the UI) hostage. A read that outlives
//   the deadline is abandoned; if it eventually lands, HomeKit caches the
//   value and the NEXT refresh picks it up.
// - A reading is returned only when the characteristic actually carries a
//   value delivered by HomeKit — never invented, never defaulted.

/// One accessory's indoor climate reading, tagged with the accessory's
/// HomeKit room so climate surfaces can attribute it to a space.
struct IndoorClimateReading: Identifiable, Equatable {
    /// The accessory's `uniqueIdentifier` — stable across refreshes.
    let id: UUID
    let accessoryName: String
    /// The accessory's HomeKit room name, nil when unassigned.
    let roomName: String?
    /// Temperature in °C (Fahrenheit metadata is normalized here).
    let celsius: Double
    /// Relative humidity 0–100 %, when the same accessory reports one.
    let humidity: Double?
}

extension HomeKitService {

    /// Reads the current indoor temperature (and humidity, when present)
    /// of every reachable accessory exposing the characteristic. Returns
    /// only values HomeKit genuinely delivered; an empty array honestly
    /// means "no indoor sensor reported".
    func readIndoorClimate(timeout: TimeInterval = 2.5) async -> [IndoorClimateReading] {
        struct Target {
            let accessory: HMAccessory
            let temperature: HMCharacteristic
            let humidity: HMCharacteristic?
        }

        let targets: [Target] = homes.flatMap(\.accessories)
            .filter(\.isReachable)
            .compactMap { accessory in
                let characteristics = accessory.services.flatMap(\.characteristics)
                guard let temperature = characteristics.first(where: {
                    $0.characteristicType == HMCharacteristicTypeCurrentTemperature
                }) else { return nil }
                let humidity = characteristics.first {
                    $0.characteristicType == HMCharacteristicTypeCurrentRelativeHumidity
                }
                return Target(accessory: accessory,
                              temperature: temperature,
                              humidity: humidity)
            }
        guard !targets.isEmpty else { return [] }

        // Fan out the fresh reads; every characteristic races the shared
        // per-read timeout, so the whole refresh finishes in ~one timeout
        // regardless of how many accessories are slow or gone.
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask { @MainActor in
                    await Self.refreshValue(of: target.temperature, within: timeout)
                }
                if let humidity = target.humidity {
                    group.addTask { @MainActor in
                        await Self.refreshValue(of: humidity, within: timeout)
                    }
                }
            }
        }

        return targets.compactMap { target in
            guard let celsius = Self.celsius(from: target.temperature) else { return nil }
            return IndoorClimateReading(
                id: target.accessory.uniqueIdentifier,
                accessoryName: target.accessory.name,
                roomName: target.accessory.room?.name,
                celsius: celsius,
                humidity: target.humidity.flatMap(Self.numericValue(of:)))
        }
    }

    // MARK: Read with timeout

    /// Issues one fresh `readValue` and waits at most `timeout` seconds.
    /// Both completion paths funnel through the main queue, so the
    /// single-resume gate needs no lock; the continuation resumes exactly
    /// once whichever side wins.
    private static func refreshValue(of characteristic: HMCharacteristic,
                                     within timeout: TimeInterval) async {
        final class Gate { var resumed = false }
        let gate = Gate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            characteristic.readValue { _ in
                DispatchQueue.main.async {
                    guard !gate.resumed else { return }
                    gate.resumed = true
                    continuation.resume()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !gate.resumed else { return }
                gate.resumed = true
                continuation.resume()
            }
        }
    }

    // MARK: Value extraction

    /// The characteristic's cached numeric value (Int or Double as HomeKit
    /// happens to deliver it), nil when nothing has ever been read.
    private static func numericValue(of characteristic: HMCharacteristic) -> Double? {
        if let double = characteristic.value as? Double { return double }
        if let int = characteristic.value as? Int { return Double(int) }
        return nil
    }

    /// The temperature in °C — HAP defines currentTemperature in Celsius,
    /// but an accessory declaring Fahrenheit metadata is normalized here.
    private static func celsius(from characteristic: HMCharacteristic) -> Double? {
        guard let value = numericValue(of: characteristic) else { return nil }
        if characteristic.metadata?.units == HMCharacteristicMetadataUnitsFahrenheit {
            return (value - 32) * 5 / 9
        }
        return value
    }
}

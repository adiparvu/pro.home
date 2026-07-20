import Foundation
import HomeKit
import Observation

// MARK: - Smart-home aggregator (Smart Home S1)
//
// The one service the smart-home surfaces bind to. It projects both providers
// (HomeKitService + IoTService) into the unified `SmartDevice` list and routes
// actions back to the right one. `devices` is computed on access, so the
// Observation framework tracks the underlying providers' state directly —
// a HomeKit delegate update or an IoT relay confirmation re-renders the UI
// with no mirroring/sync layer to drift.
@MainActor
@Observable
final class SmartHomeService {
    static let shared = SmartHomeService()
    private let homeKit = HomeKitService.shared
    private let iot = IoTService.shared

    private init() {}

    // MARK: Aggregation

    /// Every device from both providers, HomeKit first (richer capabilities).
    var devices: [SmartDevice] {
        var out: [SmartDevice] = []
        for home in homeKit.homes {
            for accessory in home.accessories {
                out.append(Self.device(from: accessory))
            }
        }
        for actuator in iot.relayActuators {
            out.append(Self.device(from: actuator))
        }
        for sensor in iot.sensors {
            out.append(Self.device(from: sensor))
        }
        return out
    }

    /// Room names across both providers, in stable order, deduplicated.
    var rooms: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for d in devices {
            guard let room = d.room, !room.isEmpty, seen.insert(room).inserted else { continue }
            out.append(room)
        }
        return out
    }

    func devices(in room: String?) -> [SmartDevice] {
        guard let room else { return devices }
        return devices.filter { $0.room == room }
    }

    /// Devices grouped by kind for the dashboard's type cards, in a stable
    /// display order. Only kinds that actually have devices appear.
    func devicesByKind(in room: String?) -> [(kind: SmartDeviceKind, devices: [SmartDevice])] {
        let scoped = devices(in: room)
        return SmartDeviceKind.allCases.compactMap { kind in
            let matching = scoped.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    /// Whether ANY provider has devices — drives the dashboard's honest
    /// empty/onboarding state instead of an empty grid.
    var hasAnyDevice: Bool { !devices.isEmpty }

    // MARK: Actions

    /// Sets a device's power, routed to its provider. No-op for devices
    /// without the capability (the UI never draws the control for those).
    func setPower(_ device: SmartDevice, on: Bool) async {
        guard device.hasPower else { return }
        switch device.backing {
        case .homeKit(let accessory):
            try? await homeKit.setPower(accessory, on: on)
        case .iotRelay(let actuator):
            iot.perform(on ? .turnOn : .turnOff, on: actuator)
        case .iotSensor:
            break
        }
    }

    // MARK: Capability controls (Smart Home S3) — each acts only on devices
    // whose capability set unlocked the control; others no-op harmlessly.

    /// Brightness percent (0–100) when the device reports one.
    func brightness(of device: SmartDevice) -> Int? {
        guard case .homeKit(let accessory) = device.backing,
              device.capabilities.contains(.brightness) else { return nil }
        return homeKit.brightness(accessory)
    }

    func setBrightness(_ device: SmartDevice, percent: Int) async {
        guard case .homeKit(let accessory) = device.backing else { return }
        try? await homeKit.setBrightness(accessory, percent: percent)
    }

    /// Hue in degrees (0–360) for color bulbs.
    func hue(of device: SmartDevice) -> Double? {
        guard case .homeKit(let accessory) = device.backing,
              device.capabilities.contains(.color) else { return nil }
        return homeKit.hue(accessory)
    }

    func setHue(_ device: SmartDevice, degrees: Double) async {
        guard case .homeKit(let accessory) = device.backing else { return }
        try? await homeKit.setHue(accessory, degrees: degrees)
    }

    /// The thermostat's own measured temperature, when it reports one.
    func currentTemperature(of device: SmartDevice) -> Double? {
        guard case .homeKit(let accessory) = device.backing else { return nil }
        return homeKit.currentTemperature(accessory)
    }

    /// The commanded target temperature, when the device has one.
    func targetTemperature(of device: SmartDevice) -> Double? {
        guard case .homeKit(let accessory) = device.backing,
              device.capabilities.contains(.targetTemperature) else { return nil }
        return homeKit.thermostatTarget(accessory)
    }

    func setTargetTemperature(_ device: SmartDevice, celsius: Double) async {
        guard case .homeKit(let accessory) = device.backing else { return }
        try? await homeKit.setTargetTemperature(accessory, celsius: celsius)
    }

    /// Triggers the HomeKit permission flow (first use of the manager).
    func connectHomeKit() { homeKit.requestAccess() }

    var homeKitAuthorized: Bool { homeKit.isAuthorized }

    // MARK: Provider → SmartDevice projections

    private static func device(from accessory: HMAccessory) -> SmartDevice {
        let characteristics = accessory.services.flatMap(\.characteristics)
        var caps: Set<SmartDeviceCapability> = []
        var isOn: Bool? = nil
        for c in characteristics {
            switch c.characteristicType {
            case HMCharacteristicTypePowerState:
                caps.insert(.power)
                isOn = c.value as? Bool
            case HMCharacteristicTypeBrightness:        caps.insert(.brightness)
            case HMCharacteristicTypeHue:               caps.insert(.color)
            case HMCharacteristicTypeTargetTemperature: caps.insert(.targetTemperature)
            case HMCharacteristicTypeTargetLockMechanismState: caps.insert(.lock)
            default: break
            }
        }
        return SmartDevice(
            id: "hk:\(accessory.uniqueIdentifier.uuidString)",
            name: accessory.name,
            room: accessory.room?.name,
            kind: kind(for: accessory),
            capabilities: caps,
            isReachable: accessory.isReachable,
            isOn: isOn,
            readingValue: nil, readingUnit: nil,
            backing: .homeKit(accessory))
    }

    private static func kind(for accessory: HMAccessory) -> SmartDeviceKind {
        if accessory.profiles.contains(where: { $0 is HMCameraProfile }) { return .camera }
        switch accessory.category.categoryType {
        case HMAccessoryCategoryTypeLightbulb:     return .light
        case HMAccessoryCategoryTypeOutlet:        return .outlet
        case HMAccessoryCategoryTypeSwitch,
             HMAccessoryCategoryTypeProgrammableSwitch: return .switcher
        case HMAccessoryCategoryTypeThermostat:    return .thermostat
        case HMAccessoryCategoryTypeSensor:        return .sensor
        case HMAccessoryCategoryTypeDoorLock:      return .lock
        case HMAccessoryCategoryTypeWindowCovering: return .cover
        default:                                   return .other
        }
    }

    private static func device(from actuator: IoTActuator) -> SmartDevice {
        SmartDevice(
            id: "iot-act:\(actuator.id.uuidString)",
            name: actuator.name,
            room: nil,
            kind: .switcher,
            capabilities: [.power],
            isReachable: true,
            // Last commanded state only — nil until the first command, and we
            // never invent a state the controller hasn't confirmed.
            isOn: actuator.isOn,
            readingValue: nil, readingUnit: nil,
            backing: .iotRelay(actuator))
    }

    private static func device(from sensor: IoTSensor) -> SmartDevice {
        SmartDevice(
            id: "iot-sen:\(sensor.id.uuidString)",
            name: sensor.name,
            room: sensor.linkedZoneName.isEmpty ? nil : sensor.linkedZoneName,
            kind: .sensor,
            capabilities: [.reading],
            isReachable: sensor.value != nil,
            isOn: nil,
            readingValue: sensor.value,
            readingUnit: sensor.unit,
            backing: .iotSensor(sensor))
    }
}

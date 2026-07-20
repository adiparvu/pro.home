import Foundation
import HomeKit
import Observation

// MARK: - Smart-home schedules (Smart Home S3 — Schedule card)
//
// One schedule per device: power ON at `fromMinutes`, OFF at `toMinutes`,
// daily. Two honest execution paths:
//
// - HomeKit accessories: a real `HMTimerTrigger` PAIR on the accessory's
//   home — each trigger fires a dedicated `HMActionSet` holding one
//   `HMCharacteristicWriteAction` on the power characteristic (true at
//   From, false at To), recurring daily. HomeKit executes these on the
//   home hub, so they run with the app closed. Re-saving REPLACES the
//   previous pair (triggers and action sets are found by their canonical
//   PRVIO name prefix, removed, and recreated).
//
// - IoT relays: the hub has no server-side scheduler the app can program,
//   so the schedule persists locally (UserDefaults) and a lightweight
//   foreground check (`evaluateIoTSchedules`, called by the Schedule card
//   on appear and on scene-activation) commands the relay toward the
//   window's desired state. Honest by design: it works while the app runs,
//   and the card's caption says exactly that.
//
// UserDefaults mirrors BOTH providers' schedules so the card can reflect
// saved state instantly; for HomeKit the triggers on the home remain the
// executing source of truth.

/// One device's daily power window. Times are minutes from midnight in the
/// user's current calendar; a window with `from > to` wraps past midnight.
struct SmartSchedule: Codable, Equatable {
    var isEnabled: Bool
    var fromMinutes: Int
    var toMinutes: Int
    /// The last state the foreground IoT check commanded, so re-activations
    /// don't spam the relay with the same command.
    var lastAppliedOn: Bool? = nil

    static let `default` = SmartSchedule(isEnabled: false,
                                         fromMinutes: 18 * 60,
                                         toMinutes: 22 * 60)

    /// Whether `minuteOfDay` falls inside the ON window (midnight-wrapping).
    func contains(minuteOfDay minute: Int) -> Bool {
        guard fromMinutes != toMinutes else { return false }
        if fromMinutes < toMinutes {
            return minute >= fromMinutes && minute < toMinutes
        }
        return minute >= fromMinutes || minute < toMinutes
    }
}

@MainActor
@Observable
final class SmartScheduleService {
    static let shared = SmartScheduleService()

    /// Persisted schedules keyed by `SmartDevice.id` (stable per provider
    /// object: "hk:<uuid>" / "iot-act:<uuid>").
    private(set) var schedules: [String: SmartSchedule] = [:]

    private static let storeKey = "smartHome.schedules.v1"
    /// Canonical name prefix for the trigger/action-set pair PRVIO owns on
    /// a HomeKit home — the replace/remove handle.
    private static let homeKitNamePrefix = "PRVIO Schedule"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: SmartSchedule].self, from: data) {
            schedules = decoded
        }
    }

    func schedule(for deviceID: String) -> SmartSchedule? {
        schedules[deviceID]
    }

    /// Persists and applies a schedule. Returns whether the apply landed —
    /// callers reflect a failure honestly instead of showing a saved state
    /// that doesn't exist. Best-effort: a HomeKit apply failure leaves the
    /// previously persisted schedule untouched.
    func setSchedule(_ schedule: SmartSchedule, for device: SmartDevice) async -> Bool {
        switch device.backing {
        case .homeKit(let accessory):
            do {
                try await applyHomeKit(schedule, accessory: accessory, deviceID: device.id)
            } catch {
                debugLog("Smart schedule apply failed:", error)
                return false
            }
            persist(schedule, for: device.id)
            return true

        case .iotRelay:
            // Reset the applied marker so the next evaluation re-decides
            // against the new window, then evaluate immediately.
            var stored = schedule
            stored.lastAppliedOn = nil
            persist(stored, for: device.id)
            evaluateIoTSchedules()
            return true

        case .iotSensor:
            return false
        }
    }

    // MARK: - HomeKit: HMTimerTrigger pair (runs on the home hub)

    private func applyHomeKit(_ schedule: SmartSchedule,
                              accessory: HMAccessory,
                              deviceID: String) async throws {
        guard let home = HomeKitService.shared.homes.first(where: { home in
            home.accessories.contains { $0.uniqueIdentifier == accessory.uniqueIdentifier }
        }) else { throw SmartScheduleError.homeNotFound }

        guard let power = accessory.services
            .flatMap(\.characteristics)
            .first(where: { $0.characteristicType == HMCharacteristicTypePowerState })
        else { throw SmartScheduleError.noPowerCharacteristic }

        // Deterministic names — the replace handle. Scoped per accessory so
        // two scheduled devices in one home never collide.
        let handle = "\(Self.homeKitNamePrefix) \(accessory.uniqueIdentifier.uuidString.prefix(8))"

        // Remove the previous pair (idempotent; missing objects are fine).
        for trigger in home.triggers where trigger.name.hasPrefix(handle) {
            try? await home.removeTrigger(trigger)
        }
        for actionSet in home.actionSets where actionSet.name.hasPrefix(handle) {
            try? await home.removeActionSet(actionSet)
        }

        guard schedule.isEnabled else { return }

        try await addTimerTrigger(named: "\(handle) On",
                                  minutes: schedule.fromMinutes,
                                  powerValue: true,
                                  characteristic: power, in: home)
        try await addTimerTrigger(named: "\(handle) Off",
                                  minutes: schedule.toMinutes,
                                  powerValue: false,
                                  characteristic: power, in: home)
    }

    /// One half of the pair: an action set writing `powerValue` to the power
    /// characteristic, fired daily at `minutes` past midnight.
    private func addTimerTrigger(named name: String,
                                 minutes: Int,
                                 powerValue: Bool,
                                 characteristic: HMCharacteristic,
                                 in home: HMHome) async throws {
        let actionSet = try await home.addActionSet(named: name)
        let write = HMCharacteristicWriteAction(characteristic: characteristic,
                                                targetValue: NSNumber(value: powerValue))
        try await actionSet.addAction(write)

        let trigger = HMTimerTrigger(name: name,
                                     fireDate: Self.nextFireDate(minutesFromMidnight: minutes),
                                     recurrence: DateComponents(day: 1))
        try await home.addTrigger(trigger)
        try await trigger.addActionSet(actionSet)
        try await trigger.enable(true)
    }

    /// HomeKit requires a future fire date: the next wall-clock occurrence
    /// of hh:mm (today if still ahead, otherwise tomorrow).
    static func nextFireDate(minutesFromMidnight minutes: Int) -> Date {
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        return Calendar.current.nextDate(after: Date(),
                                         matching: components,
                                         matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(60)
    }

    // MARK: - IoT relays: foreground evaluation

    /// Drives enabled relay schedules toward their window's desired state.
    /// Called on card appear and scene activation — deliberately lightweight
    /// (a dictionary walk plus at most one command per changed relay).
    func evaluateIoTSchedules() {
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.hour, from: now) * 60
                   + calendar.component(.minute, from: now)

        for (key, schedule) in schedules where key.hasPrefix("iot-act:") && schedule.isEnabled {
            guard let actuator = IoTService.shared.relayActuators.first(where: {
                "iot-act:\($0.id.uuidString)" == key
            }) else { continue }

            let desired = schedule.contains(minuteOfDay: minute)
            guard schedule.lastAppliedOn != desired else { continue }

            IoTService.shared.perform(desired ? .turnOn : .turnOff, on: actuator)
            var updated = schedule
            updated.lastAppliedOn = desired
            persist(updated, for: key)
        }
    }

    // MARK: - Persistence

    private func persist(_ schedule: SmartSchedule, for deviceID: String) {
        schedules[deviceID] = schedule
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    private enum SmartScheduleError: Error {
        case homeNotFound
        case noPowerCharacteristic
    }
}

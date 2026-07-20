import Foundation
import HomeKit

// MARK: - Rooms & accessory pairing (Home hub)
//
// Room management and real accessory pairing for the dashboard's home hub —
// added as an extension so the frozen HomeKitService.swift stays untouched
// (the same pattern as HomeKitService+Climate). Reads resolve from the
// delegate-mirrored `homes` (never the lazy manager), so merely rendering a
// view can't trigger the HomeKit permission prompt. Writes bridge HomeKit's
// completion handlers to async and rethrow the exact HomeKit error to the
// caller — no silent failures, the UI says what actually happened.

extension HomeKitService {

    // MARK: Reads

    /// The user-defined rooms of a home (`HMHome.rooms`). The implicit
    /// whole-home default room is not listed — Apple Home's own room
    /// pickers do the same.
    func rooms(in home: HMHome) -> [HMRoom] {
        home.rooms
    }

    /// The home containing an accessory, resolved from the delegate-mirrored
    /// `homes` array (an `HMAccessory` doesn't expose its home directly).
    func home(of accessory: HMAccessory) -> HMHome? {
        homes.first { home in
            home.accessories.contains { $0.uniqueIdentifier == accessory.uniqueIdentifier }
        }
    }

    // MARK: Writes

    /// Creates a room in a home — bridged from
    /// `HMHome.addRoom(withName:completionHandler:)` (iOS 8.0+). Throws the
    /// HomeKit error unchanged on failure.
    @discardableResult
    func addRoom(name: String, to home: HMHome) async throws -> HMRoom {
        let room: HMRoom = try await withCheckedThrowingContinuation { continuation in
            home.addRoom(withName: name) { room, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let room {
                    continuation.resume(returning: room)
                } else {
                    // HomeKit's contract is exactly one of the two; if the
                    // framework ever breaks it, fail loudly, never hang.
                    continuation.resume(throwing: HMError(.genericError))
                }
            }
        }
        touchHomes()
        return room
    }

    /// Moves an accessory into a room — bridged from
    /// `HMHome.assignAccessory(_:to:completionHandler:)` (iOS 8.0+). Throws
    /// the HomeKit error unchanged on failure.
    func assignAccessory(_ accessory: HMAccessory, to room: HMRoom, in home: HMHome) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            home.assignAccessory(accessory, to: room) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        touchHomes()
    }

    // MARK: Pairing (Apple's native setup flow)

    /// One setup manager for the app's lifetime — the flow itself is
    /// system-owned UI; keeping the manager alive across the presentation
    /// is the documented usage.
    private static let accessorySetup = HMAccessorySetupManager()

    /// Presents Apple's NATIVE accessory-pairing flow (code scan, Matter
    /// setup), scoped to the given home when one exists. Uses
    /// `HMAccessorySetupManager.performAccessorySetup(using:)` — the modern
    /// API (iOS 15.4+, comfortably inside our 17.1 target); the older
    /// `HMHome.addAndSetupAccessories(completionHandler:)` is deprecated
    /// since iOS 15.4 in favor of exactly this call. Throws HomeKit's error
    /// unchanged — including `HMError.Code.operationCancelled` when the
    /// user backs out of the system sheet, which callers may treat as a
    /// non-error.
    func startPairing(in home: HMHome?) async throws {
        let request = HMAccessorySetupRequest()
        request.homeUniqueIdentifier = home?.uniqueIdentifier
        _ = try await Self.accessorySetup.performAccessorySetup(using: request)
        touchHomes()
    }

    // MARK: Observation nudge

    /// `HMHome` objects mutate IN PLACE (a room added, an accessory
    /// reassigned, a device paired) — the mirrored `homes` array keeps the
    /// same element identities, so the Observation framework has no write
    /// to react to. Re-assigning the array after a successful mutation is
    /// the deliberate, single-point nudge that re-renders every surface
    /// derived from it.
    private func touchHomes() {
        homes = homes
        accessories = homes.flatMap(\.accessories)
    }
}

import Foundation
import HomeKit

// MARK: - Scenes (Smart Control R2)
//
// The scene layer every scene surface binds to (dashboard chips, space-page
// quick chips, hub list) — added as an extension so the frozen
// HomeKitService.swift stays untouched (the HomeKitService+Rooms pattern).
//
// Read discipline: everything resolves from the delegate-mirrored `homes`
// (never the lazy manager), so merely rendering a scene surface can never
// trigger the HomeKit permission prompt; unauthorized states return an
// empty list, and the UI honestly renders nothing.
//
// Reachability honesty: executing a scene does NOT require a home hub —
// HomeKit runs the action set over the local network directly. A missing
// hub only limits remote access and automations (`isMissingHomeHub` covers
// that guide), so nothing here gates execution on it. The only truthful
// failure signal is the execution error itself, rethrown verbatim.

// MARK: - Scene classification

/// What a scene IS in HomeKit's own taxonomy (`HMActionSet.actionSetType`)
/// — drives the chip/row iconography only; execution is identical for all.
enum HomeKitSceneType {
    case wakeUp, sleep, homeArrival, homeDeparture, userDefined

    init(actionSetType: String) {
        switch actionSetType {
        case HMActionSetTypeWakeUp:        self = .wakeUp
        case HMActionSetTypeSleep:         self = .sleep
        case HMActionSetTypeHomeArrival:   self = .homeArrival
        case HMActionSetTypeHomeDeparture: self = .homeDeparture
        default:                           self = .userDefined
        }
    }

    var icon: String {
        switch self {
        case .wakeUp:        return "sunrise.fill"
        case .sleep:         return "bed.double.fill"
        case .homeArrival:   return "house.fill"
        case .homeDeparture: return "figure.walk.departure"
        case .userDefined:   return "sparkles"
        }
    }
}

/// One executable HomeKit scene with the home it belongs to — an
/// `HMActionSet` can only run through its own `HMHome`, so the pair travels
/// together (the same reason the S2 chips carried home × action-set pairs).
struct HomeKitScene: Identifiable {
    let home: HMHome
    let actionSet: HMActionSet

    /// The action set's `uniqueIdentifier` — stable across delegate updates.
    var id: UUID { actionSet.uniqueIdentifier }
    var name: String { actionSet.name }
    var type: HomeKitSceneType { HomeKitSceneType(actionSetType: actionSet.actionSetType) }
    var homeName: String { home.name }
}

extension HomeKitService {

    /// `SmartScheduleService`'s canonical name handle (private there, so the
    /// literal is mirrored — one string, commented on both sides). The
    /// schedule feature owns `HMActionSet`s named with this prefix as
    /// trigger plumbing; they are not user scenes and never surface as chips.
    private static let schedulePlumbingPrefix = "PRVIO Schedule"

    // MARK: Reads

    /// Every executable scene across the mirrored homes, in HomeKit's own
    /// stable order. Empty when HomeKit is unauthorized — scene surfaces
    /// render nothing, honestly, instead of a dead row.
    var scenes: [HomeKitScene] {
        guard isAuthorized else { return [] }
        return homes.flatMap { scenes(in: $0) }
    }

    /// The executable scenes of one home. Filtered honestly:
    /// - empty action sets (Apple's built-in placeholders) would run as
    ///   no-ops — dead chips, excluded;
    /// - trigger-owned action sets are automation internals HomeKit itself
    ///   never lists as scenes;
    /// - the app's own schedule plumbing (see `schedulePlumbingPrefix`).
    func scenes(in home: HMHome) -> [HomeKitScene] {
        home.actionSets
            .filter { actionSet in
                !actionSet.actions.isEmpty
                    && actionSet.actionSetType != HMActionSetTypeTriggerOwned
                    && !actionSet.name.hasPrefix(Self.schedulePlumbingPrefix)
            }
            .map { HomeKitScene(home: home, actionSet: $0) }
    }

    /// The HomeKit room names a scene genuinely touches — each write action
    /// resolves through its characteristic to the owning accessory's room.
    /// Non-write actions (none exist in the public API today) contribute
    /// nothing rather than a guess.
    func roomNames(touchedBy scene: HomeKitScene) -> Set<String> {
        var names: Set<String> = []
        for action in scene.actionSet.actions {
            guard let write = action as? HMCharacteristicWriteAction<NSCopying>,
                  let room = write.characteristic.service?.accessory?.room?.name,
                  !room.isEmpty
            else { continue }
            names.insert(room)
        }
        return names
    }

    /// Scenes whose actions touch at least one accessory in the named space
    /// — the case/diacritic-insensitive name match used everywhere the
    /// HomeKit and PRVIO worlds meet.
    func scenes(touchingSpaceNamed name: String) -> [HomeKitScene] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return scenes.filter { scene in
            roomNames(touchedBy: scene).contains { room in
                room.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(trimmed,
                             options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }

    // MARK: Execute

    /// Runs a scene — bridged from
    /// `HMHome.executeActionSet(_:completionHandler:)` and rethrowing the
    /// exact HomeKit error (no silent failures, no wrapper copy). HomeKit
    /// has no cancel for a running action set, so callers own their UI
    /// patience; the command itself always runs to completion or error.
    func executeScene(_ scene: HomeKitScene) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            scene.home.executeActionSet(scene.actionSet) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

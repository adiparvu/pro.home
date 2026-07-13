import Foundation
import Observation

// MARK: - Indoor climate store (Smart Control R3)
//
// The one cache the climate surfaces bind to: the latest HomeKit indoor
// readings (temperature per accessory, humidity when present), refreshed
// through `HomeKitService.readIndoorClimate` — the concurrent, timeboxed
// readValue fan-out. Feature-level by design (the Services layer stays
// stateless about UI cadence): the dashboard refreshes it on scene-active
// and first appearance, the space page and climate page on their own
// appearance plus pull-to-refresh. No polling loops — every refresh is an
// explicit, user-visible moment.
//
// Honesty: `readings` only ever contains values HomeKit genuinely
// delivered. Losing authorization empties the cache instead of freezing
// the last numbers on screen.
@MainActor
@Observable
final class IndoorClimateStore {
    static let shared = IndoorClimateStore()

    /// The latest indoor readings — empty when no reachable accessory
    /// reported a temperature (an honest nothing, never a placeholder).
    private(set) var readings: [IndoorClimateReading] = []
    /// When the last fan-out finished, nil before the first one.
    private(set) var lastRefreshed: Date?
    /// True while a fan-out is in flight (drives refresh affordances).
    private(set) var isRefreshing = false

    /// Per-characteristic readValue deadline (seconds) — short enough that
    /// a wall of dead accessories still resolves visibly fast.
    private static let readTimeout: TimeInterval = 2.5
    /// How long a completed refresh stays "fresh" for `refreshIfStale()`.
    private static let maxAge: TimeInterval = 180

    private init() {}

    /// One full fan-out. Re-entrant calls coalesce (the in-flight refresh
    /// wins); without HomeKit authorization the cache empties honestly.
    func refresh() async {
        guard !isRefreshing else { return }
        let homeKit = HomeKitService.shared
        guard homeKit.isAuthorized else {
            readings = []
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        readings = await homeKit.readIndoorClimate(timeout: Self.readTimeout)
        lastRefreshed = Date()
    }

    /// Refreshes only when the cache is older than `maxAge` — the cheap
    /// call for onAppear paths that shouldn't hammer the accessories.
    func refreshIfStale() async {
        if let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < Self.maxAge {
            return
        }
        await refresh()
    }

    /// The reading whose HomeKit room matches a PRVIO space by name —
    /// case/diacritic-insensitive, the same match every other place the
    /// two worlds meet uses.
    func reading(forSpaceNamed name: String) -> IndoorClimateReading? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return readings.first { reading in
            guard let room = reading.roomName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !room.isEmpty else { return false }
            return room.compare(trimmed,
                                options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

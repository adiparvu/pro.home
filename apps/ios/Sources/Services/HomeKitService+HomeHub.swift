import Foundation
import HomeKit

// MARK: - Home hub state (Smart Control R1 — the hub guide)
//
// One honest question: does this home lack a connected home hub (HomePod /
// Apple TV)? Automations and remote access need one; without it HomeKit
// control only works on the home network. Added as an extension so the
// frozen HomeKitService.swift stays untouched. Computed from the
// delegate-mirrored `homes` — rendering a view that reads this can never
// trigger the HomeKit permission prompt.

extension HomeKitService {
    /// True only when the absence is GENUINELY detected: HomeKit is
    /// authorized, at least one home exists, and no home reports a
    /// connected hub (`HMHome.homeHubState != .connected` everywhere).
    /// Unauthorized or home-less states return false — no detection means
    /// no scare copy, per the honesty law.
    var isMissingHomeHub: Bool {
        guard isAuthorized, !homes.isEmpty else { return false }
        return !homes.contains { $0.homeHubState == .connected }
    }
}

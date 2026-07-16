import UIKit

/// One question, answered from the real UIKit state: is the app in the
/// BACKGROUND right now?
///
/// Why it exists: iOS kills a backgrounded app that spends >10 s of wall
/// clock in a scene update (FRONTBOARD 0x8BADF00D, "scene-update watchdog
/// transgression" — captured on device, Build 1036). With realtime now
/// actually delivering rows in the background, every insert was triggering
/// reloads → SwiftUI diffs → UI transactions while backgrounded, and under
/// Low Power Mode the throttled main thread blew the 10 s budget. The rule
/// that prevents the whole class of kills: the app goes QUIET in the
/// background — no realtime-driven reloads, no channel rebuilds, no socket
/// revivals. Everything refreshes on foreground activation, where every
/// surface already has a hook.
@MainActor
enum AppLifecycle {
    /// True while the app is fully backgrounded (NOT merely inactive — the
    /// brief .inactive during transitions/system sheets must not drop work).
    static var isBackgrounded: Bool {
        UIApplication.shared.applicationState == .background
    }
}

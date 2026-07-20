import Foundation
import CoreMotion

// MARK: - MotionTiltEngine (F2) — the gyroscope behind the lens droplets
//
// A ref-counted CoreMotion tap that turns device attitude into a smoothed
// [-1, 1] tilt pair for the sky shader's droplet parallax. Deliberately NOT
// @Observable: it updates at 30 Hz, and the stage already redraws every
// frame through TimelineView — publishing each sample would only add
// invalidation churn. The view reads the current values inside its frame
// closure instead.
//
// Battery honesty: the stage acquires this ONLY while rain is actually on
// screen (droplets are the sole consumer), releases it the moment the rain
// clears or the stage leaves, and the engine refuses to start at all in
// Low Power Mode. `deviceMotion` needs no permission prompt — attitude is
// not activity data.

@MainActor
final class MotionTiltEngine {
    static let shared = MotionTiltEngine()

    /// Smoothed roll tilt, [-1, 1] over ±45° — positive = leaning right.
    private(set) var tiltX: Double = 0
    /// Smoothed pitch tilt relative to the ADAPTIVE resting angle, so the
    /// droplets react to changes in how the phone is held, not to the
    /// absolute posture (people read phones anywhere from flat to upright).
    private(set) var tiltY: Double = 0

    private let manager = CMMotionManager()
    private var refCount = 0
    private var pitchBaseline: Double?

    private init() {}

    func acquire() {
        refCount += 1
        guard refCount == 1,
              manager.isDeviceMotionAvailable,
              !manager.isDeviceMotionActive,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            // Delivered on the main queue — hop into the actor statically.
            MainActor.assumeIsolated {
                guard let self else { return }
                let quarterPi = Double.pi / 4
                // Roll rests at 0 naturally; pitch tracks a slow baseline.
                let baseline = self.pitchBaseline ?? pitch
                self.pitchBaseline = baseline * 0.995 + pitch * 0.005
                let nx = max(-1, min(1, roll / quarterPi))
                let ny = max(-1, min(1, (pitch - baseline) / quarterPi))
                // Low-pass so the droplets glide instead of jittering.
                self.tiltX = self.tiltX * 0.85 + nx * 0.15
                self.tiltY = self.tiltY * 0.85 + ny * 0.15
            }
        }
    }

    func release() {
        refCount = max(0, refCount - 1)
        guard refCount == 0 else { return }
        manager.stopDeviceMotionUpdates()
        tiltX = 0
        tiltY = 0
        pitchBaseline = nil
    }
}

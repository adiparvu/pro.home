import SwiftUI

// MARK: - Dynamic wallpapers (iMessage-style)
//
// Ambient, slowly-drifting colour fields rendered as an animated mesh
// gradient — the same feel as the dynamic backgrounds Messages ships.
// Motion is deliberately glacial (full drift cycles take ~1 minute on
// incommensurate sine tracks, so it never visibly loops), capped at 30fps,
// and collapses to a still frame under Reduce Motion.

struct AnimatedBackgroundPreset: Identifiable {
    let id: String
    let name: LocalizedStringKey
    /// Palette cycled across the 3×3 mesh control grid.
    let colors: [Color]
    /// Drives bubble/meta adaptivity, same as the static themes.
    let isDark: Bool

    static let all: [AnimatedBackgroundPreset] = [
        AnimatedBackgroundPreset(id: "aurora", name: "Aurora",
            colors: [Color(red: 0.10, green: 0.55, blue: 0.55),
                     Color(red: 0.25, green: 0.30, blue: 0.75),
                     Color(red: 0.45, green: 0.75, blue: 0.65),
                     Color(red: 0.55, green: 0.35, blue: 0.85)],
            isDark: true),
        AnimatedBackgroundPreset(id: "horizon", name: "Horizon",
            colors: [Color(red: 0.99, green: 0.80, blue: 0.55),
                     Color(red: 0.96, green: 0.55, blue: 0.45),
                     Color(red: 0.90, green: 0.42, blue: 0.55),
                     Color(red: 0.99, green: 0.70, blue: 0.45)],
            isDark: false),
        AnimatedBackgroundPreset(id: "tide", name: "Tide",
            colors: [Color(red: 0.65, green: 0.85, blue: 0.93),
                     Color(red: 0.30, green: 0.60, blue: 0.82),
                     Color(red: 0.50, green: 0.78, blue: 0.88),
                     Color(red: 0.20, green: 0.45, blue: 0.72)],
            isDark: false),
        AnimatedBackgroundPreset(id: "bloom", name: "Bloom",
            colors: [Color(red: 0.93, green: 0.83, blue: 0.95),
                     Color(red: 0.80, green: 0.70, blue: 0.95),
                     Color(red: 0.97, green: 0.78, blue: 0.86),
                     Color(red: 0.86, green: 0.82, blue: 0.98)],
            isDark: false),
        AnimatedBackgroundPreset(id: "ember", name: "Ember",
            colors: [Color(red: 0.25, green: 0.08, blue: 0.15),
                     Color(red: 0.55, green: 0.18, blue: 0.18),
                     Color(red: 0.35, green: 0.12, blue: 0.30),
                     Color(red: 0.70, green: 0.35, blue: 0.20)],
            isDark: true),
        AnimatedBackgroundPreset(id: "midnight", name: "Midnight",
            colors: [Color(red: 0.05, green: 0.08, blue: 0.20),
                     Color(red: 0.12, green: 0.18, blue: 0.40),
                     Color(red: 0.08, green: 0.10, blue: 0.28),
                     Color(red: 0.20, green: 0.30, blue: 0.55)],
            isDark: true),
    ]

    static func preset(for id: String) -> AnimatedBackgroundPreset? {
        all.first { $0.id == id }
    }

    /// Nine control colours for the 3×3 mesh, cycled from the palette.
    var meshColors: [Color] {
        (0..<9).map { colors[$0 % colors.count] }
    }

    /// Static stand-in for swatches and the iOS 17 fallback.
    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct AnimatedChatBackground: View {
    let preset: AnimatedBackgroundPreset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if reduceMotion {
            frame(at: 0)
        } else {
            // Pause the timeline (not just the drawing) when the scene leaves
            // the foreground so the mesh stops re-rendering in the background.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                    paused: scenePhase != .active)) { context in
                frame(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    @ViewBuilder
    private func frame(at t: Double) -> some View {
        if #available(iOS 18.0, *) {
            MeshGradient(width: 3, height: 3,
                         points: Self.points(at: t),
                         colors: preset.meshColors)
        } else {
            preset.gradient
        }
    }

    /// 3×3 control grid: corners pinned so edges never tear; the inner points
    /// drift on sine tracks with incommensurate speeds and phases. The first
    /// tuning (speeds ≈0.1 rad/s) took a full minute per cycle — technically
    /// animated, visibly frozen. These cycles run 9–18s: alive at a glance,
    /// still calm behind bubbles, exactly the iMessage feel.
    static func points(at t: Double) -> [SIMD2<Float>] {
        func drift(_ base: Float, _ amp: Float, _ speed: Double, _ phase: Double) -> Float {
            base + amp * Float(sin(t * speed + phase))
        }
        return [
            [0, 0], [drift(0.5, 0.20, 0.47, 0.0), 0], [1, 0],
            [0, drift(0.5, 0.18, 0.39, 1.3)],
            [drift(0.5, 0.30, 0.33, 2.1), drift(0.5, 0.30, 0.55, 4.2)],
            [1, drift(0.5, 0.18, 0.43, 5.0)],
            [0, 1], [drift(0.5, 0.20, 0.51, 3.3), 1], [1, 1],
        ]
    }
}

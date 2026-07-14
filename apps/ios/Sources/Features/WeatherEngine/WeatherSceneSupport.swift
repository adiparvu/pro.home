import SwiftUI
import SpriteKit

// MARK: - Weather Engine · shared scene building blocks
//
// Reusable pieces the scenes compose:
//   - ComposedRainView / ComposedSnowView — SwiftUI hosts that mount the
//     EXISTING SpriteKit particle engines (RainScene / SnowScene from
//     AppBackdropEffects.swift), so the weather engine reuses the one tuned
//     particle implementation instead of duplicating it. Both are `Equatable`
//     on their inputs so SwiftUI can skip re-evaluating them every frame while
//     they sit under the stage's TimelineView (the SKView runs its own display
//     link; it needs no SwiftUI tick).
//   - CloudField — a Canvas drifting soft-cloud field driven purely by the
//     parameters and the stage clock; the generic scene and the storm share it.

// MARK: - Composed SpriteKit hosts

/// Hosts the shared `RainScene`. `isActive` pauses the SKView with the scene
/// phase (energy contract). The scene object is created once and kept in
/// `@State`; identity is stable so it is not rebuilt per frame.
struct ComposedRainView: View, Equatable {
    let scheme: ColorScheme
    let intensity: CGFloat
    let isActive: Bool
    /// Adds a very faint airborne dust/haze emitter to the shared rain scene —
    /// invisible in the dark storm, but "caught in the flash" when the Metal
    /// illumination wash (a plusLighter layer composited above this SpriteView)
    /// lights it. Default OFF, so the mood backdrop and the plain rain scenes
    /// are unchanged; the thunderstorm passes `true`. It rides the SAME SKView
    /// this scene already mounts, so it costs no extra display link.
    var airborneDust: Bool = false

    @State private var scene: SKScene?

    var body: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, isPaused: !isActive,
                           preferredFramesPerSecond: 60,
                           options: [.allowsTransparency])
            }
        }
        .onAppear {
            if scene == nil {
                scene = RainScene(scheme: scheme, intensity: intensity,
                                  airborneDust: airborneDust)
            }
        }
        .allowsHitTesting(false)
    }

    // Rebuild only when the rain's defining inputs change — not every frame.
    static func == (lhs: ComposedRainView, rhs: ComposedRainView) -> Bool {
        lhs.scheme == rhs.scheme && lhs.intensity == rhs.intensity
            && lhs.isActive == rhs.isActive && lhs.airborneDust == rhs.airborneDust
    }
}

/// Hosts the shared `SnowScene`. Same lifecycle/pause contract as the rain host.
struct ComposedSnowView: View, Equatable {
    let intensity: CGFloat
    let isActive: Bool

    @State private var scene: SKScene?

    var body: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, isPaused: !isActive,
                           preferredFramesPerSecond: 60,
                           options: [.allowsTransparency])
            }
        }
        .onAppear {
            if scene == nil { scene = SnowScene(intensity: intensity) }
        }
        .allowsHitTesting(false)
    }

    static func == (lhs: ComposedSnowView, rhs: ComposedSnowView) -> Bool {
        lhs.intensity == rhs.intensity && lhs.isActive == rhs.isActive
    }
}

// MARK: - Cloud field (Canvas)

/// A drifting field of soft clouds, drawn in one Canvas. Blob count scales with
/// `cover`; `darkness` bruises them for storms; `warmth` tints them at golden
/// hour; `wind` sets drift speed. Fully deterministic (a fixed seed) so clouds
/// never jump between frames or mounts, and a pure function of `time` so the
/// static frame (time frozen) is a valid still.
///
/// COST: N ≤ ~14 radial-gradient fills per frame (no Canvas blur — the softness
/// is baked into each radial gradient's falloff). See the frame-cost notes.
struct CloudField: View {
    var cover: Double
    var darkness: Double
    var warmth: Double
    var wind: Double
    var time: TimeInterval
    /// Vertical band the clouds occupy, in unit space.
    var band: ClosedRange<Double> = 0.06...0.5

    /// Deterministic per-cloud layout in unit space: x seed, y, scale, alpha,
    /// speed. Generated once.
    private static let seeds: [(x: Double, y: Double, scale: Double,
                                alpha: Double, speed: Double)] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0x0C10_0D_5EED)
        return (0..<14).map { _ in
            (x: Double.random(in: 0...1, using: &rng),
             y: Double.random(in: 0...1, using: &rng),
             scale: Double.random(in: 0.7...1.5, using: &rng),
             alpha: Double.random(in: 0.5...1.0, using: &rng),
             speed: Double.random(in: 0.4...1.0, using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            guard cover > 0.02 else { return }
            let count = max(1, Int((Double(Self.seeds.count) * cover).rounded()))
            let baseColor = cloudColor
            let driftBase = time * (6 + wind * 30) // pt/s, wind-scaled

            for seed in Self.seeds.prefix(count) {
                let w = size.width * (0.5 + seed.scale * 0.5)
                let h = w * 0.42
                // Wrap horizontally across a widened track so clouds enter and
                // exit fully offscreen (no pop-in).
                let track = size.width + w
                var x = (seed.x * track + driftBase * seed.speed)
                    .truncatingRemainder(dividingBy: track)
                if x < 0 { x += track }
                x -= w / 2
                let y = size.height * (band.lowerBound
                    + seed.y * (band.upperBound - band.lowerBound))

                let rect = CGRect(x: x, y: y, width: w, height: h)
                let a = seed.alpha * min(1, cover * 1.15)
                let shading = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [baseColor.opacity(a),
                                      baseColor.opacity(a * 0.4),
                                      baseColor.opacity(0)]),
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    startRadius: 0, endRadius: w / 2)
                context.fill(Path(ellipseIn: rect), with: shading)
            }
        }
        .allowsHitTesting(false)
    }

    /// Cloud body color: bright neutral, warmed toward gold, darkened for storms.
    private var cloudColor: Color {
        // Bright base, pulled down by darkness, warmed by warmth.
        let base = 1.0 - darkness * 0.72
        let r = base
        let g = base - warmth * 0.02
        let b = base - warmth * 0.14
        return Color(red: max(0, r), green: max(0, g), blue: max(0, b))
    }
}

// MARK: - Seeded RNG (deterministic Canvas layouts)

/// SplitMix64 — the same deterministic generator the night star field uses, so
/// every Canvas layout in the weather engine is stable across mounts and
/// frames. (Private to the weather engine; the mood system keeps its own copy.)
struct SystemRandomNumberGeneratorSeeded: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

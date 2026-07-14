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

// MARK: - Star field (Canvas, fixed seed + twinkle) — shared

/// A fixed-seed constellation twinkling off the shared clock. Deterministic
/// layout (SplitMix64) so the sky never jumps; a pure function of `time`, so
/// the still frame is a valid night. `visibility` fades the whole field in as
/// dusk deepens; `count` selects a stable PREFIX of the 90-star layout (so a
/// twilight sky can show just a few first stars while the deep night shows the
/// full field — same seed, same positions, never a separate dice roll); and
/// `alphaScale` dims the field independently (blue hour's faint first stars).
///
/// SHARED by NightScene (full field), BlueHourScene (a faint few) and the
/// full-moon night. The `count == 90, alphaScale == 1` default reproduces the
/// night flagship's original field exactly.
struct WeatherStarField: View {
    var visibility: Double
    var time: TimeInterval
    /// How many of the fixed 90-star layout to draw (a stable prefix).
    var count: Int = 90
    /// An extra multiplier on every star's alpha (1 = night; < 1 = fainter).
    var alphaScale: Double = 1

    private struct Star { let x, y, size, baseAlpha, twinkleAmp, speed, phase: Double }

    private static let stars: [Star] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0x5EED_57A2_F1E1D)
        return (0..<90).map { _ in
            Star(x: .random(in: 0.01...0.99, using: &rng),
                 y: .random(in: 0.01...0.72, using: &rng), // stars sit in the upper sky
                 size: .random(in: 0.6...1.7, using: &rng),
                 baseAlpha: .random(in: 0.25...0.9, using: &rng),
                 twinkleAmp: .random(in: 0.05...0.35, using: &rng),
                 speed: .random(in: 0.6...2.2, using: &rng),
                 phase: .random(in: 0...(2 * .pi), using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            let n = min(Self.stars.count, max(0, count))
            for star in Self.stars.prefix(n) {
                let tw = star.baseAlpha
                    + star.twinkleAmp * sin(time * star.speed + star.phase)
                let alpha = max(0, min(1, tw)) * visibility * alphaScale
                guard alpha > 0.01 else { continue }
                let r = star.size
                let rect = CGRect(x: star.x * size.width - r, y: star.y * size.height - r,
                                  width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Atmospheric sky gradient (overlay depth)

/// A reusable additive-depth gradient the sky scenes lay OVER the stage's
/// two-stop base sky to give it altitude: a `zenith` tint that deepens the top
/// of the sky (the richer, more saturated overhead blue of a Rayleigh sky, or
/// the indigo of twilight) fading out by `zenithSpan`, and a `horizon` band
/// that pales/warms the lower sky (atmospheric haze, a golden wash, a twilight
/// ember) rising from `horizonStart`. Both are plain `LinearGradient`s — no
/// blur, no per-frame work — so this redraws only when its inputs change.
///
/// Colors carry their own opacity (via `WeatherRGB.color(opacity:)`), so normal
/// alpha compositing does the tint; a scene that wants a glow can pass
/// `blend: .plusLighter`. SHARED by ClearDay, GoldenHour and BlueHour so the
/// three read as one atmospheric system; the flagships are untouched.
struct WeatherSkyGradient: View {
    var zenith: WeatherRGB
    var zenithStrength: Double
    var horizon: WeatherRGB
    var horizonStrength: Double
    /// Height fraction where the zenith influence has faded to nothing.
    var zenithSpan: Double = 0.55
    /// Height fraction where the horizon band begins to rise.
    var horizonStart: Double = 0.6
    var blend: BlendMode = .normal

    var body: some View {
        ZStack {
            if zenithStrength > 0.001 {
                LinearGradient(
                    stops: [.init(color: zenith.color(opacity: zenithStrength), location: 0),
                            .init(color: .clear, location: min(0.999, zenithSpan))],
                    startPoint: .top, endPoint: .bottom)
            }
            if horizonStrength > 0.001 {
                LinearGradient(
                    stops: [.init(color: .clear, location: max(0.001, horizonStart)),
                            .init(color: horizon.color(opacity: horizonStrength), location: 1)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .blendMode(blend)
        .allowsHitTesting(false)
    }
}

// MARK: - Cirrus field (Canvas, thin high wisps)

/// A few high, thin, slow-drifting cirrus streaks — the wispy ice clouds of a
/// clear or golden sky, distinct from `CloudField`'s soft cumulus blobs. Each
/// streak is an elongated ellipse filled with a horizontal gradient that fades
/// at both ends, so it reads as a feathered wisp with NO blur (softness baked
/// into the falloff). Deterministic (fixed seed) and a pure function of `time`.
///
/// COST: ≤ 6 gradient-filled ellipses per frame. See the frame-cost notes.
struct WeatherCirrusField: View {
    /// Overall opacity, 0...1.
    var strength: Double
    /// Tint toward warm (golden hour) as this goes 0 → 1.
    var warmth: Double
    var wind: Double
    var time: TimeInterval
    /// Vertical band the wisps occupy — high in the sky by default.
    var band: ClosedRange<Double> = 0.10...0.34

    private static let seeds: [(x: Double, y: Double, len: Double,
                                thick: Double, alpha: Double, speed: Double)] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0xC127_5E5E_D1A0_7B11)
        return (0..<6).map { _ in
            (x: Double.random(in: 0...1, using: &rng),
             y: Double.random(in: 0...1, using: &rng),
             len: Double.random(in: 0.4...0.85, using: &rng),
             thick: Double.random(in: 0.5...1.0, using: &rng),
             alpha: Double.random(in: 0.35...0.8, using: &rng),
             speed: Double.random(in: 0.3...0.7, using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            guard strength > 0.01 else { return }
            let drift = time * (3 + wind * 14) // pt/s, gentle, wind-scaled
            let tint = cirrusColor
            for s in Self.seeds {
                let w = size.width * s.len
                let h = max(2, size.height * 0.014 * s.thick)
                let track = size.width + w
                var x = (s.x * track + drift * s.speed)
                    .truncatingRemainder(dividingBy: track)
                if x < 0 { x += track }
                x -= w / 2
                let y = size.height * (band.lowerBound
                    + s.y * (band.upperBound - band.lowerBound))
                let rect = CGRect(x: x, y: y, width: w, height: h)
                let a = s.alpha * strength
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [tint.opacity(0), tint.opacity(a),
                                      tint.opacity(a * 0.6), tint.opacity(0)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY))
                context.fill(Path(ellipseIn: rect), with: shading)
            }
        }
        .allowsHitTesting(false)
    }

    /// Bright neutral white, warmed toward gold as `warmth` rises.
    private var cirrusColor: Color {
        Color(red: 1.0,
              green: max(0, 0.99 - warmth * 0.06),
              blue: max(0, 0.98 - warmth * 0.16))
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

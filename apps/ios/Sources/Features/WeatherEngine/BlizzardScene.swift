import SwiftUI

// MARK: - Weather Engine · BlizzardScene (SpriteKit + Canvas · blizzard)
//
// Violent snow — a storm, not merely "more snow". It replaces the generic path
// for `.blizzard` and layers, from BACK to FRONT:
//
//   1. COLD FLAT OVERCAST — a pale, desaturated depth gradient (WeatherSkyGradient),
//      colder and flatter than the calm snow scene: a storm sky with no sun.
//   2. WHITEOUT HAZE (back) — the SHARED WeatherFogBank driven HARD: high
//      density, a near-white tint, banks filling the whole frame, so visibility
//      drops the way it does in a real whiteout.
//   3. ACCUMULATION (shared SnowAccumulationBand) — deeper and FASTER-building
//      than calm snow (higher cap, shorter time-constant), sitting behind the
//      near atmosphere so the front veil hazes it like distant ground.
//   4. DRIVEN FLAKES — the SHARED SpriteKit SnowScene at high intensity (≈1.7)
//      with a strong WIND BIAS (its additive `wind` knob): dense, fast,
//      near-horizontal flakes. The one flake engine, biased — not a copy.
//   5. MOTION STREAKS (Canvas) — fast near-horizontal wind-driven streaks with
//      baked motion blur, the violent driving-snow read the particle field alone
//      can't give.
//   6. WHITEOUT PULSE (front) — a heavy pale veil over everything whose opacity
//      PULSES on a slow gust rhythm, cutting visibility as the storm gusts.
//
// ENERGY: the SpriteKit flakes and the Canvas streaks mount only when
// `context.motionEnabled`; the whiteout haze/veil and the accumulation are cheap
// gradients/paths that also render (frozen) in the still frame, so Reduce Motion
// / Low Power still reads as a pale, hazy, snowed-in storm — no SpriteKit, no
// animating shader.
struct BlizzardScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    private var snow: Double { context.parameters.snowIntensity }

    /// Near-white haze tint — the whiteout colour for both the bank and the veil.
    private static let whiteout = Color(red: 0.96, green: 0.97, blue: 0.99)

    var body: some View {
        let p = context.parameters
        ZStack {
            // 1. Cold flat overcast depth.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.54, 0.60, 0.68), zenithStrength: 0.26,
                horizon: WeatherRGB(0.90, 0.92, 0.96), horizonStrength: 0.34,
                zenithSpan: 0.6, horizonStart: 0.5)

            // 2. Whiteout haze — the shared fog bank driven hard, filling the frame.
            WeatherFogBank(density: min(1.0, 0.55 + p.fogDensity),
                           tint: Self.whiteout, wind: p.windStrength,
                           time: context.time, band: 0.0...1.1)

            // 3. Accumulation — deeper, faster than calm snow; resets on mount.
            SnowAccumulationBand(cap: 0.18, timeConstant: 12,
                                 time: context.time,
                                 motionEnabled: context.motionEnabled)

            // 4. Driven flakes — shared SpriteKit engine, high intensity + wind.
            //    intensity 0.6 + snow×1.1 → blizzard ≈ 1.7 (budget in the report).
            if context.motionEnabled {
                ComposedSnowView(intensity: 0.6 + snow * 1.1,
                                 isActive: context.isActive,
                                 wind: p.windStrength)
                    .equatable()

                // 5. Motion streaks — fast near-horizontal driving snow.
                BlizzardStreaks(intensity: p.particleIntensity, wind: p.windStrength,
                                time: context.time)
            }

            // 6. Pulsing whiteout veil — over everything, gusting.
            BlizzardWhiteout(time: context.time)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Motion streaks (Canvas · fast near-horizontal driving snow)

/// Fast, near-horizontal wind-driven streaks with BAKED motion blur (a wide
/// faint underlay beneath a thin bright core — never a Canvas `.blur`). Each
/// streak travels horizontally with a slight downward slope and wraps.
/// Deterministic layout, a pure function of `time`, so the still frame is valid.
///
/// COST: N ≤ 14 streaks × 2 strokes = ≤ 28 line strokes per frame. Count/alpha
/// scale with intensity. See the frame-cost notes.
private struct BlizzardStreaks: View {
    var intensity: Double
    var wind: Double
    var time: TimeInterval

    private struct Streak { let y, length, width, speed, alpha, phase, slope: Double }

    private static let streaks: [Streak] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0xB112_2A4D_57EE_A011)
        return (0..<14).map { _ in
            Streak(y: .random(in: -0.02...1.02, using: &rng),
                   length: .random(in: 0.16...0.34, using: &rng),
                   width: .random(in: 1.2...2.6, using: &rng),
                   speed: .random(in: 0.6...1.1, using: &rng),   // fraction width / s
                   alpha: .random(in: 0.10...0.22, using: &rng),
                   phase: .random(in: 0...1, using: &rng),
                   slope: .random(in: 0.28...0.42, using: &rng)) // downward tilt
        }
    }()

    var body: some View {
        Canvas { context, size in
            guard intensity > 0.02, size.width > 1 else { return }
            let count = max(6, Int((Double(Self.streaks.count)
                                    * (0.5 + intensity * 0.5)).rounded()))
            let travel = 0.6 + wind   // wind speeds the horizontal drive
            for s in Self.streaks.prefix(count) {
                let prog = (s.phase + time * s.speed * travel)
                    .truncatingRemainder(dividingBy: 1)
                let len = s.length * size.width
                let x0 = prog * (size.width + len) - len
                let y0 = s.y * size.height
                let p0 = CGPoint(x: x0, y: y0)
                let p1 = CGPoint(x: x0 + len, y: y0 + len * s.slope)
                var path = Path()
                path.move(to: p0)
                path.addLine(to: p1)
                // Baked motion blur: wide faint pass, then a thin bright core.
                context.stroke(path,
                    with: .color(.white.opacity(s.alpha * 0.5 * intensity)),
                    style: StrokeStyle(lineWidth: s.width * 1.9, lineCap: .round))
                context.stroke(path,
                    with: .color(.white.opacity(s.alpha * intensity)),
                    style: StrokeStyle(lineWidth: s.width * 0.7, lineCap: .round))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Whiteout veil (pulsing pale wash)

/// A heavy pale veil over the whole frame whose opacity PULSES on a slow,
/// two-sine gust rhythm — the visibility-killing whiteout of a blizzard. A plain
/// additive `LinearGradient` (no blur, no per-frame drawing beyond one
/// composite); `time` frozen in the still frame settles it to a steady haze.
private struct BlizzardWhiteout: View {
    var time: TimeInterval

    var body: some View {
        // Two decorrelated sines → a gusting, non-mechanical breath.
        let gust = 0.5 + 0.5 * sin(time * 0.5)
        let slow = 0.5 + 0.5 * sin(time * 0.23 + 1.3)
        let a = 0.14 + 0.16 * gust * (0.6 + 0.4 * slow)
        LinearGradient(
            colors: [Color.white.opacity(a * 0.7),
                     Color.white.opacity(a),
                     Color.white.opacity(a * 0.88)],
            startPoint: .top, endPoint: .bottom)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

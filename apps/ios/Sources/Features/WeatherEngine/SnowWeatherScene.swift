import SwiftUI

// MARK: - Weather Engine · SnowWeatherScene (SpriteKit + Canvas · snow)
//
// The dedicated Apple-Weather-depth snow scene, replacing the generic path for
// `.snow`. Calm and dimensional — 3D-feeling flakes at varied speeds with
// near/far parallax, a gentle motion blur on the nearest plane, and snow that
// ACCUMULATES along the bottom edge over time. It layers, from BACK to FRONT:
//
//   1. COLD OVERCAST SKY — a cool blue-white depth gradient (WeatherSkyGradient)
//      over the stage's already-pale base sky, plus a soft high overcast deck
//      (a light, flat CloudField) — the low snow cloud, no sun.
//   2. PARALLAX FLAKES — the SHARED SpriteKit SnowScene (two depths: far
//      slow/small/faint + near fast/large/bright, with per-flake rotation and a
//      twinkle), composed calm (wind 0). The one flake engine, not a copy.
//   3. NEAR MOTION-BLURRED FLAKES (Canvas) — a few large foreground flakes with
//      a BAKED vertical smear (no Canvas blur), the nearest parallax plane, in
//      front of the SpriteKit field — the dimensional "close to the glass" read.
//   4. ACCUMULATION BAND (shared SnowAccumulationBand) — a soft white pile that
//      thickens along the bottom over time toward a hard cap, then holds.
//
// ENERGY: the SpriteKit flakes and the near-flake motion mount only when
// `context.motionEnabled`; the still frame (Reduce Motion / Low Power / effects
// off) shows sky + overcast + a settled accumulation band — a faithful frozen
// representative with no SpriteKit and no animating shader.
struct SnowWeatherScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// The snow dial (snow 0.6). Fades cleanly during a cross-dissolve because
    /// the parameter set is lerped upstream.
    private var snow: Double { context.parameters.snowIntensity }

    var body: some View {
        let p = context.parameters
        ZStack {
            // 1. Cold blue-white overcast depth + a soft high snow deck.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.58, 0.66, 0.76), zenithStrength: 0.28,
                horizon: WeatherRGB(0.93, 0.95, 0.98), horizonStrength: 0.30,
                zenithSpan: 0.55, horizonStart: 0.58)

            if p.cloudCover > 0.02 {
                // Light, flat, high — an even overcast, not sculpted cumulus.
                CloudField(cover: min(0.6, p.cloudCover * 0.8),
                           darkness: max(p.cloudDarkness, 0.14),
                           warmth: 0, wind: p.windStrength * 0.6,
                           time: context.time, band: 0.02...0.30)
                    .opacity(0.9)
            }

            // 2. Parallax flakes — shared SpriteKit engine, calm (wind 0).
            //    intensity 0.6 + snow×1.1 → snow ≈ 1.26 (budget in the report).
            //    `.equatable()` so it is not re-evaluated on every stage tick.
            if context.motionEnabled {
                ComposedSnowView(intensity: 0.6 + snow * 1.1,
                                 isActive: context.isActive)
                    .equatable()

                // 3. Near motion-blurred flakes — nearest parallax, in front.
                NearSnowFlakes(intensity: snow, wind: p.windStrength,
                               time: context.time)
            }

            // 4. Accumulation — slow, thin, capped; resets on mount.
            SnowAccumulationBand(cap: 0.12, timeConstant: 26,
                                 time: context.time,
                                 motionEnabled: context.motionEnabled)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Near motion-blurred flakes (Canvas · nearest parallax)

/// A few large foreground flakes drifting down with a BAKED vertical motion
/// smear (a faint elongated glow behind a soft round core — never a Canvas
/// `.blur`), the nearest parallax plane in front of the SpriteKit field.
/// Deterministic layout, a pure function of `time` (each flake falls, sways and
/// wraps), so the frozen still frame is valid.
///
/// COST: N ≤ 7 flakes × 2 radial-gradient fills = ≤ 14 fills per frame. Count
/// and alpha scale with intensity. See the frame-cost notes.
private struct NearSnowFlakes: View {
    var intensity: Double
    var wind: Double
    var time: TimeInterval

    private struct Flake { let x, radius, speed, alpha, phase, sway, swayPhase: Double }

    private static let flakes: [Flake] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0x5A0F_1A4E_B00C_71D3)
        return (0..<7).map { _ in
            Flake(x: .random(in: -0.05...1.05, using: &rng),
                  radius: .random(in: 3.5...7.0, using: &rng),
                  speed: .random(in: 0.05...0.11, using: &rng),   // fraction of height / s
                  alpha: .random(in: 0.5...0.85, using: &rng),
                  phase: .random(in: 0...1, using: &rng),
                  sway: .random(in: 0.02...0.05, using: &rng),
                  swayPhase: .random(in: 0...(2 * .pi), using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            guard intensity > 0.02, size.width > 1 else { return }
            let count = max(3, Int((Double(Self.flakes.count)
                                    * (0.6 + intensity * 0.4)).rounded()))
            let windSway = 0.6 + wind * 1.4
            for f in Self.flakes.prefix(count) {
                let prog = (f.phase + time * f.speed).truncatingRemainder(dividingBy: 1)
                let y = prog * (1.1 * size.height) - 0.05 * size.height
                let swayX = sin(time * windSway + f.swayPhase) * f.sway * size.width
                let cx = f.x * size.width + swayX
                let r = f.radius
                let a = f.alpha * intensity

                // Baked vertical motion smear (clipped to a tall ellipse).
                let smear = CGRect(x: cx - r * 0.7, y: y - r * 2.2,
                                   width: r * 1.4, height: r * 4.4)
                context.fill(Path(ellipseIn: smear), with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(a * 0.22), .clear]),
                    center: CGPoint(x: cx, y: y), startRadius: 0, endRadius: r * 2.2))

                // Soft round core.
                let core = CGRect(x: cx - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: core), with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(a),
                                      Color.white.opacity(a * 0.4), .clear]),
                    center: CGPoint(x: cx, y: y), startRadius: 0, endRadius: r))
            }
        }
        .allowsHitTesting(false)
    }
}

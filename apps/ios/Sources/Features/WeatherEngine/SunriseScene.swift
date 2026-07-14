import SwiftUI

// MARK: - Weather Engine · SunriseScene (flagship · Composite tier)
//
// The dawn slice of the daylight arc. It proves the COMPOSITE tier: a warm
// bloom + illuminated fog band (Canvas/gradient), Metal god rays, and tinted
// clouds (Canvas), all seated on the stage's night→day base gradient.
//
// THE NIGHT→DAY PROGRESSION is real parameter interpolation, NOT a canned
// 20-minute animation: the engine transitions through night → sunrise →
// clearDay as conditions, and the stage's base sky LERPS their gradients (and
// this scene cross-dissolves in over the dawn window). A future real-time
// driver can push `sunElevation` continuously and everything here tracks it,
// because the scene is a pure function of `parameters` — the sun position,
// bloom seat, and ray origin are all derived from `sunElevation`/`sunAzimuth`.
// The same file serves `.sunset` (the sun simply sits on the other azimuth,
// descending); the scene reads the parameters, so no separate code path.
struct SunriseScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// The sun / ray origin in unit space. Low sun (small elevation) seats the
    /// glow near the horizon; azimuth places it left (sunrise) or right (sunset).
    private var sun: UnitPoint {
        UnitPoint(x: context.parameters.sunAzimuth,
                  y: 0.92 - context.parameters.sunElevation * 0.72)
    }

    var body: some View {
        let p = context.parameters
        let warm = WeatherLight.color(warmth: p.lightWarmth)
        ZStack {
            // Tinted clouds first (they catch the low warm light) — kept high
            // and thin so the horizon stays clear for the bloom.
            if p.cloudCover > 0.02 {
                CloudField(cover: p.cloudCover, darkness: p.cloudDarkness,
                           warmth: max(p.lightWarmth, 0.8), wind: p.windStrength,
                           time: context.time, band: 0.05...0.32)
            }

            // Illuminated fog band — a soft warm horizontal wash lying along the
            // horizon where dawn light scatters. A gradient, not a blur.
            if p.fogDensity > 0.02 {
                LinearGradient(
                    colors: [.clear,
                             warm.opacity(p.fogDensity * 0.5),
                             warm.opacity(p.fogDensity * 0.28)],
                    startPoint: UnitPoint(x: 0.5, y: 0.5),
                    endPoint: .bottom)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }

            // Warm bloom pooled at the sun — a large soft radial, additive.
            RadialGradient(
                colors: [warm.opacity(0.55 * (0.5 + p.lightWarmth * 0.5)),
                         warm.opacity(0.18), .clear],
                center: sun, startRadius: 0, endRadius: context.size.width * 0.7)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            // Metal volumetric god rays streaming from the low sun.
            GodRayLayer(sun: sun, strength: p.godRayStrength,
                        warmth: warm, time: context.time, size: context.size)
        }
        .allowsHitTesting(false)
    }
}

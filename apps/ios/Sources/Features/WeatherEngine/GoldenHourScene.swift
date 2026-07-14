import SwiftUI

// MARK: - Weather Engine · GoldenHourScene (Metal tier)
//
// The warm hour before sunset (and after sunrise): a low, warm sun with long
// volumetric light. Over the base gradient it lays:
//   1. A whole-sky amber-gold WASH (WeatherSkyGradient, plusLighter) — dusky
//      violet up high melting into a strong warm band low, so the entire frame
//      is bathed in gold, not just the horizon.
//   2. Thin, high CLOUDS tinted by the warm light (shared CloudField, forced
//      warm) — they catch the gold on their undersides.
//   3. A large warm BLOOM pooled at the low sun.
//   4. Stronger warm volumetric GOD RAYS than clear day (the shared Metal
//      shaft) streaming from the low sun.
//
// Distinct from SunriseScene (which keeps a night→day gradient and a horizon-
// hugging bloom): golden hour washes the FULL sky warm and reads as cinematic,
// settled daylight rather than the cool-to-warm dawn transition.
struct GoldenHourScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// The low warm sun — seated near the horizon, dropping further as
    /// `sunElevation` falls; azimuth places it on its side of the sky.
    private var sun: UnitPoint {
        UnitPoint(x: context.parameters.sunAzimuth,
                  y: 0.88 - context.parameters.sunElevation * 0.52)
    }

    var body: some View {
        let p = context.parameters
        let warm = WeatherLight.color(warmth: p.lightWarmth)
        ZStack {
            // Full-sky amber wash.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.52, 0.40, 0.56), zenithStrength: 0.26,
                horizon: WeatherRGB(1.0, 0.72, 0.38), horizonStrength: 0.52,
                zenithSpan: 0.5, horizonStart: 0.40, blend: .plusLighter)

            // Warm-tinted thin clouds, kept high so the horizon stays open.
            if p.cloudCover > 0.02 {
                CloudField(cover: p.cloudCover, darkness: p.cloudDarkness,
                           warmth: max(p.lightWarmth, 0.85), wind: p.windStrength,
                           time: context.time, band: 0.08...0.36)
            }

            // Large warm bloom at the sun.
            RadialGradient(
                colors: [warm.opacity(0.6 * (0.5 + p.lightWarmth * 0.5)),
                         warm.opacity(0.20), .clear],
                center: sun, startRadius: 0, endRadius: context.size.width * 0.8)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            // Strong warm volumetric rays.
            GodRayLayer(sun: sun, strength: p.godRayStrength, warmth: warm,
                        time: context.time, size: context.size)
        }
        .allowsHitTesting(false)
    }
}

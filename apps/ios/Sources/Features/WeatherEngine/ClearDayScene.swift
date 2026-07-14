import SwiftUI

// MARK: - Weather Engine · ClearDayScene (Metal tier)
//
// A physically-plausible clear daytime sky. Over the stage's two-stop base
// gradient it lays, top to bottom:
//   1. A Rayleigh-style DEPTH gradient (WeatherSkyGradient) — a richer, more
//      saturated blue at the zenith fading out by mid-sky, plus a pale
//      atmospheric-haze band along the horizon. This is what turns a flat
//      two-stop fill into a sky with altitude.
//   2. A few slow, high CIRRUS wisps (WeatherCirrusField) — thin feathered ice
//      clouds, not cumulus blobs.
//   3. A soft SUN with a subtle bloom, seated high from `sunElevation`.
//   4. Low-strength volumetric GOD RAYS (the shared Metal shaft) — barely there,
//      just enough to feel the light is real. Gated on `godRayStrength > 0`.
//
// Pure function of the context; no blur; the one shader pass is strength-gated.
// Crisp, bright, calm — the clear-day baseline the daylight arc dissolves from.
struct ClearDayScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// The sun sits high; a touch of `sunElevation` lets a lower clear sky drop
    /// it slightly. Azimuth places it left/right.
    private var sun: UnitPoint {
        UnitPoint(x: context.parameters.sunAzimuth,
                  y: 0.30 - context.parameters.sunElevation * 0.14)
    }

    var body: some View {
        let p = context.parameters
        let warm = WeatherLight.color(warmth: p.lightWarmth)
        ZStack {
            // Zenith blue deepened, horizon paled with haze.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.15, 0.41, 0.78), zenithStrength: 0.5,
                horizon: WeatherRGB(0.86, 0.93, 0.99), horizonStrength: 0.30,
                zenithSpan: 0.62, horizonStart: 0.60)

            // High, slow cirrus — a few wisps, scaled by the sky's cloud cover.
            WeatherCirrusField(strength: min(0.7, 0.34 + p.cloudCover * 2),
                               warmth: p.lightWarmth,
                               wind: p.windStrength, time: context.time)

            // Soft sun disc + subtle bloom.
            RadialGradient(
                colors: [Color.white.opacity(0.85),
                         warm.opacity(0.35), .clear],
                center: sun, startRadius: 0, endRadius: context.size.width * 0.42)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            // Low-strength god rays.
            GodRayLayer(sun: sun, strength: p.godRayStrength, warmth: warm,
                        time: context.time, size: context.size)
        }
        .allowsHitTesting(false)
    }
}

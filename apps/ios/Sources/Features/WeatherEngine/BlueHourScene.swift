import SwiftUI

// MARK: - Weather Engine · BlueHourScene (Canvas tier)
//
// The deep blue twilight between sunset and full night. Over the base gradient
// it lays:
//   1. A rich indigo→violet DEEPENING (WeatherSkyGradient) — saturated indigo
//      overhead, a violet cast lower down, so the sky reads as true twilight
//      rather than a washed mid-blue.
//   2. The FIRST STARS just appearing — the shared night star field at a low
//      count and low alpha, so only a faint handful show high in the sky (same
//      deterministic layout as night; blue hour simply shows fewer, fainter).
//   3. A faint warm EMBER still on the horizon on the sun's side — the last of
//      the sunset holding under the blue.
//   4. A calm, cool thin CLOUD band.
//
// No god rays (the sun is gone). Pure gradients + two cheap Canvas passes.
struct BlueHourScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    var body: some View {
        let p = context.parameters
        ZStack {
            // Indigo zenith → violet lower sky.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.05, 0.08, 0.26), zenithStrength: 0.55,
                horizon: WeatherRGB(0.30, 0.16, 0.36), horizonStrength: 0.34,
                zenithSpan: 0.5, horizonStart: 0.52)

            // The first faint stars — few, dim, high.
            if p.starVisibility > 0.05 {
                WeatherStarField(visibility: p.starVisibility, time: context.time,
                                 count: 26, alphaScale: 0.65)
            }

            // The last warm ember low on the horizon, on the sun's side.
            RadialGradient(
                colors: [p.horizonGlow.color(opacity: p.horizonGlowStrength * 0.9),
                         .clear],
                center: UnitPoint(x: p.sunAzimuth, y: 1.02),
                startRadius: 0, endRadius: context.size.width * 0.75)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            // Calm cool cloud band.
            if p.cloudCover > 0.02 {
                CloudField(cover: p.cloudCover,
                           darkness: max(p.cloudDarkness, 0.35),
                           warmth: 0, wind: p.windStrength, time: context.time,
                           band: 0.12...0.42)
            }
        }
        .allowsHitTesting(false)
    }
}

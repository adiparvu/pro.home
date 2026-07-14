import SwiftUI

// MARK: - Weather Engine · CloudsScene (Canvas tier)
//
// A partly-cloudy sky. Over the stage's muted-blue base gradient it lays:
//   1. A gentle blue DEPTH gradient (WeatherSkyGradient) — a touch more saturated
//      overhead, paled with haze along the horizon, so the sky has altitude.
//   2. A diffuse SUN glow seated high — drawn BEHIND the cloud bank, so the
//      cumulus occlude it and the light reads as the sun peeking through.
//   3. Two VOLUMETRIC cumulus layers at different depths (shared CloudField with
//      its `volumetric` knob): a FAR bank (smaller, higher, slower, fainter) and
//      a NEAR bank (larger, lower, faster, fuller). Each cloud gets a shadowed
//      underside and a lit crown, so the field reads as rounded, lit-from-above
//      volume drifting at parallax speeds — not flat blobs.
//
// Pure function of the context; no blur; the softness is baked into the radial
// falloffs. Gentle, bright, three-dimensional — the calm partly-cloudy baseline.
struct CloudsScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// The sun sits high; a lower sky drops it a little. Azimuth places it.
    private var sun: UnitPoint {
        UnitPoint(x: context.parameters.sunAzimuth,
                  y: 0.30 - context.parameters.sunElevation * 0.12)
    }

    var body: some View {
        let p = context.parameters
        ZStack {
            // Muted blue depth: mild zenith, pale hazy horizon.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.30, 0.46, 0.68), zenithStrength: 0.32,
                horizon: WeatherRGB(0.90, 0.93, 0.97), horizonStrength: 0.26,
                zenithSpan: 0.55, horizonStart: 0.62)

            // Diffuse sun behind the bank — the cumulus drift over it.
            RadialGradient(
                colors: [Color.white.opacity(0.5), Color.white.opacity(0.14), .clear],
                center: sun, startRadius: 0, endRadius: context.size.width * 0.5)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // FAR cumulus — smaller/higher/slower/fainter (parallax back).
            CloudField(cover: max(0.35, p.cloudCover * 0.7),
                       darkness: max(p.cloudDarkness, 0.14),
                       warmth: p.lightWarmth * 0.5, wind: p.windStrength * 0.6,
                       time: context.time, band: 0.10...0.34, volumetric: true)
                .opacity(0.85)

            // NEAR cumulus — larger/lower/faster/fuller volume (parallax front).
            // The +30s time offset decorrelates the two layers' drift.
            CloudField(cover: p.cloudCover,
                       darkness: max(p.cloudDarkness, 0.16),
                       warmth: p.lightWarmth * 0.5, wind: p.windStrength,
                       time: context.time + 30, band: 0.30...0.60, volumetric: true)
        }
        .allowsHitTesting(false)
    }
}

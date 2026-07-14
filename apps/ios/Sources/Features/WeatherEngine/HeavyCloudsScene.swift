import SwiftUI

// MARK: - Weather Engine · HeavyCloudsScene (Canvas tier)
//
// A fully overcast sky — a dense low grey deck under flat, diffuse light. Over
// the stage's cool grey base gradient it lays:
//   1. A COLD DESATURATED depth gradient (WeatherSkyGradient) — a grey-blue
//      overhead pulled down to a pale grey horizon, so the palette reads cold
//      and heavy rather than blue.
//   2. The sun reduced to a FAINT bright patch — a very low-opacity glow behind
//      the deck, just enough to say the light has a direction.
//   3. Two FLAT (non-volumetric) grey cloud layers filling most of the frame
//      (shared CloudField, `warmth: 0`, high `darkness`). Flat — deliberately no
//      lit crown / shadowed belly — so the deck reads as even, diffuse overcast
//      light, not a sculpted partly-cloudy sky. The two layers overlap across
//      most of the vertical frame to build a dense, oppressive-but-elegant deck.
//
// Pure function of the context; no blur; soft radial falloffs keep the heavy
// greys from turning muddy. Distinct from CloudsScene (flat + dark + full-frame
// vs. volumetric + bright + partial).
struct HeavyCloudsScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    var body: some View {
        let p = context.parameters
        ZStack {
            // Cold desaturated depth — grey-blue zenith, pale grey horizon.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.30, 0.34, 0.40), zenithStrength: 0.30,
                horizon: WeatherRGB(0.60, 0.63, 0.68), horizonStrength: 0.34,
                zenithSpan: 0.6, horizonStart: 0.5)

            // The sun reduced to a faint bright patch behind the deck.
            RadialGradient(
                colors: [Color.white.opacity(0.16), .clear],
                center: UnitPoint(x: p.sunAzimuth, y: 0.34),
                startRadius: 0, endRadius: context.size.width * 0.55)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Dense low deck — two flat, cold, heavy layers filling most of the
            // frame. Non-volumetric: even diffuse overcast, not sculpted cumulus.
            CloudField(cover: 1.0, darkness: max(p.cloudDarkness, 0.30),
                       warmth: 0, wind: p.windStrength * 0.7,
                       time: context.time, band: 0.0...0.46)
            CloudField(cover: 0.95, darkness: max(p.cloudDarkness, 0.42),
                       warmth: 0, wind: p.windStrength,
                       time: context.time + 50, band: 0.22...0.74)
                .opacity(0.92)
        }
        .allowsHitTesting(false)
    }
}

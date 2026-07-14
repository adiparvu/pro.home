import SwiftUI

// MARK: - Weather Engine · MistScene (Canvas tier)
//
// A light, fine mist — a delicate cool veil, distinctly lighter and more
// transparent than fog. Over the stage's high-key base sky it lays:
//   1. A faint COOL DEPTH gradient (WeatherSkyGradient) at low strength — a soft
//      blue-grey overhead so the SKY STAYS VISIBLE through the haze (fog hides
//      it; mist does not).
//   2. A soft high GLOW — dewy, diffuse, gentle.
//   3. The SAME WeatherFogBank helper fog uses, but at LOW density, a COOLER pale
//      tint and a LOWER band (0.5…1.05) — so only a thin, transparent veil drifts
//      across the lower frame while the upper sky reads clear.
//
// The fog/mist distinction lives entirely in these parameters: fog = high
// density, luminous near-white, banks filling the frame, no visible sky; mist =
// low density, cool pale tint, sparse low banks, sky visible through — lighter,
// higher-key, more transparent. No blur; softness is the banks' radial falloff.
struct MistScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// A cool pale tint — cooler and more transparent than the fog grey.
    private static let mistTint = Color(red: 0.87, green: 0.91, blue: 0.94)

    var body: some View {
        let p = context.parameters
        ZStack {
            // Faint cool depth so the sky still reads blue-grey through the haze.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.62, 0.70, 0.78), zenithStrength: 0.18,
                horizon: WeatherRGB(0.90, 0.93, 0.95), horizonStrength: 0.20,
                zenithSpan: 0.5, horizonStart: 0.55)

            // A soft, dewy high glow.
            RadialGradient(
                colors: [Color.white.opacity(0.16), .clear],
                center: UnitPoint(x: p.sunAzimuth, y: 0.30),
                startRadius: 0, endRadius: context.size.width * 0.55)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // A thin transparent veil — the shared helper at low density, cooler,
            // seated low so the upper sky stays clear.
            WeatherFogBank(density: min(0.6, p.fogDensity * 0.85),
                           tint: Self.mistTint, wind: p.windStrength,
                           time: context.time, band: 0.5...1.05)
        }
        .allowsHitTesting(false)
    }
}

import SwiftUI

// MARK: - Weather Engine · FogScene (Canvas tier)
//
// Thick fog. The stage's base sky is already a pale grey with a white fog wash
// (from `fogDensity`); over it this scene lays:
//   1. A soft diffuse GLOW where the sun would be — a wide, low-contrast bright
//      patch, the only hint of direction in an otherwise even grey.
//   2. Thick layered FOG BANKS (shared WeatherFogBank) at high density and a
//      luminous near-white tint — horizontal banks scrolling at parallax speeds
//      (near faster, far slower) that reduce the sky to a pale luminous grey and
//      let depth read through the stack.
//
// Very low contrast, heavy, luminous. No blur anywhere — the softness is the
// banks' baked radial falloffs (the energy contract for fog). The still frame
// (time frozen) is a valid fog. Shares WeatherFogBank with MistScene, which
// passes a lower density and a cooler tint for the thin veil.
struct FogScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// Luminous near-white grey — reduces the frame to pale, low-contrast fog.
    private static let fogTint = Color(red: 0.92, green: 0.93, blue: 0.94)

    var body: some View {
        let p = context.parameters
        ZStack {
            // Soft diffuse glow where the sun would be.
            RadialGradient(
                colors: [Color.white.opacity(0.28), .clear],
                center: UnitPoint(x: p.sunAzimuth, y: 0.38),
                startRadius: 0, endRadius: context.size.width * 0.6)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Thick parallax banks — dense, luminous, filling the frame.
            WeatherFogBank(density: min(1.0, p.fogDensity),
                           tint: Self.fogTint, wind: p.windStrength,
                           time: context.time, band: 0.24...1.04)
        }
        .allowsHitTesting(false)
    }
}

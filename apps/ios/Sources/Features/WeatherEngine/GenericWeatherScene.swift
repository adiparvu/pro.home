import SwiftUI

// MARK: - Weather Engine · generic parameter scene
//
// The scene for the 16 non-flagship conditions. It is a PURE function of the
// parameter set — it reads nothing but its context — and composes the same
// building blocks the flagship scenes use, so the model is exercised for every
// condition from day one:
//   - CloudField (Canvas)      when cloudCover > 0
//   - GodRayLayer (Metal)      when godRayStrength > 0   (clear/golden/heat/mist)
//   - ComposedRainView         when rainIntensity > 0    (rain / heavyRain / hail)
//   - ComposedSnowView         when snowIntensity > 0    (snow / blizzard)
//   - LightningIlluminationLayer (Metal) when flashEnabled (hail)
//
// The base sky (gradient, horizon glow, fog) is the stage's job; this layer is
// transparent over it. Precipitation mounts only when motion is allowed; the
// still frame shows sky + clouds + rays, which is a faithful representative.
struct GenericWeatherScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    var body: some View {
        let p = context.parameters
        ZStack {
            if p.cloudCover > 0.02 {
                CloudField(cover: p.cloudCover, darkness: p.cloudDarkness,
                           warmth: p.lightWarmth, wind: p.windStrength,
                           time: context.time)
            }

            if p.godRayStrength > 0.001 {
                GodRayLayer(
                    sun: UnitPoint(x: p.sunAzimuth, y: 0.16 + (1 - p.sunElevation) * 0.5),
                    strength: p.godRayStrength,
                    warmth: WeatherLight.color(warmth: p.lightWarmth),
                    time: context.time, size: context.size)
            }

            if context.motionEnabled {
                if p.rainIntensity > 0.02 {
                    // Storm-grade darker drops over the (already dark) rain sky;
                    // heavier conditions ask the shared engine for more live drops.
                    // `.equatable()` so it is not re-evaluated on every stage tick.
                    ComposedRainView(scheme: .dark,
                                     intensity: 1 + p.rainIntensity * 0.6,
                                     isActive: context.isActive)
                        .equatable()
                }
                if p.snowIntensity > 0.02 {
                    ComposedSnowView(intensity: 0.6 + p.snowIntensity * 1.1,
                                     isActive: context.isActive)
                        .equatable()
                }
            }

            if p.flashEnabled {
                LightningIlluminationLayer(origin: context.flashOrigin,
                                           flash: context.flashLevel,
                                           tint: WeatherLight.flashTint,
                                           size: context.size)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shared light colors

/// The warm/cool light color the rays and bloom tint toward, and the storm
/// flash tint — one definition so every scene agrees.
enum WeatherLight {
    /// Cool daylight → warm gold as `warmth` goes 0 → 1.
    static func color(warmth: Double) -> Color {
        let w = min(1, max(0, warmth))
        return Color(red: 0.82 + 0.18 * w,
                     green: 0.86 - 0.04 * w,
                     blue: 1.0 - 0.5 * w)
    }

    /// Cool storm-light — the lightning flash color.
    static let flashTint = Color(red: 0.86, green: 0.90, blue: 1.0)
}

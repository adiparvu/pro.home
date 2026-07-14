import SwiftUI

// MARK: - Weather Engine · the model
//
// The Apple-grade Dynamic Weather Engine renders LIVE weather scenes on top
// of the app's living mood backdrop (AppBackdrop / AppMood). This file is the
// engine's data foundation: the 19 conditions, an interpolatable parameter
// set that fully describes a sky at a moment in time, and the renderer-tier
// map every scene is built against.
//
// FOUNDATION-PHASE SCOPE (read before extending):
// - The engine is NEW and strictly ADDITIVE. It does NOT replace AppBackdrop,
//   AppMood, or AppBackdropEffects. Three flagship scenes prove the three
//   render tiers (SpriteKit / Canvas / Metal); the other 16 conditions render
//   through a generic parameter-driven scene so the model, the cross-dissolve,
//   and the energy contract are all exercised for every case from day one.
// - Every value here is a pure, cheap `struct`/`enum`; nothing observes,
//   allocates per frame, or touches the main-actor UI. The engine
//   (WeatherEngine) owns lifetime; the stage (WeatherStageView) owns frames.
//
// HONESTY (constitution): the parameter defaults are DESIGN values chosen to
// look like Apple Weather (iOS 26) for each named condition — they are not an
// atmospheric-physics simulation and are never presented as measured data.
// The one place real astronomy is computed (the night moon phase) documents
// its source at the call site (WeatherMoonPhase.swift).

// MARK: - WeatherRGB (an interpolatable color)

/// A linear-interpolatable RGB triple. SwiftUI's `Color` is opaque and cannot
/// be blended component-wise, so the parameter set stores colors as explicit
/// channels and resolves to `Color` only at render time. Values are sRGB in
/// 0...1 but interpolation tolerates the extended range, so a lerp never
/// clamps mid-transition (which would read as a hue shift).
struct WeatherRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// Component-wise linear blend. `t` is expected in 0...1 but is not
    /// clamped here — the caller (WeatherParameters.lerp) owns clamping so the
    /// contract is stated in exactly one place.
    static func lerp(_ a: WeatherRGB, _ b: WeatherRGB, _ t: Double) -> WeatherRGB {
        WeatherRGB(a.r + (b.r - a.r) * t,
                   a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    /// The color at a chosen opacity — the ambient layers lean on this so a
    /// glow/fog band fades with its strength, never with a separate layer.
    func color(opacity: Double) -> Color {
        Color(red: r, green: g, blue: b).opacity(opacity)
    }
}

// MARK: - WeatherParameters (a sky, fully described, fully interpolatable)

/// The complete, continuous description of one sky. EVERY field is designed to
/// interpolate: the transition between two conditions is `lerp` of their
/// parameter sets, so the base sky (gradient, horizon glow, fog band, cloud
/// wash) MORPHS smoothly the way Apple Weather's does — it never hard-cuts.
/// The distinctive particle/effect systems (rain, stars, god rays, the bolt)
/// cannot be lerped into one another, so those cross-DISSOLVE by opacity in
/// WeatherStageView; both mechanisms run together, which is the whole
/// transition model (see WeatherEngine.transition).
///
/// Ranges are documented per field. `0...1` fields are unitless design
/// intensities. Bools are discrete and switch at the transition midpoint.
struct WeatherParameters: Equatable, Sendable {
    // The vertical ground gradient — the base of every sky.
    var skyTop: WeatherRGB
    var skyBottom: WeatherRGB

    /// A warm (or cool) band near the horizon — the sunrise/sunset ember, the
    /// storm's bruised underlight. `horizonGlowStrength` (0...1) is its
    /// opacity; 0 removes it with zero cost.
    var horizonGlow: WeatherRGB
    var horizonGlowStrength: Double

    /// Sun height, 0 (below horizon — full night) → 1 (high noon). Drives the
    /// sunrise scene's night→day gradient blend and the god-ray falloff.
    var sunElevation: Double
    /// Sun horizontal position, 0 (leading edge) → 1 (trailing edge). The
    /// origin of the god-ray shafts and the warm-bloom center.
    var sunAzimuth: Double

    /// Light color temperature, 0 (cool/blue) → 1 (warm/gold). Tints clouds,
    /// bloom, and the god rays without touching the sky gradient itself.
    var lightWarmth: Double

    /// Overall particle presence, 0 (none) → 1 (dense). A single dial the
    /// scenes read to scale their own systems; the engine also gates whole
    /// particle scenes on the energy policy, so 0 here means "no particles
    /// even when mounted", not "cheaply mounted".
    var particleIntensity: Double

    /// Cloud sky-coverage, 0 (clear) → 1 (overcast). `cloudDarkness` (0...1)
    /// is how storm-bruised those clouds read — clear clouds are bright, a
    /// thunderhead is near-black.
    var cloudCover: Double
    var cloudDarkness: Double

    /// Fog/mist band opacity, 0 → 1. A soft horizontal wash, not a full-screen
    /// blur (blur is a real compositor cost — see the frame-cost notes).
    var fogDensity: Double

    /// Star-field visibility, 0 (day) → 1 (clear night). Below ~0.15 the night
    /// scene skips the field entirely.
    var starVisibility: Double

    /// Rain / snow / wind design intensities, each 0 → 1. Rain and snow feed
    /// the composed SpriteKit systems; wind biases drift angles and speeds.
    var rainIntensity: Double
    var snowIntensity: Double
    var windStrength: Double

    /// The additive god-ray (volumetric light shaft) strength, 0 → 1. Fed to
    /// the Metal `volumetricLightShaft` shader; 0 means the shaft layer is not
    /// mounted at all.
    var godRayStrength: Double

    /// Whether this condition's scene arms the lightning scheduler. Discrete —
    /// it switches at the transition midpoint rather than fading, because a
    /// half-armed scheduler is meaningless. The live flash is a separate
    /// engine broadcast (`WeatherEngine.flashLevel`), not a parameter.
    var flashEnabled: Bool

    /// Clamped linear blend of two skies. Doubles and colors interpolate;
    /// `flashEnabled` flips at the midpoint. This is the ONLY place `t` is
    /// clamped, so every downstream reader gets a well-formed sky.
    static func lerp(_ a: WeatherParameters, _ b: WeatherParameters,
                     _ t: Double) -> WeatherParameters {
        let u = min(1, max(0, t))
        func f(_ x: Double, _ y: Double) -> Double { x + (y - x) * u }
        return WeatherParameters(
            skyTop: .lerp(a.skyTop, b.skyTop, u),
            skyBottom: .lerp(a.skyBottom, b.skyBottom, u),
            horizonGlow: .lerp(a.horizonGlow, b.horizonGlow, u),
            horizonGlowStrength: f(a.horizonGlowStrength, b.horizonGlowStrength),
            sunElevation: f(a.sunElevation, b.sunElevation),
            sunAzimuth: f(a.sunAzimuth, b.sunAzimuth),
            lightWarmth: f(a.lightWarmth, b.lightWarmth),
            particleIntensity: f(a.particleIntensity, b.particleIntensity),
            cloudCover: f(a.cloudCover, b.cloudCover),
            cloudDarkness: f(a.cloudDarkness, b.cloudDarkness),
            fogDensity: f(a.fogDensity, b.fogDensity),
            starVisibility: f(a.starVisibility, b.starVisibility),
            rainIntensity: f(a.rainIntensity, b.rainIntensity),
            snowIntensity: f(a.snowIntensity, b.snowIntensity),
            windStrength: f(a.windStrength, b.windStrength),
            godRayStrength: f(a.godRayStrength, b.godRayStrength),
            flashEnabled: u < 0.5 ? a.flashEnabled : b.flashEnabled)
    }
}

// MARK: - Renderer tier (documentation + gallery labelling)

/// Which rendering technology a condition's scene leans on. Purely
/// descriptive — it documents the architecture and labels the audition
/// gallery; the engine never branches on it. Composite means a scene layers
/// more than one tier (the thunderstorm is the exemplar: Canvas clouds +
/// SpriteKit rain + Metal illumination).
enum WeatherRendererTier: String, Sendable {
    case canvas = "Canvas"
    case spriteKit = "SpriteKit"
    case metal = "Metal"
    case composite = "Composite"

    /// A one-line human summary for the gallery's technical caption.
    var subtitle: String {
        switch self {
        case .canvas:    "Canvas 2D"
        case .spriteKit: "SpriteKit particles"
        case .metal:     "Metal shader"
        case .composite: "Canvas · SpriteKit · Metal"
        }
    }
}

// MARK: - WeatherCondition (all 19)

/// The 19 named skies the engine can render. `CaseIterable` order is the
/// gallery's display order — grouped by daylight arc, then cloud/precip, then
/// the extremes — so an on-device audition reads as a coherent tour.
///
/// RENDERER-TIER MAP (documented per case in `tier`; the three flagship
/// scenes that fully realise a tier are marked ★):
///   clearDay      Metal      — god rays over a clean gradient
///   goldenHour    Metal      — warm god rays + bloom
///   sunrise    ★  Composite  — night→day gradient + Metal rays + fog + clouds
///   sunset        Composite  — mirror of sunrise, sun descending
///   blueHour      Canvas     — cool gradient + faint early stars
///   night      ★  Composite  — Canvas star field + real moon phase + clouds
///   fullMoon      Composite  — night with the moon forced full & bright
///   clouds        Canvas     — drifting soft cloud field
///   heavyClouds   Canvas     — dense, low, darker cloud field
///   fog           Canvas     — layered fog bands
///   mist          Canvas     — lighter, higher fog
///   rain          Composite  — SpriteKit rain + Metal lens refraction
///   heavyRain     Composite  — denser rain + stronger lens refraction
///   thunderstorm ★ Composite — Canvas storm clouds + SpriteKit rain + Metal
///                              lightning illumination + bolt stroke
///   snow          SpriteKit  — parallax flake system
///   blizzard      SpriteKit  — dense wind-driven flakes
///   wind          Canvas     — fast streaked cloud wisps
///   hail          Composite  — hard SpriteKit pellets + flash accents
///   heatWave      Metal      — heat-shimmer distortion over a hazy sky
enum WeatherCondition: String, CaseIterable, Identifiable, Sendable {
    case clearDay, goldenHour, sunrise, sunset, blueHour, night, fullMoon
    case clouds, heavyClouds, fog, mist
    case rain, heavyRain, thunderstorm
    case snow, blizzard, wind, hail, heatWave

    var id: String { rawValue }

    /// Localized display name (RO/EN via Localizable.xcstrings, `weather_cond_*`).
    var displayNameKey: LocalizedStringKey {
        switch self {
        case .clearDay:     "weather_cond_clear_day"
        case .goldenHour:   "weather_cond_golden_hour"
        case .sunrise:      "weather_cond_sunrise"
        case .sunset:       "weather_cond_sunset"
        case .blueHour:     "weather_cond_blue_hour"
        case .night:        "weather_cond_night"
        case .fullMoon:     "weather_cond_full_moon"
        case .clouds:       "weather_cond_clouds"
        case .heavyClouds:  "weather_cond_heavy_clouds"
        case .fog:          "weather_cond_fog"
        case .mist:         "weather_cond_mist"
        case .rain:         "weather_cond_rain"
        case .heavyRain:    "weather_cond_heavy_rain"
        case .thunderstorm: "weather_cond_thunderstorm"
        case .snow:         "weather_cond_snow"
        case .blizzard:     "weather_cond_blizzard"
        case .wind:         "weather_cond_wind"
        case .hail:         "weather_cond_hail"
        case .heatWave:     "weather_cond_heat_wave"
        }
    }

    /// A resolved `String` for accessibility labels and gallery rows.
    var displayName: String {
        String(localized: String.LocalizationValue(displayNameKeyRaw))
    }

    /// The raw catalog key (the `LocalizedStringKey` above is not readable as a
    /// String, so the key is restated once here for `String(localized:)`).
    private var displayNameKeyRaw: String {
        switch self {
        case .clearDay:     "weather_cond_clear_day"
        case .goldenHour:   "weather_cond_golden_hour"
        case .sunrise:      "weather_cond_sunrise"
        case .sunset:       "weather_cond_sunset"
        case .blueHour:     "weather_cond_blue_hour"
        case .night:        "weather_cond_night"
        case .fullMoon:     "weather_cond_full_moon"
        case .clouds:       "weather_cond_clouds"
        case .heavyClouds:  "weather_cond_heavy_clouds"
        case .fog:          "weather_cond_fog"
        case .mist:         "weather_cond_mist"
        case .rain:         "weather_cond_rain"
        case .heavyRain:    "weather_cond_heavy_rain"
        case .thunderstorm: "weather_cond_thunderstorm"
        case .snow:         "weather_cond_snow"
        case .blizzard:     "weather_cond_blizzard"
        case .wind:         "weather_cond_wind"
        case .hail:         "weather_cond_hail"
        case .heatWave:     "weather_cond_heat_wave"
        }
    }

    /// An SF Symbol standing in for the condition — used by the gallery rows
    /// and any compact chip. Chosen from the WeatherKit-aligned symbol set.
    var symbolName: String {
        switch self {
        case .clearDay:     "sun.max.fill"
        case .goldenHour:   "sun.and.horizon.fill"
        case .sunrise:      "sunrise.fill"
        case .sunset:       "sunset.fill"
        case .blueHour:     "moon.haze.fill"
        case .night:        "moon.stars.fill"
        case .fullMoon:     "moon.fill"
        case .clouds:       "cloud.fill"
        case .heavyClouds:  "smoke.fill"
        case .fog:          "cloud.fog.fill"
        case .mist:         "cloud.fog"
        case .rain:         "cloud.rain.fill"
        case .heavyRain:    "cloud.heavyrain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .snow:         "cloud.snow.fill"
        case .blizzard:     "wind.snow"
        case .wind:         "wind"
        case .hail:         "cloud.hail.fill"
        case .heatWave:     "thermometer.sun.fill"
        }
    }

    /// The renderer tier this condition's scene targets (documentation only —
    /// see the map in the type comment).
    var tier: WeatherRendererTier {
        switch self {
        case .clearDay, .goldenHour, .heatWave:
            return .metal
        case .blueHour, .clouds, .heavyClouds, .fog, .mist, .wind:
            return .canvas
        case .snow, .blizzard:
            return .spriteKit
        case .sunrise, .sunset, .night, .fullMoon,
             .rain, .heavyRain, .thunderstorm, .hail:
            return .composite
        }
    }

    /// True for the three scenes that are hand-built this phase to fully
    /// realise their tier; the rest render through the generic parameter
    /// scene. The gallery marks these so an auditor knows what to scrutinise.
    var isFlagship: Bool {
        self == .sunrise || self == .night || self == .thunderstorm
    }
}

// MARK: - Default parameters per condition

extension WeatherCondition {
    /// The DESIGN parameter set for this condition — the sky the engine snaps
    /// to when the condition is set with no transition, and the endpoints the
    /// cross-dissolve interpolates between. Tuned by eye against Apple Weather
    /// (iOS 26); every value is a design choice, not a measurement.
    var parameters: WeatherParameters {
        switch self {
        case .clearDay:
            return WeatherParameters(
                skyTop: WeatherRGB(0.325, 0.60, 0.86),
                skyBottom: WeatherRGB(0.68, 0.83, 0.95),
                horizonGlow: WeatherRGB(0.98, 0.95, 0.85), horizonGlowStrength: 0.18,
                sunElevation: 0.92, sunAzimuth: 0.72, lightWarmth: 0.45,
                particleIntensity: 0, cloudCover: 0.08, cloudDarkness: 0,
                fogDensity: 0, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.1,
                godRayStrength: 0.35, flashEnabled: false)

        case .goldenHour:
            return WeatherParameters(
                skyTop: WeatherRGB(0.42, 0.44, 0.62),
                skyBottom: WeatherRGB(0.98, 0.74, 0.46),
                horizonGlow: WeatherRGB(1.0, 0.80, 0.48), horizonGlowStrength: 0.5,
                sunElevation: 0.30, sunAzimuth: 0.80, lightWarmth: 0.92,
                particleIntensity: 0, cloudCover: 0.16, cloudDarkness: 0.05,
                fogDensity: 0.06, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.1,
                godRayStrength: 0.7, flashEnabled: false)

        case .sunrise:
            return WeatherParameters(
                skyTop: WeatherRGB(0.20, 0.26, 0.44),
                skyBottom: WeatherRGB(0.98, 0.70, 0.50),
                horizonGlow: WeatherRGB(1.0, 0.72, 0.44), horizonGlowStrength: 0.6,
                sunElevation: 0.16, sunAzimuth: 0.30, lightWarmth: 0.85,
                particleIntensity: 0, cloudCover: 0.22, cloudDarkness: 0.04,
                fogDensity: 0.22, starVisibility: 0.10,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.08,
                godRayStrength: 0.75, flashEnabled: false)

        case .sunset:
            return WeatherParameters(
                skyTop: WeatherRGB(0.24, 0.22, 0.42),
                skyBottom: WeatherRGB(0.96, 0.58, 0.40),
                horizonGlow: WeatherRGB(1.0, 0.60, 0.36), horizonGlowStrength: 0.62,
                sunElevation: 0.13, sunAzimuth: 0.70, lightWarmth: 0.88,
                particleIntensity: 0, cloudCover: 0.26, cloudDarkness: 0.06,
                fogDensity: 0.18, starVisibility: 0.12,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.08,
                godRayStrength: 0.68, flashEnabled: false)

        case .blueHour:
            return WeatherParameters(
                skyTop: WeatherRGB(0.10, 0.14, 0.30),
                skyBottom: WeatherRGB(0.30, 0.36, 0.56),
                horizonGlow: WeatherRGB(0.85, 0.62, 0.55), horizonGlowStrength: 0.28,
                sunElevation: 0.06, sunAzimuth: 0.68, lightWarmth: 0.5,
                particleIntensity: 0, cloudCover: 0.2, cloudDarkness: 0.12,
                fogDensity: 0.14, starVisibility: 0.4,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.06,
                godRayStrength: 0.1, flashEnabled: false)

        case .night:
            return WeatherParameters(
                skyTop: WeatherRGB(0.045, 0.055, 0.11),
                skyBottom: WeatherRGB(0.10, 0.12, 0.20),
                horizonGlow: WeatherRGB(0.30, 0.34, 0.48), horizonGlowStrength: 0.12,
                sunElevation: 0, sunAzimuth: 0.5, lightWarmth: 0.3,
                particleIntensity: 0, cloudCover: 0.14, cloudDarkness: 0.3,
                fogDensity: 0.04, starVisibility: 1.0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.05,
                godRayStrength: 0, flashEnabled: false)

        case .fullMoon:
            return WeatherParameters(
                skyTop: WeatherRGB(0.06, 0.08, 0.16),
                skyBottom: WeatherRGB(0.13, 0.16, 0.26),
                horizonGlow: WeatherRGB(0.42, 0.48, 0.62), horizonGlowStrength: 0.18,
                sunElevation: 0, sunAzimuth: 0.5, lightWarmth: 0.34,
                particleIntensity: 0, cloudCover: 0.10, cloudDarkness: 0.22,
                fogDensity: 0.03, starVisibility: 0.8,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.04,
                godRayStrength: 0, flashEnabled: false)

        case .clouds:
            return WeatherParameters(
                skyTop: WeatherRGB(0.55, 0.62, 0.72),
                skyBottom: WeatherRGB(0.78, 0.83, 0.89),
                horizonGlow: WeatherRGB(0.90, 0.90, 0.92), horizonGlowStrength: 0.12,
                sunElevation: 0.6, sunAzimuth: 0.6, lightWarmth: 0.4,
                particleIntensity: 0, cloudCover: 0.6, cloudDarkness: 0.12,
                fogDensity: 0.08, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.2,
                godRayStrength: 0.08, flashEnabled: false)

        case .heavyClouds:
            return WeatherParameters(
                skyTop: WeatherRGB(0.36, 0.40, 0.47),
                skyBottom: WeatherRGB(0.55, 0.59, 0.65),
                horizonGlow: WeatherRGB(0.66, 0.68, 0.72), horizonGlowStrength: 0.12,
                sunElevation: 0.45, sunAzimuth: 0.55, lightWarmth: 0.32,
                particleIntensity: 0, cloudCover: 0.9, cloudDarkness: 0.35,
                fogDensity: 0.14, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.3,
                godRayStrength: 0, flashEnabled: false)

        case .fog:
            return WeatherParameters(
                skyTop: WeatherRGB(0.62, 0.65, 0.68),
                skyBottom: WeatherRGB(0.80, 0.82, 0.84),
                horizonGlow: WeatherRGB(0.88, 0.89, 0.90), horizonGlowStrength: 0.2,
                sunElevation: 0.4, sunAzimuth: 0.5, lightWarmth: 0.36,
                particleIntensity: 0, cloudCover: 0.3, cloudDarkness: 0.1,
                fogDensity: 0.85, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.08,
                godRayStrength: 0.05, flashEnabled: false)

        case .mist:
            return WeatherParameters(
                skyTop: WeatherRGB(0.70, 0.74, 0.77),
                skyBottom: WeatherRGB(0.85, 0.88, 0.90),
                horizonGlow: WeatherRGB(0.92, 0.93, 0.94), horizonGlowStrength: 0.16,
                sunElevation: 0.5, sunAzimuth: 0.55, lightWarmth: 0.42,
                particleIntensity: 0, cloudCover: 0.22, cloudDarkness: 0.06,
                fogDensity: 0.5, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.1,
                godRayStrength: 0.06, flashEnabled: false)

        case .rain:
            return WeatherParameters(
                skyTop: WeatherRGB(0.34, 0.40, 0.48),
                skyBottom: WeatherRGB(0.52, 0.58, 0.64),
                horizonGlow: WeatherRGB(0.62, 0.66, 0.70), horizonGlowStrength: 0.1,
                sunElevation: 0.4, sunAzimuth: 0.5, lightWarmth: 0.3,
                particleIntensity: 0.6, cloudCover: 0.8, cloudDarkness: 0.3,
                fogDensity: 0.16, starVisibility: 0,
                rainIntensity: 0.6, snowIntensity: 0, windStrength: 0.3,
                godRayStrength: 0, flashEnabled: false)

        case .heavyRain:
            return WeatherParameters(
                skyTop: WeatherRGB(0.24, 0.28, 0.35),
                skyBottom: WeatherRGB(0.40, 0.45, 0.52),
                horizonGlow: WeatherRGB(0.50, 0.54, 0.60), horizonGlowStrength: 0.08,
                sunElevation: 0.32, sunAzimuth: 0.5, lightWarmth: 0.26,
                particleIntensity: 0.95, cloudCover: 0.95, cloudDarkness: 0.42,
                fogDensity: 0.22, starVisibility: 0,
                rainIntensity: 0.95, snowIntensity: 0, windStrength: 0.5,
                godRayStrength: 0, flashEnabled: false)

        case .thunderstorm:
            return WeatherParameters(
                skyTop: WeatherRGB(0.14, 0.16, 0.22),
                skyBottom: WeatherRGB(0.26, 0.29, 0.36),
                horizonGlow: WeatherRGB(0.44, 0.42, 0.55), horizonGlowStrength: 0.14,
                sunElevation: 0.22, sunAzimuth: 0.5, lightWarmth: 0.24,
                particleIntensity: 0.9, cloudCover: 1.0, cloudDarkness: 0.6,
                fogDensity: 0.2, starVisibility: 0,
                rainIntensity: 0.85, snowIntensity: 0, windStrength: 0.55,
                godRayStrength: 0, flashEnabled: true)

        case .snow:
            return WeatherParameters(
                skyTop: WeatherRGB(0.64, 0.70, 0.78),
                skyBottom: WeatherRGB(0.84, 0.88, 0.92),
                horizonGlow: WeatherRGB(0.92, 0.94, 0.97), horizonGlowStrength: 0.16,
                sunElevation: 0.5, sunAzimuth: 0.5, lightWarmth: 0.34,
                particleIntensity: 0.55, cloudCover: 0.7, cloudDarkness: 0.14,
                fogDensity: 0.12, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0.6, windStrength: 0.18,
                godRayStrength: 0, flashEnabled: false)

        case .blizzard:
            return WeatherParameters(
                skyTop: WeatherRGB(0.56, 0.62, 0.70),
                skyBottom: WeatherRGB(0.78, 0.82, 0.87),
                horizonGlow: WeatherRGB(0.90, 0.92, 0.95), horizonGlowStrength: 0.14,
                sunElevation: 0.42, sunAzimuth: 0.5, lightWarmth: 0.3,
                particleIntensity: 1.0, cloudCover: 0.9, cloudDarkness: 0.2,
                fogDensity: 0.34, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 1.0, windStrength: 0.85,
                godRayStrength: 0, flashEnabled: false)

        case .wind:
            return WeatherParameters(
                skyTop: WeatherRGB(0.48, 0.58, 0.70),
                skyBottom: WeatherRGB(0.72, 0.80, 0.87),
                horizonGlow: WeatherRGB(0.88, 0.90, 0.92), horizonGlowStrength: 0.12,
                sunElevation: 0.6, sunAzimuth: 0.6, lightWarmth: 0.4,
                particleIntensity: 0.2, cloudCover: 0.5, cloudDarkness: 0.1,
                fogDensity: 0.06, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 1.0,
                godRayStrength: 0.1, flashEnabled: false)

        case .hail:
            return WeatherParameters(
                skyTop: WeatherRGB(0.30, 0.34, 0.42),
                skyBottom: WeatherRGB(0.48, 0.53, 0.60),
                horizonGlow: WeatherRGB(0.58, 0.62, 0.68), horizonGlowStrength: 0.1,
                sunElevation: 0.34, sunAzimuth: 0.5, lightWarmth: 0.28,
                particleIntensity: 0.7, cloudCover: 0.92, cloudDarkness: 0.44,
                fogDensity: 0.12, starVisibility: 0,
                rainIntensity: 0.2, snowIntensity: 0, windStrength: 0.45,
                godRayStrength: 0, flashEnabled: true)

        case .heatWave:
            return WeatherParameters(
                skyTop: WeatherRGB(0.55, 0.66, 0.86),
                skyBottom: WeatherRGB(0.95, 0.86, 0.62),
                horizonGlow: WeatherRGB(1.0, 0.88, 0.60), horizonGlowStrength: 0.4,
                sunElevation: 0.98, sunAzimuth: 0.55, lightWarmth: 0.85,
                particleIntensity: 0, cloudCover: 0.04, cloudDarkness: 0,
                fogDensity: 0.28, starVisibility: 0,
                rainIntensity: 0, snowIntensity: 0, windStrength: 0.05,
                godRayStrength: 0.5, flashEnabled: false)
        }
    }
}

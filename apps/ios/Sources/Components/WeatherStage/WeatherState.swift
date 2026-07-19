import Foundation

// MARK: - WeatherStage: the real-time weather backdrop's state model (F1)
//
// The living background returns (user-decreed, 2026-07-20) as a REAL-TIME
// weather engine: everything procedural on the GPU (SkyShaders.metal), no
// pre-rendered assets, driven by the property's REAL weather (the cached
// Apple WeatherKit summary PropertyWeather already maintains — honest-data:
// stale cache ≥ 2h claims nothing) and the REAL sun window (the same
// low-precision solar model the mood engine used, kept in AppMood.swift).
//
// F1 states cover the day cycle + core precipitation. Storm gets the
// whole-sky exposure flash in F1; branching bolts, sandstorm, blizzard,
// after-rain rainbow and the gyroscope lens droplets are F2–F4.

enum WeatherCondition: Equatable {
    case clear          // sun/moon + sparse clouds
    case cloudy         // overcast blanket, softened light
    case fog            // dense low-contrast veil
    case rain           // procedural rain layers
    case storm          // rain + exposure lightning flashes
    case snow           // procedural flakes, cold cast

    /// Maps the cached WeatherKit SF symbol through the same buckets the
    /// retired mood engine proved out (AppWeatherTone), extended with the
    /// storm/fog splits this engine renders distinctly.
    static func from(symbol: String?) -> WeatherCondition {
        guard let s = symbol?.lowercased() else { return .clear }
        if ["bolt", "storm", "hurricane", "tropical"].contains(where: s.contains) { return .storm }
        if ["snow", "sleet", "flurr", "blizzard", "flake"].contains(where: s.contains) { return .snow }
        if ["rain", "drizzle", "hail"].contains(where: s.contains) { return .rain }
        if ["fog", "haze", "smoke", "dust"].contains(where: s.contains) { return .fog }
        if s.contains("cloud") { return .cloudy }
        return .clear
    }
}

/// Everything the sky shader needs for one frame, as plain scalars — the
/// engine interpolates BETWEEN two of these over the 2–5s transition, so
/// state changes are a single smooth cross-anim, never a cut.
struct WeatherStageParams: Equatable {
    /// Sun elevation proxy in [-1, 1]: -1 deep night, 0 at the horizon
    /// (sunrise/sunset), 1 high noon. Drives the whole sky gradient,
    /// star visibility and the warm horizon band.
    var sunElevation: Double
    /// Horizontal sun position hint in [0, 1] (morning left → evening
    /// right) so golden hour lights the correct side.
    var sunAzimuth: Double
    /// Cloud cover in [0, 1] — fBM layer density and light softening.
    var cloudiness: Double
    /// Rain intensity in [0, 1] (streak layers + atmosphere darkening).
    var rain: Double
    /// Snow intensity in [0, 1] (flake layers + cold, bright cast).
    var snow: Double
    /// Fog thickness in [0, 1] (contrast collapse + moving veil).
    var fog: Double
    /// 1 when lightning may fire: the shader hashes absolute time into
    /// rare, non-repeating whole-sky exposure flashes.
    var storm: Double
    /// Moon phase in [0, 1] (0 new, 0.5 full) — rendered at night only.
    var moonPhase: Double

    static let zero = WeatherStageParams(sunElevation: 0.6, sunAzimuth: 0.5,
                                         cloudiness: 0.2, rain: 0, snow: 0,
                                         fog: 0, storm: 0, moonPhase: 0.5)

    static func lerp(_ a: WeatherStageParams, _ b: WeatherStageParams,
                     _ t: Double) -> WeatherStageParams {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return WeatherStageParams(
            sunElevation: mix(a.sunElevation, b.sunElevation),
            sunAzimuth:   mix(a.sunAzimuth,   b.sunAzimuth),
            cloudiness:   mix(a.cloudiness,   b.cloudiness),
            rain:         mix(a.rain,         b.rain),
            snow:         mix(a.snow,         b.snow),
            fog:          mix(a.fog,          b.fog),
            storm:        mix(a.storm,        b.storm),
            moonPhase:    mix(a.moonPhase,    b.moonPhase))
    }

    /// Target params for a condition at a given sun position. Cloud cover
    /// and darkening are the physically sensible companions of each state
    /// (a storm without a heavy deck would read as fantasy — banned).
    static func target(condition: WeatherCondition, sunElevation: Double,
                       sunAzimuth: Double, moonPhase: Double) -> WeatherStageParams {
        var p = WeatherStageParams(sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                                   cloudiness: 0.18, rain: 0, snow: 0, fog: 0,
                                   storm: 0, moonPhase: moonPhase)
        switch condition {
        case .clear:  break
        case .cloudy: p.cloudiness = 0.75
        case .fog:    p.cloudiness = 0.55; p.fog = 0.8
        case .rain:   p.cloudiness = 0.9;  p.rain = 0.7
        case .storm:  p.cloudiness = 1.0;  p.rain = 1.0; p.storm = 1
        case .snow:   p.cloudiness = 0.8;  p.snow = 0.8
        }
        return p
    }

    /// Approximate lunar phase from the synodic month — plenty for a
    /// backdrop moon (no ephemeris claims; the terminator is cosmetic).
    static func moonPhase(on date: Date) -> Double {
        // Reference new moon: 2000-01-06 18:14 UTC; synodic month 29.53059d.
        let reference = Date(timeIntervalSince1970: 947_182_440)
        let days = date.timeIntervalSince(reference) / 86_400
        let phase = (days / 29.53059).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }
}

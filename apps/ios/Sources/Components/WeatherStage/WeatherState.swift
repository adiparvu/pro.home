import Foundation

// MARK: - WeatherStage: the real-time weather backdrop's state model (F1–F4)
//
// The living background returns (user-decreed, 2026-07-20) as a REAL-TIME
// weather engine: everything procedural on the GPU (SkyShaders.metal), no
// pre-rendered assets, driven by the property's REAL weather (the cached
// Apple WeatherKit summary PropertyWeather already maintains — honest-data:
// stale cache ≥ 2h claims nothing) and the REAL sun window (the same
// low-precision solar model the mood engine used, kept in AppMood.swift).
//
// F1 covered the day cycle + core precipitation. F2 adds the WIND scalar
// (real magnitude+direction from the summary — calm when the cache carries
// none) and the lens-droplet inputs. F3 splits BLIZZARD out of snow. F4
// splits SANDSTORM out of fog and adds the rainbow/firefly scalars the
// engine gates from real conditions.

enum WeatherCondition: Equatable {
    case clear          // sun/moon + sparse clouds
    case cloudy         // overcast blanket, softened light
    case fog            // dense low-contrast veil
    case rain           // procedural rain layers
    case storm          // rain + exposure lightning + branching bolts
    case snow           // procedural flakes, cold cast
    case blizzard       // snow owned by the wind: streaks + white-out
    case sandstorm      // ochre flow + airborne grain

    /// Maps the cached WeatherKit SF symbol through the same buckets the
    /// retired mood engine proved out (AppWeatherTone), extended with the
    /// storm/fog/blizzard/sandstorm splits this engine renders distinctly.
    static func from(symbol: String?) -> WeatherCondition {
        guard let s = symbol?.lowercased() else { return .clear }
        if s.contains("blizzard") { return .blizzard }
        if ["bolt", "storm", "hurricane", "tropical"].contains(where: s.contains) { return .storm }
        if ["snow", "sleet", "flurr", "flake"].contains(where: s.contains) { return .snow }
        if ["rain", "drizzle", "hail"].contains(where: s.contains) { return .rain }
        if ["dust", "sand"].contains(where: s.contains) { return .sandstorm }
        if ["fog", "haze", "smoke"].contains(where: s.contains) { return .fog }
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
    /// rare, non-repeating exposure flashes and branching bolts.
    var storm: Double
    /// Moon phase in [0, 1] (0 new, 0.5 full) — rendered at night only.
    var moonPhase: Double
    /// Signed wind in [-1, 1]: magnitude from the summary's real speed,
    /// sign from its direction's screen-space east/west component. 0 when
    /// the cache carries no wind — calm is the honest default. Shears
    /// rain, drives snow (blizzard past ~0.5 with heavy snow), hurries
    /// clouds and fog.
    var wind: Double
    /// Sandstorm density in [0, 1] (dust/sand symbols only).
    var sand: Double
    /// After-rain rainbow strength in [0, 1] — the ENGINE owns the state
    /// machine (rain just ended + sun up); the shader only paints the arc.
    var rainbow: Double
    /// Firefly amount in [0, 1] — gated in Swift to clear warm summer
    /// nights with a FRESH temperature reading; never invented.
    var fireflies: Double

    static let zero = WeatherStageParams(sunElevation: 0.6, sunAzimuth: 0.5,
                                         cloudiness: 0.2, rain: 0, snow: 0,
                                         fog: 0, storm: 0, moonPhase: 0.5,
                                         wind: 0, sand: 0, rainbow: 0,
                                         fireflies: 0)

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
            moonPhase:    mix(a.moonPhase,    b.moonPhase),
            wind:         mix(a.wind,         b.wind),
            sand:         mix(a.sand,         b.sand),
            rainbow:      mix(a.rainbow,      b.rainbow),
            fireflies:    mix(a.fireflies,    b.fireflies))
    }

    /// Target params for a condition at a given sun position. Cloud cover
    /// and darkening are the physically sensible companions of each state
    /// (a storm without a heavy deck would read as fantasy — banned).
    /// `wind` is the real reported wind; blizzard and sandstorm floor its
    /// magnitude because those states ARE wind by definition.
    static func target(condition: WeatherCondition, sunElevation: Double,
                       sunAzimuth: Double, moonPhase: Double,
                       wind: Double) -> WeatherStageParams {
        var p = WeatherStageParams(sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                                   cloudiness: 0.18, rain: 0, snow: 0, fog: 0,
                                   storm: 0, moonPhase: moonPhase, wind: wind,
                                   sand: 0, rainbow: 0, fireflies: 0)
        func floored(_ w: Double, to magnitude: Double) -> Double {
            abs(w) >= magnitude ? w : (w < 0 ? -magnitude : magnitude)
        }
        switch condition {
        case .clear:     break
        case .cloudy:    p.cloudiness = 0.75
        case .fog:       p.cloudiness = 0.55; p.fog = 0.8
        case .rain:      p.cloudiness = 0.9;  p.rain = 0.7
        case .storm:     p.cloudiness = 1.0;  p.rain = 1.0; p.storm = 1
        case .snow:      p.cloudiness = 0.8;  p.snow = 0.8
        case .blizzard:
            p.cloudiness = 1.0; p.snow = 1.0; p.fog = 0.3
            p.wind = floored(wind, to: 0.7)
        case .sandstorm:
            p.cloudiness = 0.6; p.sand = 1.0
            p.wind = floored(wind, to: 0.45)
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

// MARK: - The Fundal page's contract (pin + toggles)
//
// The weather stage is Automat by default — real sun, real weather. The
// Fundal settings page can PIN one atmosphere (a time of day under a clear
// sky, or a weather state under the real sun), switch the particle effects
// off, or stop reacting to live weather (the engine then paints a clear
// sky by time alone). Preferences read straight from UserDefaults so the
// engine, the page and its preview tiles share one authority.

enum WeatherStagePreset: String, CaseIterable, Identifiable {
    // Time pins — a clear sky frozen at that hour's light.
    case morning, day, sunset, night
    // Weather pins — the REAL sun under the chosen weather.
    case cloudy, fog, rain, storm, snow, blizzard, sandstorm

    var id: String { rawValue }

    /// Params for this pin given the live context (real sun for weather
    /// pins, real moon always, real wind when known).
    func params(sunElevation: Double, sunAzimuth: Double,
                moonPhase: Double, wind: Double) -> WeatherStageParams {
        switch self {
        case .morning:
            return .target(condition: .clear, sunElevation: 0.12, sunAzimuth: 0.25,
                           moonPhase: moonPhase, wind: wind)
        case .day:
            return .target(condition: .clear, sunElevation: 0.85, sunAzimuth: 0.5,
                           moonPhase: moonPhase, wind: wind)
        case .sunset:
            return .target(condition: .clear, sunElevation: 0.02, sunAzimuth: 0.8,
                           moonPhase: moonPhase, wind: wind)
        case .night:
            return .target(condition: .clear, sunElevation: -0.75, sunAzimuth: 0.5,
                           moonPhase: moonPhase, wind: wind)
        case .cloudy:
            return .target(condition: .cloudy, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        case .fog:
            return .target(condition: .fog, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        case .rain:
            return .target(condition: .rain, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        case .storm:
            return .target(condition: .storm, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        case .snow:
            return .target(condition: .snow, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        case .blizzard:
            return .target(condition: .blizzard, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        case .sandstorm:
            return .target(condition: .sandstorm, sunElevation: sunElevation, sunAzimuth: sunAzimuth,
                           moonPhase: moonPhase, wind: wind)
        }
    }
}

enum WeatherStagePrefs {
    private static let presetKey = "weather.stage.preset"
    private static let effectsKey = "weather.stage.effects"

    /// The pinned atmosphere; nil = Automat (real sun + real weather).
    static var preset: WeatherStagePreset? {
        get {
            UserDefaults.standard.string(forKey: presetKey)
                .flatMap(WeatherStagePreset.init(rawValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: presetKey)
            } else {
                UserDefaults.standard.removeObject(forKey: presetKey)
            }
        }
    }

    /// The particle layers (rain/snow streaks, bolts, droplets, sand grain,
    /// fireflies). Off leaves the sky's body — light, clouds, fog — intact.
    static var effectsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: effectsKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: effectsKey) }
    }
}

extension WeatherStageParams {
    /// Zeroes every particle layer (the Efecte atmosferice toggle). The
    /// sky's body — gradient, clouds, fog veil — stays truthful.
    mutating func stripEffects() {
        rain = 0; snow = 0; storm = 0; sand = 0; fireflies = 0
    }
}

// MARK: - CPU mirror of the sky gradient (F4 — widget/watch snapshots)
//
// Widgets archive static views and the watch is another device: neither can
// run the fragment pass. This mirrors ONLY the shader's base gradient math
// (day/night/dusk zenith+horizon, cloud/fog/rain/sand attenuation) so the
// phone can publish two honest colors that read as "the same sky, frozen".

extension WeatherStageParams {
    typealias RGB = (r: Double, g: Double, b: Double)

    var snapshotColors: (top: RGB, bottom: RGB) {
        func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
            let t = max(0, min((x - e0) / (e1 - e0), 1))
            return t * t * (3 - 2 * t)
        }
        func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
        }
        let day = smoothstep(-0.12, 0.35, sunElevation)
        let dusk = exp(-pow(sunElevation * 3.2, 2))

        var zenith  = mix((0.010, 0.016, 0.042), (0.16, 0.38, 0.72), day)
        var horizon = mix((0.045, 0.060, 0.110), (0.62, 0.78, 0.92), day)
        horizon = mix(horizon, (0.98, 0.55, 0.26), dusk * 0.55)
        zenith  = mix(zenith,  (0.42, 0.27, 0.45), dusk * 0.35)

        // Condition attenuation — the same visual weights the shader uses,
        // collapsed to the gradient endpoints.
        let cloudLit: RGB = mix((0.10, 0.11, 0.14), (0.90, 0.89, 0.89), day)
        zenith  = mix(zenith,  cloudLit, cloudiness * 0.5)
        horizon = mix(horizon, cloudLit, cloudiness * 0.4)
        if rain > 0 {
            zenith  = mix(zenith,  (zenith.r * 0.7,  zenith.g * 0.72,  zenith.b * 0.78),  rain)
            horizon = mix(horizon, (horizon.r * 0.7, horizon.g * 0.72, horizon.b * 0.78), rain)
        }
        if fog > 0 {
            let fogCol: RGB = mix((0.09, 0.10, 0.12), (0.82, 0.84, 0.87), day)
            zenith  = mix(zenith,  fogCol, fog * 0.6)
            horizon = mix(horizon, fogCol, fog * 0.7)
        }
        if sand > 0 {
            let ochre: RGB = mix((0.42, 0.32, 0.20), (0.80, 0.64, 0.42), day)
            zenith  = mix(zenith,  ochre, sand * 0.7)
            horizon = mix(horizon, ochre, sand * 0.8)
        }
        if snow > 0 {
            zenith  = mix(zenith,  (0.62, 0.66, 0.72), snow * 0.35 * day)
            horizon = mix(horizon, (0.72, 0.75, 0.80), snow * 0.4 * day)
        }
        return (zenith, horizon)
    }

    /// Whether snapshot consumers should render LIGHT content over this sky
    /// (dark ground → `.dark` color scheme → white primary text).
    var snapshotWantsDarkScheme: Bool {
        let (_, bottom) = snapshotColors
        let luma = 0.299 * bottom.r + 0.587 * bottom.g + 0.114 * bottom.b
        return luma < 0.5
    }
}

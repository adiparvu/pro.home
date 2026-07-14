import SwiftUI
import Observation

// MARK: - Weather Engine · the engine
//
// The single authority on which weather sky the app is showing and how it is
// moving between skies. It is a shared, main-actor `@Observable` so any
// surface — the stage, a future Liquid Glass card that brightens with
// lightning, the audition gallery — reads the same live state.
//
// TRANSITION MODEL (the core contract):
//   `current` is the condition being shown. A `transition(to:)` NEVER hard-
//   cuts: it records the outgoing condition in `previous`, stamps
//   `transitionStart`, and releases `previous` when the dissolve ends. Progress
//   is computed from the FRAME CLOCK (`easedProgress(at:)`, a smoothstep ease-
//   in-out) — deterministic and frame-accurate, not a `withAnimation` value
//   sampled inside a TimelineView. Two things interpolate off that one
//   progress, together:
//     1. THE PARAMETER SET — `displayParameters(at:)` is `lerp(previous,
//        current, progress)`, so the base sky (gradient, horizon glow, fog,
//        cloud wash) MORPHS continuously — a clear day melts into dusk instead
//        of blinking to it.
//     2. SCENE OPACITY — the stage cross-dissolves the two conditions' effect
//        scenes (rain vs. stars can't be lerped, so they fade through each
//        other), using the same frame-clock progress.
//   `setCondition(_:)` is the instant setter (no dissolve) — for first paint
//   and tests. The gallery always uses `transition(to:)` so the dissolve is
//   what an on-device auditor actually sees.
//
// LIGHTNING BROADCAST:
//   `flashLevel` (0...1) and `flashOrigin` are an app-wide broadcast the
//   thunderstorm pulses. The engine owns the PULSE SHAPE (two-flash, biased to
//   a top-edge origin) and the documented thunder-delay hook; the SCHEDULER
//   that decides WHEN to strike lives in the stage's paused-aware task, so the
//   energy contract holds — nothing pulses while the stage is off-screen.
//
// ENERGY: the engine holds no timers of its own. It is pure observable state
// plus animation; all cadence is owned by the stage, which the atmospheric
// policy gates. Reading the engine while nothing is on screen costs nothing.

@MainActor
@Observable
final class WeatherEngine {
    static let shared = WeatherEngine()

    /// The condition being shown. During a transition this is the DESTINATION;
    /// the outgoing one is `previous`.
    private(set) var current: WeatherCondition

    /// The outgoing condition while a cross-dissolve is in flight, else nil.
    /// The stage renders it (fading out) only while this is non-nil.
    private(set) var previous: WeatherCondition?

    /// When the current cross-dissolve began, or nil when settled. Progress is
    /// computed from the FRAME CLOCK against this (see `easedProgress(at:)`) —
    /// deterministic and frame-accurate, rather than depending on a
    /// `withAnimation` value being sampled correctly inside a TimelineView.
    private(set) var transitionStart: Date?
    private var transitionDuration: TimeInterval = 1.1
    /// One-shot task that releases `previous` when the dissolve ends (so the
    /// outgoing scene unmounts). Cancelled/replaced if a new transition starts.
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    /// When the current strike began, or nil when dark. The live brightness is
    /// a FRAME-DRIVEN envelope off this (see `flashLevel(at:)`) — like the
    /// transition, it is computed from the frame clock, not a `withAnimation`
    /// value, so it decays smoothly when read inside the stage's TimelineView.
    private(set) var flashStart: Date?

    /// Where the current flash is biased from — a point on the top edge band.
    /// The illumination shader reads this so successive strikes come from
    /// different parts of the cloud field, never the dead center every time.
    private(set) var flashOrigin: UnitPoint = UnitPoint(x: 0.5, y: 0.0)

    /// Per-strike intensity, 0 (a distant, dim flash) → 1 (a full, close strike).
    /// Chosen fresh on every `pulseLightning`, it is FOLDED INTO `flashLevel` so
    /// the whole broadcast (illumination shader, bolt brightness, any reactive
    /// Liquid Glass card) dims together for a distant strike, and drives the
    /// bolt's GEOMETRY (reach, width, fork count) directly via the scene context.
    /// It also maps to the thunder delay (nearer strikes clap sooner). Defaults
    /// to a full strike so a manually-forced flash reads at full strength.
    private(set) var flashMagnitude: Double = 1

    private init(initial: WeatherCondition = .clearDay) {
        current = initial
    }

    /// True while a cross-dissolve is running — the stage mounts the outgoing
    /// scene only then.
    var isTransitioning: Bool { previous != nil }

    /// Raw 0...1 dissolve progress at a given frame time.
    func rawProgress(at date: Date) -> Double {
        guard let start = transitionStart, transitionDuration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / transitionDuration))
    }

    /// Eased dissolve progress (smoothstep — an ease-in-out matching the app's
    /// `.smooth` feel) at a given frame time. The stage drives both the sky
    /// blend and the scene-opacity crossfade off this.
    func easedProgress(at date: Date) -> Double {
        let t = rawProgress(at: date)
        return t * t * (3 - 2 * t)
    }

    /// The sky to render at a given frame time: the settled condition's
    /// parameters, or the live blend between outgoing and incoming ones. The
    /// base sky layer and any app-wide consumer read this.
    func displayParameters(at date: Date) -> WeatherParameters {
        guard let previous, transitionStart != nil else { return current.parameters }
        let p = easedProgress(at: date)
        if p >= 1 { return current.parameters }
        return .lerp(previous.parameters, current.parameters, p)
    }

    // MARK: Setting the condition

    /// Instantly show `condition` with no dissolve — first paint and tests.
    /// Cancels any in-flight transition cleanly.
    func setCondition(_ condition: WeatherCondition) {
        clearTask?.cancel(); clearTask = nil
        previous = nil
        transitionStart = nil
        current = condition
    }

    /// Cross-dissolve to `condition`. No-op if already there. The dissolve is
    /// frame-driven (see `easedProgress`); Reduce Motion collapses it to an
    /// instant swap, so the engine's model stays uniform.
    ///
    /// - Parameter duration: dissolve length; the default reads as a natural
    ///   weather change, longer than a UI transition on purpose.
    func transition(to condition: WeatherCondition,
                    duration: TimeInterval = 1.1,
                    reduceMotion: Bool = false) {
        guard condition != current else { return }

        if reduceMotion {
            setCondition(condition)
            return
        }

        previous = current
        current = condition
        transitionDuration = duration
        transitionStart = Date()
        // Release the outgoing scene once the dissolve has fully played, so its
        // particles/shaders unmount — a transient task, not a running timer.
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.previous = nil
            self.transitionStart = nil
        }
    }

    // MARK: Lightning broadcast

    /// Total envelope length of one strike (bright flash + flicker + afterglow).
    private static let flashDuration: TimeInterval = 1.4

    /// The live lightning brightness at a frame time, 0 (dark) → 1 (peak),
    /// already scaled by `flashMagnitude`. The envelope models a real strike:
    ///   1. a ~6 ms attack to peak,
    ///   2. a bright MAIN FLASH lasting 30–120 ms (wider for a nearer strike),
    ///   3. a brief secondary return-stroke FLICKER, then
    ///   4. a dim AFTERGLOW tail fading to 0 by ~1.4 s.
    /// The 30–120 ms visible-flash window is the spec target; a distant strike
    /// (low magnitude) is both shorter and dimmer. Fed to the Metal illumination
    /// shader and the bolt; any Liquid Glass surface can read it against its own
    /// frame clock (see `WeatherFlashProvider`) to brighten with the storm.
    func flashLevel(at date: Date) -> Double {
        guard let start = flashStart else { return 0 }
        let e = date.timeIntervalSince(start)
        guard e >= 0, e <= Self.flashDuration else { return 0 }
        let mag = flashMagnitude
        func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }

        // Main-flash body width: 30 ms (distant) → 120 ms (close).
        let mainWidth = 0.03 + 0.09 * mag
        let level: Double
        if e < 0.006 {                               // attack → peak
            level = e / 0.006
        } else if e < mainWidth {                    // bright main flash → dim
            level = 1.0 - 0.92 * easeOut((e - 0.006) / (mainWidth - 0.006))
        } else {
            let gapEnd = mainWidth + 0.05             // short dark gap
            let echoEnd = mainWidth + 0.16            // return-stroke flicker
            if e < gapEnd {
                level = 0.08
            } else if e < echoEnd {                  // a brief re-strike
                let u = (e - gapEnd) / (echoEnd - gapEnd)
                level = 0.08 + 0.34 * sin(u * .pi)
            } else {                                  // afterglow tail → 0
                let tail = (e - echoEnd) / (Self.flashDuration - echoEnd)
                level = 0.22 * (1 - easeOut(min(1, tail)))
            }
        }
        return max(0, level) * mag
    }

    /// Begin one strike now: pick a fresh top-edge origin, a fresh per-strike
    /// magnitude, and stamp the start. The stage's scheduler calls this; the
    /// envelope then plays out purely from the frame clock (`flashLevel(at:)`),
    /// so nothing else has to tick.
    ///
    /// Returns the THUNDER DELAY that would precede the clap for this strike —
    /// a documented hook for the future audio pass (sound-at-distance). No
    /// audio plays this phase; callers that don't use it discard it, so wiring
    /// sound later needs no new plumbing.
    @discardableResult
    func pulseLightning() -> TimeInterval {
        flashOrigin = UnitPoint(x: .random(in: 0.15...0.85),
                                y: .random(in: 0.0...0.10))
        // Most strikes are moderate; ~28% are a full, close, full-screen strike;
        // the rest range down to a distant dim flash. This one number varies the
        // whole strike — brightness, bolt reach/branching, and thunder delay.
        var mag = Double.random(in: 0.45...1.0)
        if Double.random(in: 0...1) < 0.28 { mag = 1.0 }
        flashMagnitude = mag
        flashStart = Date()
        // FUTURE (audio): the thunder clap follows the flash after this delay —
        // a nearer/brighter strike (high magnitude) claps sooner. 0.4–6 s maps
        // to ~140 m–2 km at 340 m/s. Structure only; silent this phase.
        let delay = 0.4 + (1 - mag) * 5.6 + Double.random(in: -0.2...0.5)
        return max(0.4, delay)
    }

    /// Hard-resets the flash to dark — the stage calls this when the storm
    /// scene unmounts or pauses, so a half-played strike can't linger.
    func resetFlash() {
        flashStart = nil
    }

    // MARK: Auto mapping (symbol → condition) — implemented, not yet wired

    /// Resolve a live weather condition from the property's Apple Weather
    /// summary. This is the eventual AUTO path: `PropertyWeatherService`
    /// distils WeatherKit into a `Summary` (SF symbol + temps), and this maps
    /// that symbol — refined by day/night and temperature — to one of the 19.
    ///
    /// This phase it is implemented and unit-testable but NOT wired into the
    /// app-wide backdrop (see the integration note in WeatherStageView); the
    /// gallery drives the engine manually. When the auto path is switched on,
    /// a caller does `engine.transition(to: WeatherEngine.condition(for:))`.
    ///
    /// Mapping is intentionally close to `AppWeatherTone.tone(forSymbol:)` so
    /// the two never disagree about what "rain" means, but resolves to the
    /// finer 19-way set. Symbol matching is substring-based because WeatherKit
    /// symbol names compose (`cloud.bolt.rain.fill`); ORDER matters — the most
    /// specific buckets are tested first.
    static func condition(for summary: PropertyWeather.Summary,
                          at date: Date = .now,
                          isNight: Bool? = nil) -> WeatherCondition {
        let s = summary.symbol.lowercased()
        let night = isNight ?? Self.isNightHeuristic(at: date)

        // Most specific first.
        if s.contains("bolt") { return .thunderstorm }
        if s.contains("hail") { return .hail }
        if ["blizzard"].contains(where: s.contains) { return .blizzard }
        if ["snow", "sleet", "flurr", "flake"].contains(where: s.contains) {
            return summary.hi <= -3 || s.contains("heavy") ? .blizzard : .snow
        }
        if s.contains("heavyrain") || (s.contains("rain") && s.contains("heavy")) {
            return .heavyRain
        }
        if ["rain", "drizzle", "shower"].contains(where: s.contains) {
            return summary.temp >= 30 ? .heavyRain : .rain
        }
        if s.contains("fog") { return .fog }
        if ["haze", "smoke", "mist"].contains(where: s.contains) { return .mist }
        if s.contains("wind") { return .wind }
        if s.contains("smoke") { return .heavyClouds }
        // Cloud family, split by how heavy the symbol reads.
        if s.contains("cloud") {
            if ["heavy", "smoke"].contains(where: s.contains) { return .heavyClouds }
            return .clouds
        }
        // Clear family — resolve by the daylight arc.
        if s.contains("sun") || s.contains("clear") || s.contains("max") {
            if summary.temp >= 33 { return .heatWave }
            return night ? .night : .clearDay
        }
        if s.contains("moon") || s.contains("star") {
            return s.contains("moon") && !s.contains("stars") ? .fullMoon : .night
        }
        // Unknown symbol: fall back honestly to the daylight base.
        return night ? .night : .clearDay
    }

    /// A coarse day/night split for the mapping when the caller has no better
    /// signal — the fixed clock band the mood engine also falls back to
    /// (night 20:00–06:00). The real auto path should pass the sun-window
    /// answer via `isNight:`; this exists so the mapping is never undefined.
    private static func isNightHeuristic(at date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 20 || hour < 6
    }
}

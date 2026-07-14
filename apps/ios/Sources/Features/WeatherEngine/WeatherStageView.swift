import SwiftUI

// MARK: - Weather Engine · the stage
//
// `WeatherStageView` is the one surface that renders the engine's current sky.
// It composes, top to bottom:
//   1. WeatherSkyLayer — the continuously-interpolated base sky (gradient +
//      horizon glow + fog band) from `engine.displayParameters`. This MORPHS
//      across a transition; it never cross-fades, so the sky color is always
//      a single coherent field.
//   2. The effect scenes — the outgoing and incoming conditions' distinctive
//      systems (particles, god rays, stars, moon, bolt), CROSS-DISSOLVED by
//      `engine.transitionProgress`. rain-vs-stars can't be lerped, so this is
//      where opacity does the work. Together with (1) this is the full
//      transition model documented on WeatherEngine.
//   3. The lightning scheduler — one paused-aware task that pulses the engine
//      when the current condition flashes (thunderstorm / hail). It lives here,
//      not in the engine, so the energy contract holds.
//
// ENERGY CONTRACT (reused verbatim from AtmosphericEffectsPolicy — the same
// authority the mood backdrop uses):
//   - ONE `TimelineView(.animation)` drives every frame: ProMotion gets 120fps,
//     others 60, and it is PAUSED the instant `scenePhase` leaves `.active`.
//   - Reduce Motion / Low Power / effects-toggle-off  → NO TimelineView at all:
//     a single STATIC representative frame (still sky + still scene, no
//     SpriteKit, no shaders animating). Effects-off cost is a static gradient.
//   - SpriteKit scenes inside the effect scenes pause with `scenePhase`
//     (isPaused), matching the mood system exactly.
//
// INTEGRATION BOUNDARY (do not cross this phase):
//   This view is hosted full-screen ONLY by the audition gallery right now.
//   FUTURE: WeatherStageView is where the engine would slot into AppBackdrop as
//   the real-weather effects layer — AppBackdrop would host it above the mood
//   gradients (or in place of AppBackdropEffectsLayer) once the auto path
//   (WeatherEngine.condition(for:)) is trusted. Nothing wires into the app-wide
//   backdrop yet; keeping it gallery-only contains the risk and keeps this
//   reviewable.

// MARK: - Scene context + protocol

/// Everything a weather scene needs to render, as pure inputs. A scene is a
/// function of this value and nothing else — no internal clock, no singletons —
/// so the stage fully controls cadence, pausing, and the static frame.
struct WeatherSceneContext: Equatable {
    /// This scene's OWN condition parameters (not the lerped set — the base
    /// sky owns the morph; scenes cross-dissolve at their target look).
    var parameters: WeatherParameters
    /// Live lightning brightness, 0...1 (WeatherEngine.flashLevel).
    var flashLevel: Double
    /// Strike origin in unit space (near the top edge).
    var flashOrigin: UnitPoint
    /// Per-strike intensity, 0 (distant/dim) → 1 (close/full). Drives the bolt's
    /// geometry (reach, width, fork count); brightness is already folded into
    /// `flashLevel`. (WeatherEngine.flashMagnitude.)
    var flashMagnitude: Double
    /// Seconds from the stage's single TimelineView clock. Frozen in the
    /// static frame.
    var time: TimeInterval
    /// The stage size in points.
    var size: CGSize
    var reduceMotion: Bool
    /// The policy allows live motion (toggle on, not Reduce Motion, not Low
    /// Power). When false the scene must draw a still representative frame and
    /// mount NO SpriteKit / animating shader work.
    var motionEnabled: Bool
    /// `scenePhase == .active` — SpriteKit scenes pause (isPaused) when false.
    var isActive: Bool
}

/// A weather scene: a `View` built purely from a `WeatherSceneContext`.
/// Conformers are the flagship scenes and the generic parameter scene.
protocol WeatherScene: View {
    init(context: WeatherSceneContext)
}

// MARK: - Base sky layer (the continuously-morphing ground)

/// The interpolatable base sky: a vertical gradient, a horizon glow band, and
/// a soft fog wash — all pure functions of the (already-lerped) parameters, so
/// this layer MORPHS across a transition with zero cross-fade. No blur, no
/// per-frame work; it redraws only when the parameters change.
struct WeatherSkyLayer: View, Equatable {
    let parameters: WeatherParameters

    var body: some View {
        ZStack {
            LinearGradient(colors: [parameters.skyTop.color, parameters.skyBottom.color],
                           startPoint: .top, endPoint: .bottom)

            // Horizon glow — a warm/cool band rising from the sun's side of the
            // lower sky. Its vertical seat follows sun elevation (low sun → low
            // band). Opacity is the glow strength, so it fades to nothing.
            if parameters.horizonGlowStrength > 0.001 {
                RadialGradient(
                    colors: [parameters.horizonGlow.color(opacity: parameters.horizonGlowStrength),
                             .clear],
                    center: UnitPoint(x: parameters.sunAzimuth,
                                      y: 0.62 + (1 - parameters.sunElevation) * 0.28),
                    startRadius: 0, endRadius: 520)
            }

            // Fog band — a soft horizontal wash across the mid-lower sky. A
            // linear gradient (not a full-screen blur) keeps the compositor
            // cost flat; density is opacity.
            if parameters.fogDensity > 0.001 {
                LinearGradient(
                    colors: [.clear,
                             Color.white.opacity(parameters.fogDensity * 0.55),
                             Color.white.opacity(parameters.fogDensity * 0.32)],
                    startPoint: .top, endPoint: .bottom)
                .blendMode(.plusLighter)
            }
        }
    }
}

// MARK: - The stage

struct WeatherStageView: View {
    /// The shared engine — observation tracks reads made in `body`.
    private var engine = WeatherEngine.shared

    /// Fixed origin for the animation clock. The stage feeds scenes/shaders the
    /// ELAPSED seconds since this date, not an absolute timestamp: a Metal
    /// `float` uniform is 32-bit, and an absolute `timeIntervalSinceReferenceDate`
    /// (~7.7e8) would quantise to ~1 s steps and visibly stutter. Elapsed
    /// seconds stay small and precise for the life of the view.
    @State private var clockStart = Date()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let motionEnabled = AtmosphericEffectsPolicy.shared
                .allowsMounting(reduceMotion: reduceMotion)
            let isActive = scenePhase == .active

            Group {
                if motionEnabled {
                    // ONE clock for the whole stage — ProMotion 120 / others 60,
                    // paused the instant the scene leaves .active. Scenes read
                    // the elapsed seconds; RainWeatherScene owns its own scoped
                    // lens-rain refraction (see the note inside the closure).
                    TimelineView(.animation(paused: !isActive)) { timeline in
                        let t = timeline.date.timeIntervalSince(clockStart)
                        stageContent(size: size, frame: timeline.date, time: t,
                                     motionEnabled: true, isActive: isActive)
                        // NOTE (Phase 2): the lens-rain refraction is no longer
                        // applied stage-wide. Phase 1 flagged that wrapping the
                        // WHOLE stage — including the live SpriteView rain — in a
                        // `.layerEffect` is both the priciest pass AND unreliable
                        // (SwiftUI may not rasterize an SKView into a layerEffect
                        // input). RainWeatherScene now applies `.weatherLensRain`
                        // to ITS OWN sky+cloud sublayer only, with the streaks
                        // composited above the refracted sky — correct + cheaper.
                    }
                } else {
                    // Reduce Motion / Low Power / effects off → one still frame,
                    // no timeline, no SpriteKit, no lens distortion.
                    stageContent(size: size, frame: Date(), time: 0,
                                 motionEnabled: false, isActive: false)
                }
            }
            .ignoresSafeArea()
            // The lightning scheduler: re-armed whenever the storm/flash state
            // changes, cancelled while paused or off a flashing condition — so
            // nothing pulses in the background (energy contract).
            .task(id: lightningKey(motionEnabled: motionEnabled, isActive: isActive)) {
                await runLightningScheduler(motionEnabled: motionEnabled, isActive: isActive)
            }
        }
        .background(Color.black) // guards against a 1-frame gap before layout
    }

    // MARK: Composed stage content (sky + cross-dissolved scenes)

    /// The full backdrop for one frame: the morphing base sky, then the
    /// cross-dissolved effect scenes. `motionEnabled` is derived from the
    /// caller's branch (true under the TimelineView, false in the still frame).
    @ViewBuilder
    private func stageContent(size: CGSize, frame: Date, time: TimeInterval,
                              motionEnabled: Bool, isActive: Bool) -> some View {
        ZStack {
            WeatherSkyLayer(parameters: engine.displayParameters(at: frame)).equatable()
            effectScenes(size: size, frame: frame, time: time,
                         motionEnabled: motionEnabled, isActive: isActive)
        }
    }

    // MARK: Effect-scene cross-dissolve

    @ViewBuilder
    private func effectScenes(size: CGSize, frame: Date, time: TimeInterval,
                              motionEnabled: Bool, isActive: Bool) -> some View {
        let progress = engine.easedProgress(at: frame)
        ZStack {
            // Outgoing scene — mounted only during a dissolve, fading out.
            if let previous = engine.previous, progress < 1 {
                sceneView(for: previous,
                          context: context(previous.parameters, size: size, frame: frame,
                                           time: time, motionEnabled: motionEnabled,
                                           isActive: isActive))
                    .opacity(1 - progress)
            }
            // Incoming / settled scene.
            sceneView(for: engine.current,
                      context: context(engine.current.parameters, size: size, frame: frame,
                                       time: time, motionEnabled: motionEnabled,
                                       isActive: isActive))
                .opacity(engine.isTransitioning ? progress : 1)
        }
        .allowsHitTesting(false)
    }

    private func context(_ parameters: WeatherParameters, size: CGSize,
                         frame: Date, time: TimeInterval, motionEnabled: Bool,
                         isActive: Bool) -> WeatherSceneContext {
        WeatherSceneContext(
            parameters: parameters,
            flashLevel: engine.flashLevel(at: frame),
            flashOrigin: engine.flashOrigin,
            flashMagnitude: engine.flashMagnitude,
            time: time, size: size,
            reduceMotion: reduceMotion,
            motionEnabled: motionEnabled, isActive: isActive)
    }

    /// Dispatch to the flagship scene for the three hand-built conditions, and
    /// to the generic parameter scene for the other sixteen. Every branch is a
    /// `WeatherScene`, so they are interchangeable to the cross-dissolve.
    @ViewBuilder
    private func sceneView(for condition: WeatherCondition,
                           context: WeatherSceneContext) -> some View {
        switch condition {
        case .thunderstorm: ThunderstormScene(context: context)
        case .rain, .heavyRain: RainWeatherScene(context: context)
        case .clearDay: ClearDayScene(context: context)
        case .goldenHour: GoldenHourScene(context: context)
        case .sunrise, .sunset: SunriseScene(context: context)
        case .blueHour: BlueHourScene(context: context)
        case .night: NightScene(context: context)
        case .fullMoon: NightScene(context: context, forceFull: true)
        default: GenericWeatherScene(context: context)
        }
    }

    // MARK: Lightning scheduler (paused-aware, energy-safe)

    /// A stable key that re-arms the scheduler task on any change that should
    /// start/stop it: the condition, whether it flashes, motion, and activity.
    private func lightningKey(motionEnabled: Bool, isActive: Bool) -> String {
        "\(engine.current.rawValue)-\(engine.current.parameters.flashEnabled)-\(motionEnabled)-\(isActive)"
    }

    /// Between strikes exactly one task sleeps; cancelling it (pause / leaving
    /// the storm) stops every timer — the same shape as the mood system's
    /// lightning. 25–70 s cadence; each `pulseLightning` is a two-flash.
    private func runLightningScheduler(motionEnabled: Bool, isActive: Bool) async {
        guard motionEnabled, isActive,
              engine.current.parameters.flashEnabled else {
            engine.resetFlash()
            return
        }
        while !Task.isCancelled {
            let wait = Double.random(in: 25...70)   // cadence between strikes
            guard (try? await Task.sleep(for: .seconds(wait))) != nil else {
                engine.resetFlash(); return
            }
            let thunderDelay = engine.pulseLightning()
            // FUTURE (audio): after `thunderDelay` seconds, play the thunder clap
            // at a volume scaled by the strike magnitude. The delay is already
            // computed and distance-mapped, so wiring audio later needs no new
            // plumbing; it stays silent this phase.
            _ = thunderDelay
        }
        engine.resetFlash()
    }
}

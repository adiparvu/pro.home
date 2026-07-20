import SwiftUI
import Observation
import WidgetKit

// MARK: - WeatherStageEngine — real weather + real sun → shader params
//
// The one authority for what the sky shows. Honest-data throughout: the
// weather condition comes ONLY from the property's fresh (≤ 2h) cached
// Apple WeatherKit summary — stale or absent cache claims clear skies by
// TIME alone, never invented weather. The sun position comes from the same
// solar window model the mood engine proved (AppMood.defaultEdges), fed by
// the property's coordinates when known, clock windows otherwise.
//
// F2: the WIND scalar rides the summary's real speed+direction (calm when
// absent). F4: the engine owns the after-rain RAINBOW state machine, the
// firefly gate (clear warm summer night, fresh temperature only), and the
// widget/watch SKY SNAPSHOT — two CPU-mirrored gradient colors published
// to the App Group whenever the target sky materially changes.
//
// State changes ease over 3 seconds (the 2–5s spec) via param-space lerp:
// the shader only ever sees one smoothly-moving parameter set.

@MainActor
@Observable
final class WeatherStageEngine {
    static let shared = WeatherStageEngine()

    /// The interpolation pair: the shader renders lerp(from, to, eased-t).
    private(set) var fromParams: WeatherStageParams = .zero
    private(set) var toParams: WeatherStageParams = .zero
    private(set) var transitionStart: Date = .distantPast
    static let transitionDuration: TimeInterval = 3

    /// The rainbow's lifetime after a rain-end transition (seconds). Long
    /// enough to be noticed, short enough to stay a moment — and it fades
    /// across recompute ticks so the arc dissolves rather than blinking out.
    static let rainbowLifetime: TimeInterval = 420

    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var weatherObserver: NSObjectProtocol?
    @ObservationIgnored private var liveStages = 0
    @ObservationIgnored private var rainbowUntil: Date?
    @ObservationIgnored private var lastSnapshotTop: WeatherStageParams.RGB?
    @ObservationIgnored private var lastSnapshotAt: Date = .distantPast

    private init() {
        recompute(animated: false)
        weatherObserver = NotificationCenter.default.addObserver(
            forName: .propertyWeatherCacheDidUpdate, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in WeatherStageEngine.shared.recompute(animated: true) }
        }
    }

    /// Params for `date`, fully derived — pure, so recompute can diff.
    /// (The rainbow, an inherently stateful moment, is layered on by
    /// `recompute` itself.)
    private func params(at date: Date) -> WeatherStageParams {
        let edges = AppMood.defaultEdges(on: date,
                                         latitude: AppMoodEngine.shared.latitude,
                                         longitude: AppMoodEngine.shared.longitude)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        // The Fundal page's custom hours override the sun window's edges —
        // the same thresholds (and stored keys) the mood engine always had.
        let morningEdge = AppMoodEngine.shared.morningStartMinutes.map { Double($0) / 60 } ?? edges.morning
        let nightEdge = max(AppMoodEngine.shared.nightStartMinutes.map { Double($0) / 60 } ?? edges.night,
                            morningEdge + 1)
        let daySpan = max(nightEdge - morningEdge, 1)
        // Elevation proxy: -1 at deep night, 0 at the edges, peaking ~1 at
        // solar mid-day; azimuth sweeps left → right across the day.
        let mid = (morningEdge + nightEdge) / 2
        let elev: Double
        if hour < morningEdge || hour > nightEdge {
            let nightSpan = 24 - daySpan
            let sinceDusk = hour > nightEdge ? hour - nightEdge
                                             : hour + 24 - nightEdge
            elev = -0.3 - 0.7 * sin(.pi * min(sinceDusk / max(nightSpan, 1), 1))
        } else {
            elev = sin(.pi * (hour - morningEdge) / daySpan) * (0.35 + 0.65 * (1 - abs(hour - mid) / (daySpan / 2)))
        }
        let azimuth = hour < morningEdge ? 0.2
            : hour > nightEdge ? 0.8
            : 0.15 + 0.7 * (hour - morningEdge) / daySpan

        // Fresh summary or nothing — the honest gate every scalar shares.
        // The Reacționează la vreme toggle (the mood engine's stored pref)
        // can stand the live weather down: the sky then follows time alone.
        let summary = PropertyWeather.cached()
        let fresh = summary.map { date.timeIntervalSince($0.fetchedAt) <= AppWeatherTone.maxAge } ?? false
        let condition: WeatherCondition = (fresh && AppMoodEngine.shared.weatherReactive)
            ? WeatherCondition.from(symbol: summary?.symbol) : .clear

        // F2 — wind: magnitude from the real speed (≈55 km/h saturates the
        // visual scale), sign from the direction's screen east/west
        // component. No wind in the cache → calm, never invented.
        var wind: Double = 0
        if fresh, let kph = summary?.windKph {
            let magnitude = min(max(kph, 0) / 55.0, 1.0)
            let sign: Double = (summary?.windDeg)
                .map { sin($0 * .pi / 180) >= 0 ? 1.0 : -1.0 } ?? 1.0
            wind = magnitude * sign
        }

        // The Fundal page's pin: a chosen atmosphere stays on screen no
        // matter the weather; Automat (no pin) follows sun + weather.
        if let preset = WeatherStagePrefs.preset {
            var pinned = preset.params(sunElevation: max(min(elev, 1), -1),
                                       sunAzimuth: azimuth,
                                       moonPhase: WeatherStageParams.moonPhase(on: date),
                                       wind: wind)
            if !WeatherStagePrefs.effectsEnabled { pinned.stripEffects() }
            return pinned
        }

        var p = WeatherStageParams.target(condition: condition,
                                          sunElevation: max(min(elev, 1), -1),
                                          sunAzimuth: azimuth,
                                          moonPhase: WeatherStageParams.moonPhase(on: date),
                                          wind: wind)
        // F4 — fireflies: clear warm summer night, fresh temperature only.
        p.fireflies = firefliesLevel(condition: condition,
                                     sunElevation: p.sunElevation,
                                     at: date,
                                     summary: fresh ? summary : nil)
        if !WeatherStagePrefs.effectsEnabled { p.stripEffects() }
        return p
    }

    /// 1 on a clear warm summer night — hemisphere-aware (the property's
    /// latitude decides which months are summer) and honest about the
    /// temperature: no fresh reading, no fireflies.
    private func firefliesLevel(condition: WeatherCondition, sunElevation: Double,
                                at date: Date, summary: PropertyWeather.Summary?) -> Double {
        guard condition == .clear, sunElevation < -0.15,
              let summary, summary.temp >= 13 else { return 0 }
        let month = Calendar.current.component(.month, from: date)
        let north = (AppMoodEngine.shared.latitude ?? 45) >= 0
        let summer = north ? (5...8).contains(month) : (month >= 11 || month <= 2)
        return summer ? 1 : 0
    }

    /// Re-derives the target; a changed target eases in over the standard
    /// window (animated) or snaps (first frame, scene restore).
    func recompute(animated: Bool) {
        var target = params(at: .now)
        let now = Date.now

        // F4 — rainbow state machine: rain that JUST ended under a risen
        // sun arms the arc; it then decays across recompute ticks.
        if toParams.rain >= 0.5, target.rain <= 0.05,
           target.sunElevation > 0.05, rainbowUntil == nil {
            rainbowUntil = now.addingTimeInterval(Self.rainbowLifetime)
            scheduleRainbowFadeTicks()
        }
        if let until = rainbowUntil {
            if now < until {
                let remaining = until.timeIntervalSince(now) / Self.rainbowLifetime
                target.rainbow = min(1, remaining * 1.6)   // quick in, slow out
            } else {
                rainbowUntil = nil
            }
        }

        guard target != toParams else { return }
        fromParams = animated ? current(at: now) : target
        toParams = target
        transitionStart = animated ? now : .distantPast
        publishSkySnapshot(for: target, at: now)
    }

    /// The rainbow outlives the 5-minute timer's granularity mid-life, so
    /// two one-shot ticks re-derive the decay and the final fade-out.
    private func scheduleRainbowFadeTicks() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.rainbowLifetime * 0.5))
            self.recompute(animated: true)
            try? await Task.sleep(for: .seconds(Self.rainbowLifetime * 0.5 + 2))
            self.recompute(animated: true)
        }
    }

    /// The interpolated params the shader should render right now.
    func current(at date: Date) -> WeatherStageParams {
        let t = date.timeIntervalSince(transitionStart) / Self.transitionDuration
        guard t < 1 else { return toParams }
        let eased = t * t * (3 - 2 * t)   // smoothstep
        return WeatherStageParams.lerp(fromParams, toParams, max(eased, 0))
    }

    // MARK: F4 — the widget/watch sky snapshot

    /// Publishes the CPU-mirrored gradient into the App Group so widgets
    /// (directly) and the watch (via the payload push) wear the same sky.
    /// Throttled: a reload storm of home-screen timelines for a barely
    /// different blue would be all cost and no truth.
    private func publishSkySnapshot(for params: WeatherStageParams, at date: Date) {
        let colors = params.snapshotColors
        let materially = lastSnapshotTop.map {
            abs($0.r - colors.top.r) + abs($0.g - colors.top.g) + abs($0.b - colors.top.b) > 0.06
        } ?? true
        let stale = date.timeIntervalSince(lastSnapshotAt) > 900
        guard materially || stale else { return }
        lastSnapshotTop = colors.top
        lastSnapshotAt = date
        SharedDataStore.writeWeatherSky(WeatherSkySnapshot(
            top: [colors.top.r, colors.top.g, colors.top.b],
            bottom: [colors.bottom.r, colors.bottom.g, colors.bottom.b],
            darkGround: params.snapshotWantsDarkScheme,
            capturedAt: date))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Ref-counted 5-minute re-derivation while any stage is on screen —
    // the sun proxy and clock windows only move at that granularity.
    func stageAppeared() {
        liveStages += 1
        guard refreshTimer == nil else { return }
        recompute(animated: true)
        let timer = Timer(timeInterval: 300, repeats: true) { _ in
            Task { @MainActor in WeatherStageEngine.shared.recompute(animated: true) }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stageDisappeared() {
        liveStages = max(0, liveStages - 1)
        if liveStages == 0 {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
}

// MARK: - WeatherStageView — the animated sky itself

/// The full-screen procedural sky. One fragment pass per frame; the frame
/// cadence bends to the energy policy — Reduce Motion pins a still frame,
/// Low Power Mode drops to 10 fps, otherwise the display drives it (the
/// shader is a single pass, ProMotion-friendly).
struct WeatherStageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    /// Whether THIS stage currently holds the motion engine (F2 droplets).
    @State private var holdsMotion = false

    private var engine: WeatherStageEngine { .shared }

    /// The gyroscope earns its battery only while droplets exist to move.
    private var wantsMotion: Bool {
        !reduceMotion && (engine.toParams.rain > 0.03 || engine.fromParams.rain > 0.03)
    }

    var body: some View {
        Group {
            if reduceMotion {
                sky(time: 0, params: engine.current(at: .now), tilt: (0, 0))
            } else {
                TimelineView(.animation(minimumInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.1 : nil)) { context in
                    sky(time: context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 86_400),
                        params: engine.current(at: context.date),
                        tilt: (MotionTiltEngine.shared.tiltX,
                               MotionTiltEngine.shared.tiltY))
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { engine.stageAppeared(); syncMotion() }
        .onDisappear {
            engine.stageDisappeared()
            if holdsMotion { MotionTiltEngine.shared.release(); holdsMotion = false }
        }
        .onChange(of: wantsMotion) { _, _ in syncMotion() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                engine.recompute(animated: true)
                syncMotion()
            } else if holdsMotion {
                // The gyroscope must never outlive the foreground:
                // backgrounding does NOT call onDisappear, and a live
                // CoreMotion thread in a background process is battery
                // drain plus termination resistance — the 0x8BADF00D
                // watchdog kill (build 1173, 14:07) showed exactly
                // com.apple.CoreMotion.MotionThread alive at exit.
                MotionTiltEngine.shared.release()
                holdsMotion = false
            }
        }
    }

    private func syncMotion() {
        if wantsMotion, !holdsMotion {
            MotionTiltEngine.shared.acquire(); holdsMotion = true
        } else if !wantsMotion, holdsMotion {
            MotionTiltEngine.shared.release(); holdsMotion = false
        }
    }

    private func sky(time: TimeInterval, params p: WeatherStageParams,
                     tilt: (Double, Double)) -> some View {
        Rectangle()
            .fill(.black)
            .colorEffect(ShaderLibrary.weatherSky(
                .boundingRect,
                .float(Float(time)),
                .float(Float(p.sunElevation)),
                .float(Float(p.sunAzimuth)),
                .float(Float(p.cloudiness)),
                .float(Float(p.rain)),
                .float(Float(p.snow)),
                .float(Float(p.fog)),
                .float(Float(p.storm)),
                .float(Float(p.moonPhase)),
                .float(colorScheme == .dark ? 1 : 0),
                .float(Float(p.wind)),
                .float(Float(p.sand)),
                .float(Float(p.rainbow)),
                .float(Float(p.fireflies)),
                .float(Float(tilt.0)),
                .float(Float(tilt.1))))
    }
}

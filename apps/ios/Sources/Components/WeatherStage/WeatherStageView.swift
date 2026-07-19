import SwiftUI
import Observation

// MARK: - WeatherStageEngine — real weather + real sun → shader params
//
// The one authority for what the sky shows. Honest-data throughout: the
// weather condition comes ONLY from the property's fresh (≤ 2h) cached
// Apple WeatherKit summary — stale or absent cache claims clear skies by
// TIME alone, never invented weather. The sun position comes from the same
// solar window model the mood engine proved (AppMood.defaultEdges), fed by
// the property's coordinates when known, clock windows otherwise.
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

    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var weatherObserver: NSObjectProtocol?
    @ObservationIgnored private var liveStages = 0

    private init() {
        recompute(animated: false)
        weatherObserver = NotificationCenter.default.addObserver(
            forName: .propertyWeatherCacheDidUpdate, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in WeatherStageEngine.shared.recompute(animated: true) }
        }
    }

    /// Params for `date`, fully derived — pure, so recompute can diff.
    private func params(at date: Date) -> WeatherStageParams {
        let edges = AppMood.defaultEdges(on: date,
                                         latitude: AppMoodEngine.shared.latitude,
                                         longitude: AppMoodEngine.shared.longitude)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        let daySpan = max(edges.night - edges.morning, 1)
        // Elevation proxy: -1 at deep night, 0 at the edges, peaking ~1 at
        // solar mid-day; azimuth sweeps left → right across the day.
        let mid = (edges.morning + edges.night) / 2
        let elev: Double
        if hour < edges.morning || hour > edges.night {
            let nightSpan = 24 - daySpan
            let sinceDusk = hour > edges.night ? hour - edges.night
                                               : hour + 24 - edges.night
            elev = -0.3 - 0.7 * sin(.pi * min(sinceDusk / max(nightSpan, 1), 1))
        } else {
            elev = sin(.pi * (hour - edges.morning) / daySpan) * (0.35 + 0.65 * (1 - abs(hour - mid) / (daySpan / 2)))
        }
        let azimuth = hour < edges.morning ? 0.2
            : hour > edges.night ? 0.8
            : 0.15 + 0.7 * (hour - edges.morning) / daySpan

        let condition: WeatherCondition = {
            guard let summary = PropertyWeather.cached(),
                  date.timeIntervalSince(summary.fetchedAt) <= AppWeatherTone.maxAge
            else { return .clear }
            return WeatherCondition.from(symbol: summary.symbol)
        }()

        return WeatherStageParams.target(condition: condition,
                                         sunElevation: max(min(elev, 1), -1),
                                         sunAzimuth: azimuth,
                                         moonPhase: WeatherStageParams.moonPhase(on: date))
    }

    /// Re-derives the target; a changed target eases in over the standard
    /// window (animated) or snaps (first frame, scene restore).
    func recompute(animated: Bool) {
        let target = params(at: .now)
        guard target != toParams else { return }
        let now = Date.now
        fromParams = animated ? current(at: now) : target
        toParams = target
        transitionStart = animated ? now : .distantPast
    }

    /// The interpolated params the shader should render right now.
    func current(at date: Date) -> WeatherStageParams {
        let t = date.timeIntervalSince(transitionStart) / Self.transitionDuration
        guard t < 1 else { return toParams }
        let eased = t * t * (3 - 2 * t)   // smoothstep
        return WeatherStageParams.lerp(fromParams, toParams, max(eased, 0))
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

    private var engine: WeatherStageEngine { .shared }

    var body: some View {
        Group {
            if reduceMotion {
                sky(time: 0, params: engine.current(at: .now))
            } else {
                TimelineView(.animation(minimumInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.1 : nil)) { context in
                    sky(time: context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 86_400),
                        params: engine.current(at: context.date))
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { engine.stageAppeared() }
        .onDisappear { engine.stageDisappeared() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.recompute(animated: true) }
        }
    }

    private func sky(time: TimeInterval, params p: WeatherStageParams) -> some View {
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
                .float(colorScheme == .dark ? 1 : 0)))
    }
}

import SwiftUI
import Observation

// MARK: - App mood (the living background's three atmospheres)
//
// One mood drives the whole app's backdrop and color scheme:
// dimineața (morning) / zi (day) / noapte (night). The mood resolves
// automatically from the clock — refined by the property's coordinates when
// they exist — or is pinned manually from Settings → Aspect → Fundal.
//
// Honesty notes (constitution):
// - The sunrise/sunset window is a standard low-precision solar
//   approximation (same family as the retired Twin3D sun model): declination
//   from day-of-year, hour angle from the local clock. When a longitude is
//   available, solar noon is corrected for the time zone's offset (which
//   also absorbs DST); the equation of time (±16 min) is ignored. Good for
//   picking an atmosphere, never presented as an ephemeris.
// - Without coordinates the engine claims nothing about the sun — it follows
//   fixed clock windows (6–10 / 10–19 / 19–6), and the settings page's Auto
//   explanation says exactly that.
// - Custom Auto thresholds ("night starts at…") override only the edge they
//   name; the settings caption then says the hours are the user's, not the
//   sun's. A pinned mood ignores them, so their pickers never show then.
// - The weather tone comes only from a FRESH cached Apple Weather summary
//   (≤ 2h); with stale or missing data the backdrop claims nothing.

enum AppMood: String, CaseIterable, Identifiable {
    case morning
    case day
    case night

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .morning: "mood_morning"
        case .day:     "mood_day"
        case .night:   "mood_night"
        }
    }

    /// Resolved string for contexts that need a `String` (settings row
    /// values, accessibility labels).
    var localizedTitle: String {
        switch self {
        case .morning: String(localized: "mood_morning")
        case .day:     String(localized: "mood_day")
        case .night:   String(localized: "mood_night")
        }
    }

    /// The mood's background palette (tokens live in DesignSystem.swift so
    /// the palette values sit with every other design token).
    var palette: AppMoodPalette {
        switch self {
        case .morning: .morning
        case .day:     .day
        case .night:   .night
        }
    }

    // MARK: Automatic resolution

    /// Sunrise..10h → morning; 10h..(sunset−1h) → day; everything else →
    /// night. Without coordinates (or inside a polar day/night) the fixed
    /// clock windows apply (6–10 / 10–19 / 19–6). In a high-latitude winter
    /// where the sun rises after 10h, the morning band collapses and day
    /// starts at sunrise.
    ///
    /// `morningStart`/`nightStart` (fractional local-clock hours) are the
    /// user's optional custom thresholds: each one overrides ONLY the edge
    /// it names — morning onset (sunrise / 6h) or night onset (sunset−1h /
    /// 19h) — and every other edge keeps its sun/clock default. When the
    /// two ever cross, night wins (the settings pickers are ranged so this
    /// stays theoretical).
    static func auto(at date: Date = .now,
                     latitude: Double?,
                     longitude: Double? = nil,
                     morningStart: Double? = nil,
                     nightStart: Double? = nil) -> AppMood {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60

        let edges = defaultEdges(on: date, latitude: latitude, longitude: longitude)
        let morningBegin = morningStart ?? edges.morning
        let nightBegin = nightStart ?? edges.night
        // Day never begins before 10h (the original band) nor after night.
        let dayBegin = min(max(10, morningBegin), max(morningBegin, nightBegin))

        if hour < morningBegin || hour >= nightBegin { return .night }
        return hour < dayBegin ? .morning : .day
    }

    /// The automatic edges a given day would use with no custom thresholds:
    /// morning onset (sunrise, or 6h without coordinates / in polar
    /// day/night) and night onset (sunset−1h, or 19h). The settings page
    /// seeds its custom-hour pickers from this, so "reset" is always honest
    /// about what Auto would actually do today.
    static func defaultEdges(on date: Date = .now,
                             latitude: Double?,
                             longitude: Double? = nil) -> (morning: Double, night: Double) {
        guard let latitude,
              let sun = SunWindow.compute(on: date, latitude: latitude,
                                          longitude: longitude) else {
            return (6, 19)
        }
        return (sun.sunrise, sun.sunset - 1)
    }
}

// MARK: - Approximate sunrise/sunset window

/// Local-clock sunrise and sunset hours from the standard low-precision
/// solar approximation (see the honesty notes at the top of this file).
private struct SunWindow {
    /// Local clock hours (0–24, fractional).
    let sunrise: Double
    let sunset: Double

    static func compute(on date: Date, latitude: Double,
                        longitude: Double?) -> SunWindow? {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
        let phi = latitude * .pi / 180
        let declination = -23.44 * cos(2 * .pi * (dayOfYear + 10) / 365) * .pi / 180

        // Half-day arc: cos(H0) = −tanφ·tanδ. Out of range → polar day or
        // polar night; the caller falls back to the clock windows.
        let cosH0 = -tan(phi) * tan(declination)
        guard cosH0 > -1, cosH0 < 1 else { return nil }
        let halfDayHours = acos(cosH0) * 180 / .pi / 15

        // Solar noon on the local clock. With a longitude the time zone's
        // offset (incl. DST) is corrected for; without one, 12:00 is assumed.
        var solarNoon = 12.0
        if let longitude {
            let zoneHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600
            solarNoon = 12 + zoneHours - longitude / 15
        }
        return SunWindow(sunrise: solarNoon - halfDayHours,
                         sunset: solarNoon + halfDayHours)
    }
}

// MARK: - AppMoodEngine

/// The single mood authority. Views read `resolved`; the settings page
/// writes `override` (persisted; nil = Auto) and the optional custom Auto
/// thresholds; the app shell provides the primary property's coordinates
/// when it has them (PropertyService is a per-scene `@State` service, not a
/// singleton — the engine never reaches into the environment itself).
///
/// Recomputation is event-driven, never continuous: an internal 15-minute
/// timer runs only while at least one live `AppBackdrop` is on screen
/// (ref-counted from the view's appear/disappear), plus a refresh whenever
/// the scene becomes active. Resolution itself is O(1) arithmetic.
///
/// Every change of the resolved mood is published to the shared App Group
/// suite ("app.mood.current" = the raw mood, "app.mood.scheme" =
/// "light"/"dark") for the widgets/watch, and announced in-process via
/// `Notification.Name.appMoodResolvedChanged` (the icon manager listens).
@MainActor
@Observable
final class AppMoodEngine {
    static let shared = AppMoodEngine()

    private static let overrideKey = "app.mood.override"
    private static let morningStartKey = "app.mood.morningStart"
    private static let nightStartKey = "app.mood.nightStart"
    private static let weatherReactiveKey = "app.mood.weatherReactive"
    private static let publishedMoodKey = "app.mood.current"
    private static let publishedSchemeKey = "app.mood.scheme"

    /// Manual mood pin; nil follows the clock (Auto). Persisted.
    var override: AppMood? {
        didSet {
            if let override {
                UserDefaults.standard.set(override.rawValue, forKey: Self.overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.overrideKey)
            }
            publishResolvedIfChanged()
        }
    }

    /// Custom Auto thresholds, stored as MINUTES SINCE MIDNIGHT (0–1439);
    /// nil = today's sun/clock behavior. Each overrides only the edge it
    /// names (see `AppMood.auto`). A pinned mood ignores them entirely.
    var morningStartMinutes: Int? {
        didSet {
            persist(minutes: morningStartMinutes, key: Self.morningStartKey)
            publishResolvedIfChanged()
        }
    }
    var nightStartMinutes: Int? {
        didSet {
            persist(minutes: nightStartMinutes, key: Self.nightStartKey)
            publishResolvedIfChanged()
        }
    }

    /// True while at least one custom Auto threshold is set.
    var hasCustomHours: Bool { morningStartMinutes != nil || nightStartMinutes != nil }

    /// Whether the backdrop may modulate with the property's real weather
    /// (Settings → Aspect → Fundal). Persisted; default ON. The toggle only
    /// ever matters when a fresh cached summary exists — see `weatherTone`.
    var weatherReactive: Bool {
        didSet {
            UserDefaults.standard.set(weatherReactive, forKey: Self.weatherReactiveKey)
            refreshWeatherTone()
        }
    }

    /// The current weather modulation layer for live backdrops: non-nil only
    /// when the feature is on AND a fresh (≤ 2h) cached summary maps to a
    /// tone. Reassigned only when the value actually changes, so backdrops
    /// are never invalidated by a no-op tick.
    private(set) var weatherTone: AppWeatherTone?

    /// Primary property coordinates, provided by the app shell when known.
    /// Latitude alone already refines the sun window; longitude additionally
    /// corrects solar noon for the time zone.
    var latitude: Double? {
        didSet { if latitude != oldValue { publishResolvedIfChanged() } }
    }
    var longitude: Double? {
        didSet { if longitude != oldValue { publishResolvedIfChanged() } }
    }

    /// True while no manual pin is set.
    var isAuto: Bool { override == nil }

    /// What the app shows right now.
    var resolved: AppMood {
        override ?? autoMood(at: clock)
    }

    /// The observation-tracked "now" that `resolved` derives from. Only
    /// reassigned when the automatic mood actually changes, so the dozens of
    /// on-screen backdrops aren't invalidated by a no-op tick.
    private var clock: Date = .now

    @ObservationIgnored private var liveBackdrops = 0
    @ObservationIgnored private var timer: Timer?
    /// The last mood written to the App Group (dedupes publishes).
    @ObservationIgnored private var publishedMood: AppMood?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.overrideKey) ?? ""
        override = AppMood(rawValue: stored)
        morningStartMinutes = Self.readMinutes(key: Self.morningStartKey)
        nightStartMinutes = Self.readMinutes(key: Self.nightStartKey)
        weatherReactive = (UserDefaults.standard.object(forKey: Self.weatherReactiveKey) as? Bool) ?? true
        refreshWeatherTone()
        // Seed the App Group without posting: observers registering later
        // (IconManager) check the engine themselves at startup, and posting
        // from inside the singleton's own `init` could re-enter `shared`.
        publishResolvedIfChanged(posting: false)
    }

    /// `AppMood.auto` with this engine's coordinates and custom thresholds.
    private func autoMood(at date: Date) -> AppMood {
        AppMood.auto(at: date, latitude: latitude, longitude: longitude,
                     morningStart: morningStartMinutes.map { Double($0) / 60 },
                     nightStart: nightStartMinutes.map { Double($0) / 60 })
    }

    /// Today's sun/clock edges (fractional hours) — what Auto uses when no
    /// custom threshold is set; the settings pickers seed from this.
    func defaultEdges() -> (morning: Double, night: Double) {
        AppMood.defaultEdges(latitude: latitude, longitude: longitude)
    }

    /// Re-evaluates the automatic mood and the weather tone (scene became
    /// active, timer tick).
    func refresh() {
        let now = Date.now
        if autoMood(at: now) != autoMood(at: clock) {
            clock = now
        }
        refreshWeatherTone()
        publishResolvedIfChanged()
    }

    // MARK: Weather tone (event-driven, from the cached summary only)

    /// Recomputes the tone from the cached Apple Weather summary. Never
    /// fetches; never assigns unless the tone actually changed.
    private func refreshWeatherTone() {
        let tone = weatherReactive ? AppWeatherTone.fromFreshCache() : nil
        if tone != weatherTone { weatherTone = tone }
    }

    // MARK: Cross-process publish + in-process notification

    /// Writes the resolved mood (and its color scheme) to the shared App
    /// Group whenever it changed, and posts `.appMoodResolvedChanged`.
    /// Widgets and the watch read exactly these keys.
    private func publishResolvedIfChanged(posting: Bool = true) {
        let mood = resolved
        guard mood != publishedMood else { return }
        publishedMood = mood
        if let ud = UserDefaults(suiteName: SharedDataStore.suiteName) {
            ud.set(mood.rawValue, forKey: Self.publishedMoodKey)
            ud.set(mood.palette.colorScheme == .dark ? "dark" : "light",
                   forKey: Self.publishedSchemeKey)
        }
        if posting {
            NotificationCenter.default.post(name: .appMoodResolvedChanged, object: nil)
        }
    }

    private func persist(minutes: Int?, key: String) {
        if let minutes {
            UserDefaults.standard.set(minutes, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func readMinutes(key: String) -> Int? {
        UserDefaults.standard.object(forKey: key) as? Int
    }

    // MARK: Backdrop lifecycle (ref-counted 15-minute tick)

    /// Called by every live `AppBackdrop`'s `onAppear`. The first visible
    /// backdrop starts the shared timer; there is never more than one.
    func backdropAppeared() {
        liveBackdrops += 1
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in AppMoodEngine.shared.refresh() }
        }
        t.tolerance = 90   // let the system coalesce wakeups — battery first
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Called by every live `AppBackdrop`'s `onDisappear`. The last one off
    /// screen stops the timer — nothing ticks while the app shows no backdrop.
    func backdropDisappeared() {
        liveBackdrops = max(0, liveBackdrops - 1)
        if liveBackdrops == 0 {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Resolved-mood change notification

extension Notification.Name {
    /// Posted by `AppMoodEngine` (main actor) every time the RESOLVED mood
    /// changes — auto rollover, manual pin, threshold or coordinate change.
    /// `IconManager` listens to swap the mood-following app icon.
    static let appMoodResolvedChanged = Notification.Name("app.mood.resolvedChanged")
}

// MARK: - Nonisolated last-published mood

extension AppMood {
    /// The mood the engine last published to the shared App Group — kept
    /// current by `AppMoodEngine.publishResolvedIfChanged()`. Nonisolated on
    /// purpose: the "auto" accent resolver (`avatarRingColor`) is called
    /// from UIKit appearance setup outside the main actor, where the engine
    /// itself is unreachable. Falls back to the persisted override, then to
    /// the coordinate-less clock windows, for the moments before the
    /// engine's first write.
    static var lastPublished: AppMood {
        // Keys must match AppMoodEngine's publish/override keys exactly.
        if let raw = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .string(forKey: "app.mood.current"),
           let mood = AppMood(rawValue: raw) {
            return mood
        }
        if let raw = UserDefaults.standard.string(forKey: "app.mood.override"),
           let mood = AppMood(rawValue: raw) {
            return mood
        }
        return .auto(at: .now, latitude: nil)
    }
}

// MARK: - Weather tone (the backdrop's weather modulation)

/// A subtle weather wash blended over the mood palette — one extra
/// low-opacity layer, never a fourth mood. Derived exclusively from the
/// property's FRESH cached Apple Weather summary (≤ 2 hours old — stale
/// data claims nothing about now) by mapping its SF symbol name. Clear
/// skies map to no tone at all.
enum AppWeatherTone: Equatable {
    case rain       // rain / drizzle / storms — cool gray-blue
    case snow       // snow / sleet / flurries — whiter, quieter
    case overcast   // fog / haze / clouds — desaturated

    /// Freshness bound: beyond this the cached summary is ignored entirely.
    static let maxAge: TimeInterval = 2 * 3600

    /// True while a fresh (≤ 2h) cached summary exists at all — the
    /// settings row disables itself honestly on this instead of showing a
    /// toggle that could not do anything.
    static var hasFreshSummary: Bool {
        guard let summary = PropertyWeather.cached() else { return false }
        return Date().timeIntervalSince(summary.fetchedAt) <= maxAge
    }

    /// The tone for the current fresh cached summary, if any.
    static func fromFreshCache(now: Date = .now) -> AppWeatherTone? {
        guard let summary = PropertyWeather.cached(),
              now.timeIntervalSince(summary.fetchedAt) <= maxAge else { return nil }
        return tone(forSymbol: summary.symbol)
    }

    /// SF symbol name → tone. Priority matters: "cloud.snow" must land on
    /// snow and "cloud.bolt.rain" on rain before either falls into the
    /// plain cloud bucket. Sun, moon, and wind symbols return nil.
    static func tone(forSymbol symbol: String) -> AppWeatherTone? {
        let s = symbol.lowercased()
        if ["snow", "sleet", "flurr", "blizzard", "flake"].contains(where: s.contains) {
            return .snow
        }
        if ["rain", "drizzle", "storm", "bolt", "hail", "hurricane", "tropical"]
            .contains(where: s.contains) {
            return .rain
        }
        if ["fog", "haze", "smoke", "dust", "cloud"].contains(where: s.contains) {
            return .overcast
        }
        return nil
    }

    /// The single wash layer `AppBackdrop` lays over the palette, already
    /// carrying its opacity. Values are capped so text keeps AA contrast in
    /// both schemes (worst cases measured: white text over night + snow
    /// ≥ 14:1; near-black text over day + rain ≥ 15.9:1).
    func wash(for scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch self {
        case .rain:
            return dark
                ? Color(red: 0.141, green: 0.220, blue: 0.306).opacity(0.16) // #24384E
                : Color(red: 0.333, green: 0.404, blue: 0.478).opacity(0.10) // #55677A
        case .snow:
            return Color.white.opacity(dark ? 0.06 : 0.30)
        case .overcast:
            return dark
                ? Color(red: 0.604, green: 0.627, blue: 0.651).opacity(0.05) // #9AA0A6
                : Color(red: 0.431, green: 0.431, blue: 0.451).opacity(0.08) // #6E6E73
        }
    }
}

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
    /// clock windows apply. In a high-latitude winter where the sun rises
    /// after 10h, the morning band collapses and day starts at sunrise.
    static func auto(at date: Date = .now,
                     latitude: Double?,
                     longitude: Double? = nil) -> AppMood {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60

        guard let latitude,
              let sun = SunWindow.compute(on: date, latitude: latitude,
                                          longitude: longitude) else {
            switch hour {
            case 6..<10:  return .morning
            case 10..<19: return .day
            default:      return .night
            }
        }

        let dayStart = max(10, sun.sunrise)
        if hour >= sun.sunrise, hour < dayStart { return .morning }
        if hour >= dayStart, hour < sun.sunset - 1 { return .day }
        return .night
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
/// writes `override` (persisted; nil = Auto); the app shell provides the
/// primary property's coordinates when it has them (PropertyService is a
/// per-scene `@State` service, not a singleton — the engine never reaches
/// into the environment itself).
///
/// Recomputation is event-driven, never continuous: an internal 15-minute
/// timer runs only while at least one live `AppBackdrop` is on screen
/// (ref-counted from the view's appear/disappear), plus a refresh whenever
/// the scene becomes active. Resolution itself is O(1) arithmetic.
@MainActor
@Observable
final class AppMoodEngine {
    static let shared = AppMoodEngine()

    private static let overrideKey = "app.mood.override"

    /// Manual mood pin; nil follows the clock (Auto). Persisted.
    var override: AppMood? {
        didSet {
            if let override {
                UserDefaults.standard.set(override.rawValue, forKey: Self.overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.overrideKey)
            }
        }
    }

    /// Primary property coordinates, provided by the app shell when known.
    /// Latitude alone already refines the sun window; longitude additionally
    /// corrects solar noon for the time zone.
    var latitude: Double?
    var longitude: Double?

    /// True while no manual pin is set.
    var isAuto: Bool { override == nil }

    /// What the app shows right now.
    var resolved: AppMood {
        override ?? .auto(at: clock, latitude: latitude, longitude: longitude)
    }

    /// The observation-tracked "now" that `resolved` derives from. Only
    /// reassigned when the automatic mood actually changes, so the dozens of
    /// on-screen backdrops aren't invalidated by a no-op tick.
    private var clock: Date = .now

    @ObservationIgnored private var liveBackdrops = 0
    @ObservationIgnored private var timer: Timer?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.overrideKey) ?? ""
        override = AppMood(rawValue: stored)
    }

    /// Re-evaluates the automatic mood (scene became active, timer tick).
    func refresh() {
        let now = Date.now
        if AppMood.auto(at: now, latitude: latitude, longitude: longitude)
            != AppMood.auto(at: clock, latitude: latitude, longitude: longitude) {
            clock = now
        }
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

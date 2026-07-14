import Foundation
import WeatherKit
import CoreLocation

// MARK: - PropertyWeather diagnostics (the honest side-channel)
//
// `PropertyWeather.refreshIfStale` deliberately swallows WeatherKit errors:
// on advisory surfaces, stale weather beats no weather. But when the fetch
// has NEVER succeeded the cache stays empty forever and every downstream
// surface — the Fundal weather toggle, the Auto rain mood, the temperature
// dial — goes dark with a caption that implies the weather simply "hasn't
// arrived yet". That is not the truth; the truth is an error nobody kept.
//
// This extension adds, by composition only (PropertyWeatherService.swift is
// untouched):
//  1. An error-REPORTING sibling of `refreshIfStale`: same staleness rule,
//     same summary shape, same cache write — plus the failure is recorded
//     alongside the cache (same App Group suite) and a successful write is
//     announced in-process so the mood engine recomposes immediately
//     instead of waiting for its 15-minute tick.
//  2. `lastRefreshError` — the recorded failure, with an "auth-shaped"
//     classification so the UI can hint at the one failure TestFlight
//     builds actually hit: the WeatherKit capability not being active for
//     the App ID (JWT/WeatherDaemon auth errors).
//
// Key contract: `PropertyWeatherService.swift` keeps its `cacheKey` and
// `ttl` private, so this file restates them byte-for-byte. If either ever
// changes there, change it here too:
//   suite  = SharedDataStore.suiteName           ("group.com.prvio.app")
//   cache  = "prvio.weather.summary"             (JSON `Summary`)
//   ttl    = 3600 seconds

extension PropertyWeather {
    /// Byte-for-byte mirror of the private `cacheKey` in
    /// PropertyWeatherService.swift (see the contract note above).
    private static let mirroredCacheKey = "prvio.weather.summary"
    /// Byte-for-byte mirror of the private `ttl`.
    private static let mirroredTTL: TimeInterval = 3600

    /// Diagnostics keys — same suite as the summary so the cache and its
    /// failure story can never live in different containers.
    private static let lastErrorMessageKey = "prvio.weather.lastError.message"
    private static let lastErrorAtKey = "prvio.weather.lastError.at"
    private static let lastErrorAuthKey = "prvio.weather.lastError.authShaped"

    // MARK: The recorded failure

    /// The most recent refresh failure, kept until a fetch succeeds.
    struct LastRefreshError {
        /// The error's own `localizedDescription`, verbatim — surfaces
        /// quote it rather than inventing a friendlier fiction.
        let message: String
        let occurredAt: Date
        /// True when the error smells like WeatherKit authentication
        /// (JWT / WeatherDaemon / 401-class) — on TestFlight this almost
        /// always means the WeatherKit capability is not active for the
        /// App ID, a portal-side fix no retry can perform.
        let looksLikeAuthFailure: Bool
    }

    /// The failure recorded by the last error-reporting refresh, or nil
    /// when none was recorded (or the last fetch succeeded).
    static var lastRefreshError: LastRefreshError? {
        guard let ud = UserDefaults(suiteName: SharedDataStore.suiteName),
              let message = ud.string(forKey: lastErrorMessageKey),
              let at = ud.object(forKey: lastErrorAtKey) as? Date else { return nil }
        return LastRefreshError(message: message,
                                occurredAt: at,
                                looksLikeAuthFailure: ud.bool(forKey: lastErrorAuthKey))
    }

    /// True while a cached summary exists and is younger than the write
    /// TTL — i.e. `refreshIfStale`/`refreshRecordingErrors` would not fetch.
    static var hasFreshCache: Bool {
        guard let cached = cached() else { return false }
        return Date().timeIntervalSince(cached.fetchedAt) < mirroredTTL
    }

    // MARK: Error-reporting refresh

    /// `refreshIfStale`, but honest about failure: identical staleness
    /// rule, identical fetch, identical summary and cache write — plus the
    /// caught error is stored next to the cache and a successful write
    /// posts `.propertyWeatherCacheDidUpdate` so observers (the mood
    /// engine) recompose without waiting for a timer tick.
    ///
    /// Returns true when a fresh summary exists after the call (already
    /// fresh, or the fetch just landed).
    @discardableResult
    static func refreshRecordingErrors(latitude: Double,
                                       longitude: Double) async -> Bool {
        if hasFreshCache { return true }
        do {
            let weather = try await WeatherService.shared.weather(
                for: CLLocation(latitude: latitude, longitude: longitude))
            let current = weather.currentWeather
            let today = weather.dailyForecast.first
            let tomorrow = weather.dailyForecast.dropFirst().first

            let lows = [today, tomorrow].compactMap {
                $0?.lowTemperature.converted(to: .celsius).value
            }
            var advisory: String?
            if let minLow = lows.min(), minLow <= 2 {
                advisory = "frost"
            } else if let chance = tomorrow?.precipitationChance, chance >= 0.5 {
                advisory = "rain"
            }

            let currentTemp = current.temperature.converted(to: .celsius).value
            let summary = Summary(
                temp: currentTemp,
                symbol: current.symbolName,
                lo: today?.lowTemperature.converted(to: .celsius).value ?? currentTemp,
                hi: today?.highTemperature.converted(to: .celsius).value ?? currentTemp,
                advisory: advisory,
                fetchedAt: Date())
            if let ud = UserDefaults(suiteName: SharedDataStore.suiteName),
               let data = try? JSONEncoder().encode(summary) {
                ud.set(data, forKey: mirroredCacheKey)
                ud.removeObject(forKey: lastErrorMessageKey)
                ud.removeObject(forKey: lastErrorAtKey)
                ud.removeObject(forKey: lastErrorAuthKey)
            }
            NotificationCenter.default.post(name: .propertyWeatherCacheDidUpdate,
                                            object: nil)
            return true
        } catch {
            record(error)
            // The old summary (if any) survives — stale weather still beats
            // no weather; only the story about the failure is new.
            return false
        }
    }

    /// Stores the failure alongside the cache (same suite, see keys above).
    private static func record(_ error: Error) {
        guard let ud = UserDefaults(suiteName: SharedDataStore.suiteName) else { return }
        ud.set(error.localizedDescription, forKey: lastErrorMessageKey)
        ud.set(Date(), forKey: lastErrorAtKey)
        ud.set(isAuthShaped(error), forKey: lastErrorAuthKey)
    }

    /// WeatherKit auth failures arrive as JWT/token errors from
    /// WeatherDaemon (e.g. domain "WeatherDaemon.WDSJWTAuthenticatorService-
    /// Listener.Errors") or as 401-class network responses. Matched on the
    /// NSError's domain and description — a heuristic, stated as such.
    private static func isAuthShaped(_ error: Error) -> Bool {
        let ns = error as NSError
        let haystack = "\(ns.domain) \(ns.localizedDescription) \(ns.debugDescription)"
            .lowercased()
        return ["jwt", "auth", "token", "401", "unauthorized", "weatherdaemon"]
            .contains(where: haystack.contains)
    }
}

// MARK: - Cache-update notification

extension Notification.Name {
    /// Posted by `PropertyWeather.refreshRecordingErrors` every time a
    /// fetched summary lands in the App Group cache. `AppMoodEngine`
    /// observes it so a rainy fetch turns the backdrop without waiting for
    /// the 15-minute tick or a scene change.
    static let propertyWeatherCacheDidUpdate =
        Notification.Name("prvio.weather.cacheDidUpdate")
}

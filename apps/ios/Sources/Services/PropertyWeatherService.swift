import Foundation
import WeatherKit
import CoreLocation

// MARK: - Apple Weather for the property
//
// Fetched on the PHONE (the watch spends no battery on networking) and
// distilled to what the wrist needs: current temperature + condition symbol,
// today's range, and garden advisories — frost tonight, rain tomorrow.
// Cached in the App Group for an hour; failures keep the last summary,
// because weather is advisory and never worth an error state.
//
// Attribution: every surface that renders this data shows " Apple Weather",
// per the WeatherKit terms.

enum PropertyWeather {
    struct Summary: Codable {
        var temp: Double      // °C, current
        var symbol: String    // SF Symbol from WeatherKit's condition
        var lo: Double        // °C, today's low
        var hi: Double        // °C, today's high
        /// "frost" (≤2°C tonight/tomorrow) or "rain" (≥50% chance tomorrow).
        /// Raw token — each surface localizes it in its own language.
        var advisory: String?
        var fetchedAt: Date
    }

    private static let cacheKey = "prvio.weather.summary"
    private static let ttl: TimeInterval = 3600

    static func cached() -> Summary? {
        guard let ud = UserDefaults(suiteName: SharedDataStore.suiteName),
              let data = ud.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }

    static func refreshIfStale(latitude: Double, longitude: Double) async {
        if let cached = cached(), Date().timeIntervalSince(cached.fetchedAt) < ttl { return }
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
                ud.set(data, forKey: cacheKey)
            }
        } catch {
            // Keep whatever summary we had — stale weather beats no weather.
        }
    }
}

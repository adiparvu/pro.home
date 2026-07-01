import Foundation
import Observation
import WeatherKit
import CoreLocation

@MainActor
@Observable
final class WeatherKitService {
    static let shared = WeatherKitService()

    var currentWeather: CurrentWeather?
    var hourlyForecast: [HourWeather] = []
    var dailyForecast: [DayWeather] = []
    var isLoading = false
    var error: String?

    private let service = WeatherService.shared

    private init() {}

    func fetch(for coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        error = nil
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let weather = try await service.weather(
                for: location,
                including: .current, .hourly, .daily
            )
            currentWeather = weather.0
            hourlyForecast = Array(weather.1.forecast.prefix(24))
            dailyForecast = Array(weather.2.forecast.prefix(7))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var temperatureString: String {
        guard let w = currentWeather else { return "–" }
        let t = w.temperature.converted(to: .celsius)
        return "\(Int(t.value))°C"
    }

    var conditionSymbol: String {
        guard let w = currentWeather else { return "cloud.fill" }
        return w.symbolName
    }

    var conditionDescription: String {
        guard let w = currentWeather else { return "–" }
        return w.condition.description
    }

    var feelsLikeString: String {
        guard let w = currentWeather else { return "–" }
        let t = w.apparentTemperature.converted(to: .celsius)
        return "Simțit: \(Int(t.value))°C"
    }

    var humidityString: String {
        guard let w = currentWeather else { return "–" }
        return "Umiditate: \(Int(w.humidity * 100))%"
    }

    var windString: String {
        guard let w = currentWeather else { return "–" }
        let speed = w.wind.speed.converted(to: .kilometersPerHour)
        return "Vânt: \(Int(speed.value)) km/h"
    }
}

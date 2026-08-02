import Foundation

// MARK: - Weather-aware watering care (pure)
//
// Bends a plant's watering-due date around the property's REAL weather —
// the `PropertyWeather` summary the dashboard already fetches — without
// owning any I/O itself: callers hand in a due date and a distilled
// snapshot, this type only decides. Two deliberately conservative rules,
// each clamped to a single day and each outdoor-only:
//
//  • rain (falling now per the condition symbol, or a ≥50% chance flagged
//    by the fetch-time "rain" advisory) POSTPONES by one day — the sky is
//    about to do the watering;
//  • sustained heat (≥30 °C, current or today's high) ADVANCES by one day —
//    outdoor soil dries faster than the fixed interval assumes.
//
// Indoor plants never move: rain does not reach a windowsill, and a
// radiator-warm room is not a heat wave. "both" placement stays untouched
// too — a plant that migrates in and out may well be inside today, and a
// care schedule must never shift on a guess. When rain and heat coincide,
// rain wins: the rain delivers exactly the water the heat would have
// demanded sooner.

enum PlantWeatherCare {

    /// Outdoor heat threshold (°C). At or above this, an outdoor plant's
    /// due date moves one day earlier.
    static let heatThresholdC: Double = 30

    /// A cached summary older than this can no longer speak for "today",
    /// so no adjustment is derived from it at all (same honesty gate as
    /// `PropertyRulesStore.weatherSnapshot` / `AppWeatherTone.maxAge` —
    /// stale weather beats no weather on a dashboard tile, but never gets
    /// to move a care schedule).
    static let maxSnapshotAge: TimeInterval = 6 * 3600

    // MARK: Inputs

    /// The weather facts the rules read, distilled to exactly two values so
    /// tests can state them directly and the rule can't quietly grow more
    /// inputs than it documents.
    struct Conditions: Equatable {
        var rainLikely: Bool
        var highTempC: Double

        init(rainLikely: Bool, highTempC: Double) {
            self.rainLikely = rainLikely
            self.highTempC = highTempC
        }

        /// Distills the cached App-Group summary; nil when the snapshot is
        /// too old to stand behind. Rain uses the same symbol test as
        /// `PropertyRulesStore.matches` (the condition symbol names the
        /// falling water itself) plus the fetch-time "rain" advisory, which
        /// `PropertyWeather` sets on a ≥50% precipitation chance.
        init?(summary: PropertyWeather.Summary, now: Date = Date()) {
            guard now.timeIntervalSince(summary.fetchedAt) <= PlantWeatherCare.maxSnapshotAge else {
                return nil
            }
            let s = summary.symbol.lowercased()
            rainLikely = s.contains("rain") || s.contains("drizzle") || summary.advisory == "rain"
            // The hotter of "right now" and "today's high": a 31° afternoon
            // counts even when the fetch happened during a 24° morning.
            highTempC = max(summary.temp, summary.hi)
        }
    }

    // MARK: Output

    /// Why a due date moved — carries its own glyph and sentence so every
    /// surface tells the same story.
    enum Reason: Equatable {
        case rainPostponed
        case heatAdvanced

        var symbol: String {
            switch self {
            case .rainPostponed: return "cloud.rain"
            case .heatAdvanced:  return "thermometer.sun"
            }
        }

        var localizedText: String {
            switch self {
            case .rainPostponed: return String(localized: "plant_care_weather_rain")
            case .heatAdvanced:  return String(localized: "plant_care_weather_heat")
            }
        }
    }

    struct Adjustment: Equatable {
        var dueDate: Date
        /// nil means the weather left the schedule alone — callers show the
        /// reason line only when this is set.
        var reason: Reason?
    }

    // MARK: Rule

    /// The one decision: given the schedule's own due date, where does the
    /// weather move it? Never more than one calendar day in either
    /// direction, and never at all for anything but a plainly outdoor
    /// plant or when conditions are missing/stale (nil).
    static func adjustedDue(baseline: Date,
                            placement: String?,
                            conditions: Conditions?,
                            calendar: Calendar = .current) -> Adjustment {
        guard placement == "outdoor", let conditions else {
            return Adjustment(dueDate: baseline, reason: nil)
        }
        if conditions.rainLikely {
            let postponed = calendar.date(byAdding: .day, value: 1, to: baseline) ?? baseline
            return Adjustment(dueDate: postponed, reason: .rainPostponed)
        }
        if conditions.highTempC >= heatThresholdC {
            let advanced = calendar.date(byAdding: .day, value: -1, to: baseline) ?? baseline
            return Adjustment(dueDate: advanced, reason: .heatAdvanced)
        }
        return Adjustment(dueDate: baseline, reason: nil)
    }
}

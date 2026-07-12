import SwiftUI

// MARK: - Plant Health Score (Plant OS P6)
//
// An explainable 0–100 score computed ONLY from real inputs:
//   • watering discipline vs the plant's interval (from its last watering)
//   • care-event recency (from plant_events)
//   • bound-sensor readings vs the species' numeric bands (P2/P3 data)
//   • photo recency (from plant_photos)
//
// HONESTY LAW — the core of this model:
//   A factor contributes ONLY when it has real data. A missing factor is NOT
//   scored as zero and NOT given an invented default reading — it is excluded,
//   and the denominator (the sum of available weights) shrinks accordingly. The
//   final score is therefore always "of what we can actually measure", and the
//   UI names exactly which factors were left out. With no factors available at
//   all, the score is nil ("not enough data yet") — never a fabricated number.

enum PlantHealthFactorKind: String, Identifiable, CaseIterable {
    case watering, care, sensors, photo
    var id: String { rawValue }

    /// Fixed weights (points out of 100 when ALL factors are available). When
    /// some are missing these are renormalised across the available ones.
    var weight: Double {
        switch self {
        case .watering: return 35
        case .sensors:  return 30
        case .care:     return 20
        case .photo:    return 15
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .watering: return "plant_score_f_watering"
        case .care:     return "plant_score_f_care"
        case .sensors:  return "plant_score_f_sensors"
        case .photo:    return "plant_score_f_photo"
        }
    }

    var icon: String {
        switch self {
        case .watering: return "drop.fill"
        case .care:     return "hand.raised.fill"
        case .sensors:  return "sensor.tag.radiowaves.forward.fill"
        case .photo:    return "camera.fill"
        }
    }
}

/// One computed factor. `subScore` is nil when the factor has no real data —
/// that is what shrinks the denominator.
struct PlantHealthFactor: Identifiable {
    let kind: PlantHealthFactorKind
    /// 0...1, or nil when unavailable (no real data).
    let subScore: Double?
    /// A short status headline for the available case (e.g. "2 days overdue").
    let headline: String
    /// A concrete recommendation the user can act on.
    let recommendation: String

    var id: String { kind.rawValue }
    var isAvailable: Bool { subScore != nil }

    /// Renormalised max points this factor can contribute given which factors
    /// were available (set by `PlantHealthScore.compute`).
    var maxPoints: Double = 0
    /// Points this factor actually contributed to the final score.
    var earnedPoints: Double = 0
}

struct PlantHealthScore {
    /// nil = not enough real data to score honestly.
    let value: Int?
    let factors: [PlantHealthFactor]
    let computedAt: Date

    var availableFactors: [PlantHealthFactor] { factors.filter(\.isAvailable) }
    var missingFactors: [PlantHealthFactor] { factors.filter { !$0.isAvailable } }

    // MARK: Presentation

    /// Colour band for the ring, using design-system brand tokens.
    var color: Color {
        guard let v = value else { return .secondary }
        return Self.color(for: v)
    }

    /// Band colour for a bare persisted score — passive surfaces (the plant
    /// card badge) show the stored value without recomputing the full score.
    static func color(for value: Int) -> Color {
        switch value {
        case 80...:   return .brandSuccess
        case 60..<80: return Color(red: 0.55, green: 0.78, blue: 0.35) // healthy lime
        case 40..<60: return .brandWarning
        default:      return .brandDanger
        }
    }

    var bandLabel: LocalizedStringKey {
        guard let v = value else { return "plant_score_band_unknown" }
        switch v {
        case 80...:   return "plant_score_band_thriving"
        case 60..<80: return "plant_score_band_healthy"
        case 40..<60: return "plant_score_band_needs_care"
        default:      return "plant_score_band_struggling"
        }
    }

    // MARK: - Compute

    static func compute(plant: Plant,
                        events: [PlantEvent],
                        photos: [PlantPhoto],
                        species: PlantSpeciesEntry?,
                        sensorReadings: [PlantCareMetric: Double],
                        now: Date = Date()) -> PlantHealthScore {
        var factors = [
            wateringFactor(plant: plant, events: events, now: now),
            careFactor(events: events, now: now),
            sensorFactor(species: species, readings: sensorReadings),
            photoFactor(photos: photos, now: now),
        ]

        // Renormalise across the available factors (shrinking denominator).
        let availableWeight = factors.filter(\.isAvailable).reduce(0.0) { $0 + $1.kind.weight }
        guard availableWeight > 0 else {
            return PlantHealthScore(value: nil, factors: factors, computedAt: now)
        }
        var total = 0.0
        for i in factors.indices {
            guard let sub = factors[i].subScore else { continue }
            let maxPts = factors[i].kind.weight / availableWeight * 100
            factors[i].maxPoints = maxPts
            factors[i].earnedPoints = maxPts * sub
            total += factors[i].earnedPoints
        }
        return PlantHealthScore(value: Int(total.rounded()), factors: factors, computedAt: now)
    }

    // MARK: - Factor: watering discipline

    private static func wateringFactor(plant: Plant, events: [PlantEvent], now: Date) -> PlantHealthFactor {
        let interval = max(1, plant.wateringIntervalDays)
        // Prefer the plant's canonical last-watered stamp; fall back to the
        // newest watering EVENT. Either is a real, user-recorded action.
        let lastWater: Date? = plant.lastWateredAtDate
            ?? events.first(where: { $0.kindEnum == .watered })?.date
        guard let last = lastWater else {
            return PlantHealthFactor(
                kind: .watering, subScore: nil,
                headline: String(localized: "plant_score_watering_none_head"),
                recommendation: String(localized: "plant_score_watering_none_rec"))
        }
        let days = daysBetween(last, now)
        let ratio = Double(days) / Double(interval)
        let sub: Double
        if ratio <= 1 { sub = 1 }
        else if ratio >= 2 { sub = 0 }
        else { sub = 1 - (ratio - 1) } // linear 1→0 across one extra interval

        let overdue = days - interval
        let headline: String
        let rec: String
        if overdue <= 0 {
            headline = String(localized: "plant_score_watering_ok_head")
            rec = String(format: String(localized: "plant_score_watering_ok_rec"), interval)
        } else {
            headline = String(format: String(localized: "plant_score_watering_late_head"), overdue)
            rec = String(localized: "plant_score_watering_late_rec")
        }
        return PlantHealthFactor(kind: .watering, subScore: sub, headline: headline, recommendation: rec)
    }

    // MARK: - Factor: care recency

    private static func careFactor(events: [PlantEvent], now: Date) -> PlantHealthFactor {
        guard let newest = events.compactMap(\.date).max() else {
            return PlantHealthFactor(
                kind: .care, subScore: nil,
                headline: String(localized: "plant_score_care_none_head"),
                recommendation: String(localized: "plant_score_care_none_rec"))
        }
        let days = daysBetween(newest, now)
        // Fresh within 14 days, decaying to 0 by 90 days.
        let sub = clamp(1 - Double(max(0, days - 14)) / Double(90 - 14))
        let headline = days == 0
            ? String(localized: "plant_score_care_today_head")
            : String(format: String(localized: "plant_score_care_days_head"), days)
        let rec = sub >= 0.75
            ? String(localized: "plant_score_care_ok_rec")
            : String(localized: "plant_score_care_low_rec")
        return PlantHealthFactor(kind: .care, subScore: sub, headline: headline, recommendation: rec)
    }

    // MARK: - Factor: bound-sensor readings vs species bands

    private static func sensorFactor(species: PlantSpeciesEntry?,
                                     readings: [PlantCareMetric: Double]) -> PlantHealthFactor {
        guard let species else {
            return PlantHealthFactor(
                kind: .sensors, subScore: nil,
                headline: String(localized: "plant_score_sensors_none_head"),
                recommendation: String(localized: "plant_score_sensors_none_rec"))
        }
        var subs: [(metric: PlantCareMetric, verdict: BandVerdict)] = []
        for metric in PlantCareMetric.allCases {
            guard let value = readings[metric],
                  let verdict = bandVerdict(metric, value: value, species: species) else { continue }
            subs.append((metric, verdict))
        }
        guard !subs.isEmpty else {
            return PlantHealthFactor(
                kind: .sensors, subScore: nil,
                headline: String(localized: "plant_score_sensors_none_head"),
                recommendation: String(localized: "plant_score_sensors_none_rec"))
        }
        let avg = subs.reduce(0.0) { $0 + $1.verdict.sub } / Double(subs.count)
        // The worst metric drives the recommendation.
        let worst = subs.min { $0.verdict.sub < $1.verdict.sub }!
        let headline: String
        let rec: String
        if worst.verdict.sub >= 0.7 {
            headline = String(format: String(localized: "plant_score_sensors_ok_head"), subs.count)
            rec = String(localized: "plant_score_sensors_ok_rec")
        } else {
            let metricName = String(localized: metricKey(worst.metric))
            headline = worst.verdict.isLow
                ? String(format: String(localized: "plant_score_sensors_low_head"), metricName)
                : String(format: String(localized: "plant_score_sensors_high_head"), metricName)
            rec = worst.verdict.isLow
                ? String(format: String(localized: "plant_score_sensors_low_rec"), metricName)
                : String(format: String(localized: "plant_score_sensors_high_rec"), metricName)
        }
        return PlantHealthFactor(kind: .sensors, subScore: avg, headline: headline, recommendation: rec)
    }

    // MARK: - Factor: photo recency

    private static func photoFactor(photos: [PlantPhoto], now: Date) -> PlantHealthFactor {
        let newest = photos.compactMap { ISODate.date(from: $0.takenAt) }.max()
        guard let newest else {
            return PlantHealthFactor(
                kind: .photo, subScore: nil,
                headline: String(localized: "plant_score_photo_none_head"),
                recommendation: String(localized: "plant_score_photo_none_rec"))
        }
        let days = daysBetween(newest, now)
        // Fresh within 30 days, decaying to 0 by 180 days.
        let sub = clamp(1 - Double(max(0, days - 30)) / Double(180 - 30))
        let headline = String(format: String(localized: "plant_score_photo_days_head"), days)
        let rec = sub >= 0.75
            ? String(localized: "plant_score_photo_ok_rec")
            : String(localized: "plant_score_photo_low_rec")
        return PlantHealthFactor(kind: .photo, subScore: sub, headline: headline, recommendation: rec)
    }

    // MARK: - Band verdict (mirrors PlantCareCard's comparison logic)

    private enum BandVerdict { case ideal, accepted, low, high, dangerLow, dangerHigh
        var sub: Double {
            switch self {
            case .ideal:      return 1.0
            case .accepted:   return 0.7
            case .low, .high: return 0.4
            case .dangerLow, .dangerHigh: return 0.0
            }
        }
        var isLow: Bool { self == .low || self == .dangerLow }
    }

    private static func bandVerdict(_ metric: PlantCareMetric, value v: Double,
                                    species e: PlantSpeciesEntry) -> BandVerdict? {
        switch metric {
        case .light:
            guard e.hasLightData else { return nil }
            if let mx = e.lightLuxMax, v > Double(mx) { return .high }
            if let mn = e.lightLuxMin, v < Double(mn) { return .low }
            return .ideal
        case .humidity:
            guard e.hasHumidityData else { return nil }
            if let iMin = e.humidityIdealMin, let iMax = e.humidityIdealMax,
               v >= Double(iMin), v <= Double(iMax) { return .ideal }
            let aMin = e.humidityAcceptedMin ?? e.humidityIdealMin
            let aMax = e.humidityAcceptedMax ?? e.humidityIdealMax
            if let aMin, v < Double(aMin) { return .low }
            if let aMax, v > Double(aMax) { return .high }
            return .accepted
        case .temperature:
            guard e.hasTempData else { return nil }
            if let lo = e.tempDangerLow, v < lo { return .dangerLow }
            if let hi = e.tempDangerHigh, v > hi { return .dangerHigh }
            if let iMin = e.tempIdealMin, let iMax = e.tempIdealMax,
               v >= iMin, v <= iMax { return .ideal }
            let aMin = e.tempAcceptedMin ?? e.tempIdealMin
            let aMax = e.tempAcceptedMax ?? e.tempIdealMax
            if let aMin, v < aMin { return .low }
            if let aMax, v > aMax { return .high }
            return .accepted
        }
    }

    private static func metricKey(_ m: PlantCareMetric) -> String.LocalizationValue {
        switch m {
        case .light:       return "plant_care_light"
        case .temperature: return "plant_care_temperature"
        case .humidity:    return "plant_care_humidity"
        }
    }

    // MARK: - Helpers

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }
}

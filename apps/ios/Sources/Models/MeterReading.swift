import SwiftUI

// MARK: - Utility meters ("Contoare & utilități")
//
// Manual index readings for the property's meters — the monthly ritual every
// RO/BE household knows. Consumption is ALWAYS a derived delta between two
// real readings (honesty law: no interpolation, no estimated usage); a month
// with a single reading shows the index, never an invented consumption.
// The table (`meter_readings`) predates this module from the Smart Home
// migrations — this client adopts its exact shape.

enum MeterKind: String, CaseIterable, Identifiable {
    case electricity, gas, water
    case hotWater = "hot_water"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .electricity: return "bolt.fill"
        case .gas:         return "flame.fill"
        case .water:       return "drop.fill"
        case .hotWater:    return "drop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .electricity: return .brandWarning
        case .gas:         return .brandDanger
        case .water:       return .brandPrimaryBlue
        case .hotWater:    return .brandPurple
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .electricity: return "meter_electricity"
        case .gas:         return "meter_gas"
        case .water:       return "meter_water"
        case .hotWater:    return "meter_hot_water"
        }
    }

    /// The customary unit the index is read in.
    var defaultUnit: String {
        switch self {
        case .electricity: return "kWh"
        case .gas, .water, .hotWater: return "m³"
        }
    }
}

struct MeterReading: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var meterType: String
    var meterId: String?
    var reading: Double
    var unit: String?
    var readingDate: String        // "YYYY-MM-DD"
    var photoUrl: String?
    var notes: String?
    var loggedBy: UUID?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reading, unit, notes
        case propertyId  = "property_id"
        case meterType   = "meter_type"
        case meterId     = "meter_id"
        case readingDate = "reading_date"
        case photoUrl    = "photo_url"
        case loggedBy    = "logged_by"
        case createdAt   = "created_at"
    }

    var kind: MeterKind? { MeterKind(rawValue: meterType) }
    var date: Date? { AppDate.day(from: readingDate) }
    var unitDisplay: String { unit ?? kind?.defaultUnit ?? "" }
}

// MARK: - Derived consumption (pure, testable)

enum MeterStats {
    struct MonthPoint: Identifiable {
        let monthStart: Date
        let label: String
        let consumption: Double
        var id: Date { monthStart }
    }

    /// Consumption between consecutive readings of ONE meter, newest first:
    /// (reading, delta vs the previous chronological reading). The oldest
    /// reading has no delta — there is nothing honest to subtract from.
    static func deltas(for readings: [MeterReading]) -> [(reading: MeterReading, delta: Double?)] {
        let sorted = readings.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        var out: [(MeterReading, Double?)] = []
        for (i, r) in sorted.enumerated() {
            let delta = i > 0 ? max(0, r.reading - sorted[i - 1].reading) : nil
            out.append((r, delta))
        }
        return out.reversed()
    }

    /// Monthly consumption for the chart: the delta between each month's LAST
    /// index and the previous month's last index, over the trailing `months`.
    /// Months without enough data are simply absent — never zero-filled.
    static func monthlyConsumption(for readings: [MeterReading], months: Int = 6) -> [MonthPoint] {
        let cal = Calendar.current
        var lastPerMonth: [Date: Double] = [:]
        for r in readings {
            guard let d = r.date else { continue }
            let m = cal.startOfMonth(d)
            // Keep the chronologically last index of the month.
            if let existing = lastPerMonth[m] {
                lastPerMonth[m] = max(existing, r.reading)
            } else {
                lastPerMonth[m] = r.reading
            }
        }
        let orderedMonths = lastPerMonth.keys.sorted()
        var points: [MonthPoint] = []
        for (i, m) in orderedMonths.enumerated() where i > 0 {
            let delta = max(0, (lastPerMonth[m] ?? 0) - (lastPerMonth[orderedMonths[i - 1]] ?? 0))
            points.append(MonthPoint(monthStart: m,
                                     label: AppDate.monthLabel.string(from: m).capitalized,
                                     consumption: delta))
        }
        return Array(points.suffix(months))
    }
}

import Foundation
import Observation

// MARK: - Energy store (Spaces tab energy card)
//
// One honest daily-energy aggregate over the account's own `iot_events`
// history (per-user RLS — every figure comes from THIS account's sensors,
// never a fleet average or a fabricated baseline).
//
// The honesty contract, in full:
// - `.energy` sensors are cumulative kWh counters: a day's consumption is
//   last reading − first reading of that day, clamped ≥ 0 (counter resets).
//   That is a MEASUREMENT (`isEstimate` false).
// - `.power` sensors are instantaneous watts: the day's kWh is a
//   time-weighted trapezoid over the ACTUAL sample timestamps; any gap
//   longer than two hours contributes ZERO — silence is never interpolated.
//   That is an ESTIMATE (`isEstimate` true, sample count carried so the UI
//   can say exactly how many readings it rests on).
// - A day with no readings at all is nil, never 0.0 — the card says "no
//   readings" instead of claiming a measured zero.
// - Production sensors (`isProduction`) are summed separately and NEVER
//   netted against consumption.

/// One day's energy figure: the kWh total, whether any estimated (power-
/// integrated) component contributed, and how many samples fed the estimate.
struct EnergyFigure {
    let kWh: Double
    let isEstimate: Bool
    let sampleCount: Int
}

@MainActor
@Observable
final class EnergyStore {
    static let shared = EnergyStore()
    private init() {}

    /// Today's consumption so far; nil until at least one reading exists.
    private(set) var today: EnergyFigure?
    /// Yesterday's full-day consumption; nil when yesterday holds no readings.
    private(set) var yesterday: EnergyFigure?
    /// Today's consumption bucketed by the sensor's linked zone, largest
    /// first; sensors without a zone pool into one localized "other" row
    /// that exists only when it actually received contributions.
    private(set) var perZone: [(zone: String, kWh: Double)] = []
    /// Today's production (solar) — a separate line, never netted.
    private(set) var producedToday: Double?

    @ObservationIgnored private var lastRefreshAt: Date?
    @ObservationIgnored private var isRefreshing = false

    /// At most one server refresh per window; appear/foreground calls
    /// inside it are free no-ops.
    static let refreshInterval: TimeInterval = 15 * 60
    /// A sampling gap longer than this contributes zero to the trapezoid —
    /// never interpolate across silence.
    static let maxIntegrationGap: TimeInterval = 2 * 3_600

    /// Whether the installation has any sensor the energy card can speak
    /// for: instantaneous power (W) or cumulative energy (kWh) types.
    var hasEnergySensors: Bool {
        IoTService.shared.sensors.contains(where: Self.isEnergySensor)
    }

    private static func isEnergySensor(_ sensor: IoTSensor) -> Bool {
        sensor.type == .power || sensor.type == .energy
    }

    // MARK: Refresh

    func refreshIfStale() async {
        if let last = lastRefreshAt,
           Date().timeIntervalSince(last) < Self.refreshInterval { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let sensors = IoTService.shared.sensors.filter(Self.isEnergySensor)
        guard !sensors.isEmpty else {
            today = nil; yesterday = nil; perZone = []; producedToday = nil
            return
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart),
              let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else { return }

        // One bounded history query per sensor, fanned out concurrently.
        let service = IoTService.shared
        var histories: [UUID: [IoTHistoryPoint]] = [:]
        histories.reserveCapacity(sensors.count)
        await withTaskGroup(of: (UUID, [IoTHistoryPoint]).self) { group in
            for sensor in sensors {
                let id = sensor.id
                group.addTask {
                    // A failed fetch yields no points — the sensor simply
                    // doesn't contribute this pass; never a made-up value.
                    let points = (try? await service.sensorHistory(
                        sensorId: id.uuidString, since: yesterdayStart)) ?? []
                    return (id, points)
                }
            }
            for await (id, points) in group { histories[id] = points }
        }

        aggregate(sensors: sensors, histories: histories,
                  yesterdayStart: yesterdayStart,
                  todayStart: todayStart, todayEnd: todayEnd)
        lastRefreshAt = Date()
    }

    // MARK: Aggregation

    private func aggregate(sensors: [IoTSensor],
                           histories: [UUID: [IoTHistoryPoint]],
                           yesterdayStart: Date, todayStart: Date, todayEnd: Date) {
        var todayKWh = 0.0, todaySamples = 0
        var todayEstimated = false, todayHasData = false
        var yesterdayKWh = 0.0, yesterdaySamples = 0
        var yesterdayEstimated = false, yesterdayHasData = false
        var produced: Double?
        var namedZones: [String: Double] = [:]
        var unzoned: Double?

        for sensor in sensors {
            let points = histories[sensor.id] ?? []

            // Production is its own line — NEVER netted against consumption.
            if sensor.isProduction == true {
                if let c = Self.dayContribution(points, from: todayStart, to: todayEnd,
                                                type: sensor.type) {
                    produced = (produced ?? 0) + c.kWh
                }
                continue
            }

            if let c = Self.dayContribution(points, from: todayStart, to: todayEnd,
                                            type: sensor.type) {
                todayHasData = true
                todayKWh += c.kWh
                if c.isEstimate { todayEstimated = true; todaySamples += c.samples }
                let zone = sensor.linkedZoneName
                if zone.isEmpty {
                    unzoned = (unzoned ?? 0) + c.kWh
                } else {
                    namedZones[zone, default: 0] += c.kWh
                }
            }
            if let c = Self.dayContribution(points, from: yesterdayStart, to: todayStart,
                                            type: sensor.type) {
                yesterdayHasData = true
                yesterdayKWh += c.kWh
                if c.isEstimate { yesterdayEstimated = true; yesterdaySamples += c.samples }
            }
        }

        today = todayHasData
            ? EnergyFigure(kWh: todayKWh, isEstimate: todayEstimated, sampleCount: todaySamples)
            : nil
        yesterday = yesterdayHasData
            ? EnergyFigure(kWh: yesterdayKWh, isEstimate: yesterdayEstimated, sampleCount: yesterdaySamples)
            : nil
        producedToday = produced

        var zones = namedZones
            .map { (zone: $0.key, kWh: $0.value) }
            .sorted { $0.kWh == $1.kWh ? $0.zone < $1.zone : $0.kWh > $1.kWh }
        if let unzoned {
            zones.append((zone: String(localized: "energy_zone_other"), kWh: unzoned))
        }
        perZone = zones
    }

    /// One sensor's kWh for one day window, honest per type — or nil when
    /// the window holds no readings (never a claimed zero).
    private static func dayContribution(_ points: [IoTHistoryPoint],
                                        from start: Date, to end: Date,
                                        type: IoTSensor.SensorType)
        -> (kWh: Double, samples: Int, isEstimate: Bool)? {
        // Points arrive oldest-first; keep only real values inside the day.
        let day = points.filter { $0.createdAt >= start && $0.createdAt < end && $0.value != nil }
        guard !day.isEmpty else { return nil }

        switch type {
        case .energy:
            // Cumulative counter: MEASURED day delta, clamped for resets.
            guard let first = day.first?.value, let last = day.last?.value else { return nil }
            return (kWh: max(0, last - first), samples: day.count, isEstimate: false)

        case .power:
            // Instantaneous watts: trapezoid over the actual timestamps;
            // gaps beyond the threshold contribute nothing.
            var wattHours = 0.0
            for index in 1..<day.count {
                guard let previous = day[index - 1].value,
                      let current = day[index].value else { continue }
                let dt = day[index].createdAt.timeIntervalSince(day[index - 1].createdAt)
                guard dt > 0, dt <= maxIntegrationGap else { continue }
                wattHours += (previous + current) / 2 * (dt / 3_600)
            }
            return (kWh: wattHours / 1_000, samples: day.count, isEstimate: true)

        default:
            // Current/voltage etc. can't honestly become kWh — excluded.
            return nil
        }
    }
}

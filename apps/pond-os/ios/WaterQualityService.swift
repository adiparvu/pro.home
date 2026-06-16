import Foundation
import Supabase

// MARK: - Water Quality Service
//
// Manages water quality readings: manual entry, HA entity sync,
// historical queries for SensorChart, and alert generation.
// Uses the same sensor_readings Supabase table as the main PRVIO Twin sensor overlay.

@MainActor
final class WaterQualityService: ObservableObject {

    // MARK: Published

    @Published private(set) var latestReadings: [WaterParameter: WaterQualityReading] = [:]
    @Published private(set) var activeAlerts: [PondAlert] = []
    @Published private(set) var isLoading = false

    private let db = SupabaseClient.shared

    // MARK: Latest Readings (one per parameter)

    func loadLatest(for pondId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let readings: [WaterQualityReading] = try await db
                .from("water_quality_readings")
                .select()
                .eq("pond_id", value: pondId.uuidString)
                .order("recorded_at", ascending: false)
                .limit(100)
                .execute()
                .value

            var map: [WaterParameter: WaterQualityReading] = [:]
            for reading in readings {
                if map[reading.parameter] == nil {
                    map[reading.parameter] = reading
                }
            }
            latestReadings = map
            activeAlerts = generateAlerts(from: map, pondId: pondId)
        } catch {
            // Silent — caller handles absence of data
        }
    }

    // MARK: History (for SensorChart)

    func loadHistory(
        pondId: UUID,
        parameter: WaterParameter,
        from startDate: Date,
        to endDate: Date = Date()
    ) async throws -> [WaterQualityReading] {
        let formatter = ISO8601DateFormatter()
        return try await db
            .from("water_quality_readings")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .eq("parameter", value: parameter.rawValue)
            .gte("recorded_at", value: formatter.string(from: startDate))
            .lte("recorded_at", value: formatter.string(from: endDate))
            .order("recorded_at")
            .execute()
            .value
    }

    // MARK: Record Reading (manual entry or HA sync)

    func record(
        pondId: UUID,
        parameter: WaterParameter,
        value: Double,
        source: ReadingSource = .manual
    ) async throws {
        let sourceString: String
        switch source {
        case .manual:             sourceString = "manual"
        case .esphome(let id):    sourceString = "esphome:\(id)"
        case .haEntity(let id):   sourceString = "ha:\(id)"
        case .predicted:          sourceString = "predicted"
        }

        let payload = NewWaterQualityReading(
            pondId: pondId.uuidString,
            parameter: parameter.rawValue,
            value: value,
            source: sourceString,
            recordedAt: ISO8601DateFormatter().string(from: Date())
        )
        let saved: WaterQualityReading = try await db
            .from("water_quality_readings")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        latestReadings[parameter] = saved

        // Re-evaluate alerts after new reading
        activeAlerts = generateAlerts(from: latestReadings, pondId: pondId)
    }

    // MARK: Sync from HA Entity Bridge
    //
    // Called by HAEntityBridge when a pond-mapped sensor entity changes state.
    // Maps HA entity_id → WaterParameter via ha_entity_mappings table.

    func syncFromHA(pondId: UUID, parameter: WaterParameter, value: Double, entityId: String) async {
        try? await record(
            pondId: pondId,
            parameter: parameter,
            value: value,
            source: .haEntity(entityId: entityId)
        )
    }

    // MARK: Alert Generation
    //
    // Pure function — no side effects. Uses WaterParameter.koiHealthyRange.
    // Extends the existing PondAlert model — no dependency on TwinAlert.

    private func generateAlerts(
        from readings: [WaterParameter: WaterQualityReading],
        pondId: UUID
    ) -> [PondAlert] {
        var alerts: [PondAlert] = []

        for (parameter, reading) in readings {
            let value = reading.value

            // Critical threshold check
            if let criticalHigh = parameter.criticalHigh, value > criticalHigh {
                alerts.append(PondAlert(
                    pondId: pondId,
                    parameter: parameter,
                    severity: .critical,
                    title: "\(parameter.displayName) critical",
                    message: "Value \(String(format: "%.2f", value)) \(parameter.unit) exceeds critical threshold of \(criticalHigh)."
                ))
                continue
            }
            if let criticalLow = parameter.criticalLow, value < criticalLow {
                alerts.append(PondAlert(
                    pondId: pondId,
                    parameter: parameter,
                    severity: .critical,
                    title: "\(parameter.displayName) critically low",
                    message: "Value \(String(format: "%.2f", value)) \(parameter.unit) is below critical minimum of \(criticalLow)."
                ))
                continue
            }

            // Healthy range check
            if let range = parameter.koiHealthyRange {
                if value < range.lowerBound {
                    let severity: PondAlertSeverity = value < range.lowerBound * 0.8 ? .warning : .info
                    alerts.append(PondAlert(
                        pondId: pondId,
                        parameter: parameter,
                        severity: severity,
                        title: "\(parameter.displayName) low",
                        message: "Current: \(String(format: "%.2f", value)) \(parameter.unit). Healthy range: \(range.lowerBound)–\(range.upperBound)."
                    ))
                } else if value > range.upperBound {
                    let severity: PondAlertSeverity = value > range.upperBound * 1.2 ? .warning : .info
                    alerts.append(PondAlert(
                        pondId: pondId,
                        parameter: parameter,
                        severity: severity,
                        title: "\(parameter.displayName) high",
                        message: "Current: \(String(format: "%.2f", value)) \(parameter.unit). Healthy range: \(range.lowerBound)–\(range.upperBound)."
                    ))
                }
            }
        }

        return alerts.sorted { $0.severity > $1.severity }
    }

    // MARK: Load Active Alerts

    func loadAlerts(for pondId: UUID) async throws -> [PondAlert] {
        try await db
            .from("pond_alerts")
            .select()
            .eq("pond_id", value: pondId.uuidString)
            .is("resolved_at", value: nil)
            .order("triggered_at", ascending: false)
            .execute()
            .value
    }

    func acknowledgeAlert(_ alert: PondAlert) async throws {
        struct Payload: Codable {
            let isAcknowledged: Bool
            enum CodingKeys: String, CodingKey {
                case isAcknowledged = "is_acknowledged"
            }
        }
        try await db
            .from("pond_alerts")
            .update(Payload(isAcknowledged: true))
            .eq("id", value: alert.id.uuidString)
            .execute()
        activeAlerts.removeAll { $0.id == alert.id }
    }

    // MARK: AI Water Quality Prediction (stub — Phase 2)
    //
    // Calls ARIA/Claude to predict next 24h water quality trend
    // based on historical readings + weather + feeding schedule.

    func predictNextDay(pondId: UUID) async -> [WaterParameter: Double] {
        // Phase 2: call aria-chat edge function with tool: predict_water_quality
        return [:]
    }
}

import Foundation
import SwiftUI

// MARK: - Pond Health Engine
//
// Scores pond health 0–100. Same scoring philosophy as TwinHealthEngine.
// Does NOT modify TwinHealthEngine — runs independently per pond.
// TwinHealthEngine can include pond scores via Swift extension (see below).

enum PondHealthEngine {

    // MARK: Main Scoring Method

    static func score(
        readings: [WaterParameter: WaterQualityReading],
        populations: [FishPopulation],
        equipment: [PondEquipment],
        activeAlerts: [PondAlert],
        lastFeedingAt: Date?
    ) -> PondHealthSnapshot {
        let pondId = readings.values.first?.pondId ?? UUID()

        let waterScore  = waterQualityScore(from: readings)
        let fishScore   = fishHealthScore(populations: populations, alerts: activeAlerts)
        let equipScore  = equipmentScore(equipment: equipment)

        // Weighted average: water 50%, fish 30%, equipment 20%
        let overall = Int(
            Double(waterScore) * 0.50 +
            Double(fishScore)  * 0.30 +
            Double(equipScore) * 0.20
        )

        return PondHealthSnapshot(
            pondId: pondId,
            overallScore: max(0, min(100, overall)),
            waterQualityScore: waterScore,
            fishHealthScore: fishScore,
            equipmentScore: equipScore,
            alerts: activeAlerts.sorted { $0.severity > $1.severity },
            generatedAt: Date()
        )
    }

    // MARK: Water Quality Score (0–100)
    //
    // Each parameter within healthy range = full points.
    // Outside range = proportional deduction. Critical = heavy penalty.

    static func waterQualityScore(from readings: [WaterParameter: WaterQualityReading]) -> Int {
        guard !readings.isEmpty else { return 50 } // unknown — assume average

        // Parameters by weight (must sum to 1.0)
        let weights: [WaterParameter: Double] = [
            .ph:              0.20,
            .dissolvedOxygen: 0.20,
            .temperature:     0.15,
            .ammonia:         0.15,
            .nitrite:         0.10,
            .nitrate:         0.08,
            .turbidity:       0.05,
            .conductivity:    0.04,
            .orp:             0.03,
        ]

        var totalWeight = 0.0
        var totalScore  = 0.0

        for (parameter, weight) in weights {
            guard let reading = readings[parameter] else { continue }
            let paramScore = parameterScore(reading.value, for: parameter)
            totalScore  += paramScore * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return 50 }
        return Int((totalScore / totalWeight) * 100)
    }

    private static func parameterScore(_ value: Double, for parameter: WaterParameter) -> Double {
        // Critical threshold → 0
        if let critHigh = parameter.criticalHigh, value > critHigh { return 0 }
        if let critLow  = parameter.criticalLow,  value < critLow  { return 0 }

        guard let range = parameter.koiHealthyRange else { return 1.0 }

        if range.contains(value) { return 1.0 }

        let span = range.upperBound - range.lowerBound
        if value < range.lowerBound {
            let deviation = range.lowerBound - value
            return max(0, 1.0 - (deviation / (span * 0.5)))
        } else {
            let deviation = value - range.upperBound
            return max(0, 1.0 - (deviation / (span * 0.5)))
        }
    }

    // MARK: Fish Health Score (0–100)

    static func fishHealthScore(populations: [FishPopulation], alerts: [PondAlert]) -> Int {
        var score = 100

        // No fish → neutral score
        if populations.isEmpty { return 80 }

        // Deduct per active fish-related alert
        for alert in alerts {
            switch alert.severity {
            case .critical: score -= 20
            case .warning:  score -= 8
            case .info:     score -= 3
            }
        }

        return max(0, score)
    }

    // MARK: Equipment Score (0–100)

    static func equipmentScore(equipment: [PondEquipment]) -> Int {
        guard !equipment.isEmpty else { return 70 } // unknown — assume okay

        var score = 100
        let now   = Date()

        for item in equipment {
            // Pump or filter not running → penalty
            if (item.type == .pump || item.type == .filter) && !item.isRunning {
                score -= 20
            }

            // Overdue maintenance (>90 days since last service)
            if let last = item.lastMaintenanceAt,
               now.timeIntervalSince(last) > 90 * 86400 {
                score -= 8
            }

            // Warranty expired
            if let warranty = item.warrantyUntil, warranty < now {
                score -= 3
            }
        }

        return max(0, score)
    }
}

// MARK: - TwinHealthEngine Extension
//
// Plug pond health into the existing property Twin score
// WITHOUT modifying TwinHealthEngine.swift.
// Add this extension in PondHealthEngine.swift — zero coupling.

extension TwinHealthEngine {
    static func includingPondScore(
        baseScore: Int,
        pondSnapshots: [PondHealthSnapshot]
    ) -> Int {
        guard !pondSnapshots.isEmpty else { return baseScore }

        let avgPondScore = pondSnapshots.reduce(0) { $0 + $1.overallScore } / pondSnapshots.count

        // Pond contributes 10% of overall property health if ponds exist
        let adjusted = Int(Double(baseScore) * 0.90 + Double(avgPondScore) * 0.10)
        return max(0, min(100, adjusted))
    }
}

import SwiftUI

// MARK: - WaterParameterCard
//
// Compact card for a single water parameter.
// Used in the 2-column grid on PondDashboardView and WaterQualityCenter.
// Requires: GlassCard, liquidGlass() from PRVIO Components/GlassCard.swift

struct WaterParameterCard: View {
    let parameter: WaterParameter
    let reading: WaterQualityReading?
    var onTap: (() -> Void)? = nil

    private var value: Double? { reading?.value }
    private var status: ParameterStatus { parameterStatus }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: parameter.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(status.color)
                    Spacer()
                    statusDot
                }

                if let value {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedValue(value))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(parameter.unit)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Text(parameter.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                if let reading {
                    Text(reading.recordedAt.relativeFormatted)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(status.backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(status.borderColor, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
    }

    // MARK: Status Dot

    private var statusDot: some View {
        Circle()
            .fill(status.dotColor)
            .frame(width: 7, height: 7)
            .shadow(color: status.dotColor.opacity(0.6), radius: 3)
    }

    // MARK: Status

    private var parameterStatus: ParameterStatus {
        guard let value else { return .unknown }
        if let critHigh = parameter.criticalHigh, value > critHigh { return .critical }
        if let critLow  = parameter.criticalLow,  value < critLow  { return .critical }
        if let range = parameter.koiHealthyRange {
            if range.contains(value) { return .healthy }
            let span = range.upperBound - range.lowerBound
            let deviation = value < range.lowerBound
                ? range.lowerBound - value
                : value - range.upperBound
            return deviation > span * 0.3 ? .warning : .caution
        }
        return .healthy
    }

    private func formattedValue(_ v: Double) -> String {
        switch parameter {
        case .ph, .dissolvedOxygen, .salinity:
            return String(format: "%.1f", v)
        case .temperature:
            return String(format: "%.1f", v)
        case .ammonia, .nitrite, .phosphate:
            return String(format: "%.2f", v)
        default:
            return String(format: "%.0f", v)
        }
    }
}

// MARK: - ParameterStatus

enum ParameterStatus {
    case healthy, caution, warning, critical, unknown

    var color: Color {
        switch self {
        case .healthy:  return Color(hex: "#34C759")
        case .caution:  return Color(hex: "#FFD60A")
        case .warning:  return Color(hex: "#FF9F0A")
        case .critical: return Color(hex: "#FF3B30")
        case .unknown:  return Color(hex: "#636366")
        }
    }

    var dotColor: Color { color }

    var backgroundFill: Color {
        switch self {
        case .critical: return Color(hex: "#FF3B30").opacity(0.12)
        case .warning:  return Color(hex: "#FF9F0A").opacity(0.08)
        default:        return Color.white.opacity(0.05)
        }
    }

    var borderColor: Color {
        switch self {
        case .critical: return Color(hex: "#FF3B30").opacity(0.3)
        case .warning:  return Color(hex: "#FF9F0A").opacity(0.2)
        default:        return Color.white.opacity(0.08)
        }
    }
}

// MARK: - PondAlertBanner

struct PondAlertBanner: View {
    let alerts: [PondAlert]
    var onDismiss: ((PondAlert) -> Void)? = nil

    var body: some View {
        if let topAlert = alerts.first(where: { !$0.isAcknowledged && $0.isActive }) {
            HStack(spacing: 12) {
                Image(systemName: topAlert.severity.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(topAlert.severity.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(topAlert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(topAlert.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                if let onDismiss {
                    Button {
                        onDismiss(topAlert)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(topAlert.severity.color.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(topAlert.severity.color.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - PondEquipmentRow

struct PondEquipmentRow: View {
    let equipment: PondEquipment
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(equipment.isRunning
                          ? Color(hex: "#34C759").opacity(0.15)
                          : Color.white.opacity(0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: equipment.type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(equipment.isRunning ? Color(hex: "#34C759") : .white.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(equipment.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(equipment.type.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    if let watts = equipment.powerWatts {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.2))
                        Text("\(Int(watts))W")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }

            Spacer()

            if onToggle != nil {
                Toggle("", isOn: .constant(equipment.isRunning))
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#34C759")))
                    .labelsHidden()
                    .onTapGesture { onToggle?() }
            } else {
                Text(equipment.isRunning ? "On" : "Off")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(equipment.isRunning ? Color(hex: "#34C759") : .white.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(equipment.isRunning
                                  ? Color(hex: "#34C759").opacity(0.15)
                                  : Color.white.opacity(0.06))
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - WaterQualityChart (self-contained — no external SensorChart dependency)

import Charts

struct WaterQualityChart: View {
    let readings: [WaterQualityReading]
    let parameter: WaterParameter

    @State private var selectedRange: ChartRange = .week

    enum ChartRange: String, CaseIterable {
        case day   = "24H"
        case week  = "7D"
        case month = "30D"

        var days: Int {
            switch self { case .day: return 1; case .week: return 7; case .month: return 30 }
        }
    }

    private var filteredReadings: [WaterQualityReading] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
        return readings.filter { $0.recordedAt >= cutoff }.sorted { $0.recordedAt < $1.recordedAt }
    }

    private var healthyRange: ClosedRange<Double>? { parameter.koiHealthyRange }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(parameter.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Picker("Range", selection: $selectedRange) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if filteredReadings.isEmpty {
                Text("No readings in this period")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart {
                    // Healthy range band
                    if let range = healthyRange {
                        RectangleMark(
                            xStart: .value("Start", filteredReadings.first!.recordedAt),
                            xEnd: .value("End", filteredReadings.last!.recordedAt),
                            yStart: .value("Low", range.lowerBound),
                            yEnd: .value("High", range.upperBound)
                        )
                        .foregroundStyle(Color(hex: "#34C759").opacity(0.08))
                    }

                    // Reading line
                    ForEach(filteredReadings) { reading in
                        LineMark(
                            x: .value("Time", reading.recordedAt),
                            y: .value(parameter.displayName, reading.value)
                        )
                        .foregroundStyle(Color(hex: parameter.colorHex))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Time", reading.recordedAt),
                            y: .value(parameter.displayName, reading.value)
                        )
                        .foregroundStyle(Color(hex: parameter.colorHex))
                        .symbolSize(20)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: selectedRange == .day ? .hour : .day, count: selectedRange == .day ? 6 : selectedRange == .week ? 1 : 5)) {
                        AxisGridLine(stroke: StrokeStyle(dash: [2, 4]))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine(stroke: StrokeStyle(dash: [2, 4]))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 160)
            }
        }
    }
}

// MARK: - Helpers

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

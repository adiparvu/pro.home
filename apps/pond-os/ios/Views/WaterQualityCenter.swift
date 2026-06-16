import SwiftUI
import Charts

// MARK: - WaterQualityCenter
//
// Full water quality dashboard: all 12 parameters, history charts, alerts.
// Accepts WaterQualityService as init param (testable, no hidden state).

struct WaterQualityCenter: View {
    let pond: Pond
    @ObservedObject var waterQualityService: WaterQualityService

    @State private var selectedParameter: WaterParameter = .ph
    @State private var parameterHistory: [WaterQualityReading] = []
    @State private var isLoadingHistory = false
    @State private var showAddReading = false
    @State private var activeTab: QualityTab = .overview

    enum QualityTab: String, CaseIterable {
        case overview = "Overview"
        case alerts   = "Alerts"
        case history  = "History"
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $activeTab) {
                    ForEach(QualityTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Content
                switch activeTab {
                case .overview: overviewContent
                case .alerts:   alertsContent
                case .history:  historyContent
                }
            }
        }
        .navigationTitle("Water Quality")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddReading = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "#0A84FF"))
                }
            }
        }
        .sheet(isPresented: $showAddReading) {
            AddWaterReadingSheet(pond: pond, parameter: selectedParameter,
                                 service: waterQualityService)
        }
        .onChange(of: selectedParameter) { _, param in
            Task { await loadHistory(for: param) }
        }
        .task {
            await waterQualityService.loadLatest(for: pond.id)
            await loadHistory(for: selectedParameter)
        }
    }

    // MARK: Overview — all parameters in grid

    private var overviewContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Group by criticality
                let criticalParams = WaterParameter.allCases.filter {
                    isCritical(waterQualityService.latestReadings[$0]?.value, param: $0)
                }
                let warningParams = WaterParameter.allCases.filter {
                    !criticalParams.contains($0) &&
                    isWarning(waterQualityService.latestReadings[$0]?.value, param: $0)
                }
                let normalParams = WaterParameter.allCases.filter {
                    !criticalParams.contains($0) && !warningParams.contains($0)
                }

                if !criticalParams.isEmpty {
                    parameterGroup(title: "Critical", params: criticalParams, accent: Color(hex: "#FF3B30"))
                }
                if !warningParams.isEmpty {
                    parameterGroup(title: "Warning", params: warningParams, accent: Color(hex: "#FF9F0A"))
                }
                parameterGroup(title: "Readings", params: normalParams, accent: .white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func parameterGroup(title: String, params: [WaterParameter], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(params, id: \.self) { param in
                    WaterParameterCard(
                        parameter: param,
                        reading: waterQualityService.latestReadings[param]
                    ) {
                        selectedParameter = param
                        activeTab = .history
                    }
                }
            }
        }
    }

    // MARK: Alerts

    private var alertsContent: some View {
        Group {
            let alerts = waterQualityService.activeAlerts
            if alerts.isEmpty {
                emptyAlertsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(alerts) { alert in
                            AlertRow(alert: alert) {
                                Task { try? await waterQualityService.acknowledgeAlert(alert) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var emptyAlertsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(hex: "#34C759").opacity(0.6))
            Text("All parameters nominal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("No water quality alerts for this pond.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: History

    private var historyContent: some View {
        VStack(spacing: 0) {
            // Parameter picker scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WaterParameter.allCases, id: \.self) { param in
                        ParameterChip(
                            parameter: param,
                            isSelected: selectedParameter == param,
                            hasReading: waterQualityService.latestReadings[param] != nil
                        ) {
                            selectedParameter = param
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            ScrollView {
                VStack(spacing: 16) {
                    // Current value card
                    if let reading = waterQualityService.latestReadings[selectedParameter] {
                        GlassCard {
                            HStack(alignment: .bottom, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedParameter.displayName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.5))
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(formattedValue(reading.value, param: selectedParameter))
                                            .font(.system(size: 36, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .contentTransition(.numericText())
                                        Text(selectedParameter.unit)
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    if let range = selectedParameter.koiHealthyRange {
                                        Text("Healthy: \(String(format: "%.1f", range.lowerBound))–\(String(format: "%.1f", range.upperBound)) \(selectedParameter.unit)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    Text(reading.recordedAt.relativeFormatted)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            }
                        }
                    }

                    // Chart
                    GlassCard {
                        if isLoadingHistory {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Spacer()
                            }
                            .frame(height: 160)
                        } else {
                            WaterQualityChart(
                                readings: parameterHistory,
                                parameter: selectedParameter
                            )
                        }
                    }

                    // Reading log
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Recent Readings")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.bottom, 12)

                            ForEach(parameterHistory.reversed().prefix(10)) { reading in
                                ReadingLogRow(reading: reading, parameter: selectedParameter)
                                if reading.id != parameterHistory.first?.id {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                }
                            }

                            if parameterHistory.isEmpty {
                                Text("No readings yet. Tap + to add one.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Helpers

    private func loadHistory(for param: WaterParameter) async {
        isLoadingHistory = true
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        parameterHistory = (try? await waterQualityService.loadHistory(
            pondId: pond.id,
            parameter: param,
            from: start
        )) ?? []
        isLoadingHistory = false
    }

    private func isCritical(_ value: Double?, param: WaterParameter) -> Bool {
        guard let value else { return false }
        if let h = param.criticalHigh, value > h { return true }
        if let l = param.criticalLow,  value < l  { return true }
        return false
    }

    private func isWarning(_ value: Double?, param: WaterParameter) -> Bool {
        guard let value, let range = param.koiHealthyRange else { return false }
        return !range.contains(value)
    }

    private func formattedValue(_ v: Double, param: WaterParameter) -> String {
        switch param {
        case .ph, .dissolvedOxygen, .salinity, .temperature: return String(format: "%.1f", v)
        case .ammonia, .nitrite, .phosphate: return String(format: "%.2f", v)
        default: return String(format: "%.0f", v)
        }
    }
}

// MARK: - Supporting Views

private struct ParameterChip: View {
    let parameter: WaterParameter
    let isSelected: Bool
    let hasReading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: parameter.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(parameter.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if hasReading {
                    Circle()
                        .fill(Color(hex: parameter.colorHex))
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected
                          ? Color(hex: parameter.colorHex).opacity(0.25)
                          : Color.white.opacity(0.07))
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected
                                          ? Color(hex: parameter.colorHex).opacity(0.5)
                                          : Color.clear,
                                          lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

private struct AlertRow: View {
    let alert: PondAlert
    let onAcknowledge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.severity.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(alert.severity.color)
                .frame(width: 36, height: 36)
                .background(alert.severity.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                Text(alert.triggeredAt.relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            if !alert.isAcknowledged {
                Button("OK", action: onAcknowledge)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(alert.severity.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(alert.severity.color.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

private struct ReadingLogRow: View {
    let reading: WaterQualityReading
    let parameter: WaterParameter

    var body: some View {
        HStack {
            Text(reading.recordedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Text(formattedValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(parameter.unit)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 50, alignment: .leading)

            sourceIcon
        }
        .padding(.vertical, 8)
    }

    private var formattedValue: String {
        switch parameter {
        case .ph, .dissolvedOxygen, .temperature: return String(format: "%.1f", reading.value)
        case .ammonia, .nitrite, .phosphate: return String(format: "%.2f", reading.value)
        default: return String(format: "%.0f", reading.value)
        }
    }

    private var sourceIcon: some View {
        Group {
            switch reading.source {
            case .manual:
                Image(systemName: "hand.point.up.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            case .haEntity, .esphome:
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#34C759").opacity(0.7))
            case .predicted:
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#BF5AF2").opacity(0.7))
            }
        }
        .frame(width: 16)
    }
}

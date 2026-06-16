import SwiftUI

// MARK: - AddWaterReadingSheet
//
// Manual water parameter entry.
// Referenced in PondDashboardView and WaterQualityCenter.
// Signature: AddWaterReadingSheet(pond:parameter:service:)

struct AddWaterReadingSheet: View {
    let pond: Pond
    var parameter: WaterParameter? // pre-selected parameter (optional)
    @ObservedObject var service: WaterQualityService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedParameter: WaterParameter
    @State private var valueText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var showValidationError = false

    init(pond: Pond, parameter: WaterParameter? = nil, service: WaterQualityService) {
        self.pond = pond
        self.parameter = parameter
        self.service = service
        _selectedParameter = State(initialValue: parameter ?? .ph)
    }

    private var parsedValue: Double? { Double(valueText) }

    private var isValueValid: Bool {
        guard let v = parsedValue else { return false }
        return v >= 0
    }

    private var statusForValue: ParameterStatus {
        guard let v = parsedValue else { return .unknown }
        let param = selectedParameter
        if let critHigh = param.criticalHigh, v > critHigh { return .critical }
        if let critLow  = param.criticalLow,  v < critLow  { return .critical }
        if let range = param.koiHealthyRange {
            if range.contains(v) { return .healthy }
            let span = range.upperBound - range.lowerBound
            let deviation = v < range.lowerBound ? range.lowerBound - v : v - range.upperBound
            return deviation > span * 0.3 ? .warning : .caution
        }
        return .healthy
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if parameter == nil {
                            parameterPickerSection
                        }

                        valueInputSection

                        if let v = parsedValue {
                            statusFeedback(for: v)
                        }

                        notesSection
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveReading() }
                        .foregroundStyle(isValueValid ? selectedParameter.accentColor : .white.opacity(0.3))
                        .disabled(!isValueValid || isSaving)
                }
            }
            .alert("Invalid value", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid non-negative number.")
            }
        }
    }

    // MARK: Parameter Picker

    private var parameterPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Parameter")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(WaterParameter.allCases, id: \.self) { param in
                    parameterChip(param)
                }
            }
        }
    }

    private func parameterChip(_ param: WaterParameter) -> some View {
        let isSelected = selectedParameter == param
        return Button {
            selectedParameter = param
            valueText = ""
        } label: {
            HStack(spacing: 8) {
                Image(systemName: param.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? param.accentColor : .white.opacity(0.4))
                Text(param.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? param.accentColor.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? param.accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Value Input

    private var valueInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(selectedParameter.displayName)

            HStack(alignment: .center, spacing: 0) {
                TextField(placeholderText, text: $valueText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)

                Text(selectedParameter.unit)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                parsedValue != nil ? selectedParameter.accentColor.opacity(0.3) : Color.white.opacity(0.1),
                                lineWidth: 0.5
                            )
                    )
            )

            if let range = selectedParameter.koiHealthyRange {
                Text("Healthy range: \(formatBound(range.lowerBound))–\(formatBound(range.upperBound)) \(selectedParameter.unit)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private var placeholderText: String {
        switch selectedParameter {
        case .ph:              return "7.4"
        case .temperature:     return "22.0"
        case .dissolvedOxygen: return "8.5"
        case .ammonia:         return "0.00"
        case .nitrite:         return "0.00"
        default:               return "0"
        }
    }

    private func formatBound(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    // MARK: Status Feedback

    private func statusFeedback(for value: Double) -> some View {
        let status = statusForValue
        return HStack(spacing: 10) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .shadow(color: status.color.opacity(0.6), radius: 4)

            Text(statusMessage(status, value: value))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(status.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(status.color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private func statusMessage(_ status: ParameterStatus, value: Double) -> String {
        switch status {
        case .healthy:  return "\(selectedParameter.displayName) is in the healthy range."
        case .caution:  return "\(selectedParameter.displayName) is slightly outside the optimal range."
        case .warning:  return "\(selectedParameter.displayName) is out of range — monitor closely."
        case .critical: return "Critical: \(selectedParameter.displayName) requires immediate attention."
        case .unknown:  return "No reference range available for this parameter."
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Notes (optional)")
            TextField("Observations, conditions, method…", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(3, reservesSpace: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
        }
    }

    // MARK: Save

    private func saveReading() {
        guard let value = parsedValue, value >= 0 else {
            showValidationError = true
            return
        }
        isSaving = true
        Task {
            try? await service.record(
                pondId: pond.id,
                parameter: selectedParameter,
                value: value,
                source: .manual
            )
            dismiss()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
    }
}

// MARK: - WaterParameter accentColor helper

private extension WaterParameter {
    var accentColor: Color { Color(hex: colorHex) }
}

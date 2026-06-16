import SwiftUI

// MARK: - AddPondSheet
//
// 3-step wizard: Type → Details → (optionally) HA Integration.
// On save, creates a Pond via PondService and calls onCreated.

struct AddPondSheet: View {
    let propertyId: String
    @ObservedObject var pondService: PondService
    var onCreated: ((Pond) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var step: WizardStep = .type
    @State private var selectedType: PondType = .koi
    @State private var name = ""
    @State private var volumeText = ""
    @State private var surfaceAreaText = ""
    @State private var maxDepthText = ""
    @State private var haInstanceId = ""
    @State private var notes = ""
    @State private var isSaving = false

    enum WizardStep: Int, CaseIterable {
        case type    = 0
        case details = 1
        case ha      = 2
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {
                    stepIndicator
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            switch step {
                            case .type:    typeStep
                            case .details: detailsStep
                            case .ha:      haStep
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 40)
                    }

                    navigationButtons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("New Pond")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(WizardStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color(hex: "#0A84FF") : Color.white.opacity(0.1))
                    .frame(height: 3)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: Step 1: Type

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What kind of pond?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("Choose the type that best matches your pond. You can change this later.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 10) {
                ForEach(PondType.allCases, id: \.self) { type in
                    typeOptionRow(type)
                }
            }
        }
    }

    private func typeOptionRow(_ type: PondType) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "#0A84FF").opacity(0.2) : Color.white.opacity(0.07))
                        .frame(width: 48, height: 48)
                    Image(systemName: type.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color(hex: "#0A84FF") : .white.opacity(0.4))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(typeDescription(type))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(hex: "#0A84FF") : .white.opacity(0.3))
                    .font(.system(size: 20))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(hex: "#0A84FF").opacity(0.08) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color(hex: "#0A84FF").opacity(0.3) : Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func typeDescription(_ type: PondType) -> String {
        switch type {
        case .koi:         return "Japanese koi kept for viewing pleasure and competition."
        case .ornamental:  return "Decorative pond with mixed fish, plants and water features."
        case .aquaculture: return "Commercial or subsistence fish farming for food production."
        case .natural:     return "Wildlife pond, lake section or natural water body."
        case .swimming:    return "Natural swimming pond with biological filtration zones."
        }
    }

    // MARK: Step 2: Details

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pond details")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            formField("Name *", placeholder: "e.g. Main Koi Pond", text: $name)

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Dimensions (optional)")
                HStack(spacing: 12) {
                    smallField("Volume (L)", text: $volumeText)
                    smallField("Area (m²)", text: $surfaceAreaText)
                    smallField("Max depth (cm)", text: $maxDepthText)
                }
            }

            formField("Notes (optional)", placeholder: "Location, history, special notes…", text: $notes, multiline: true)
        }
    }

    // MARK: Step 3: HA Integration

    private var haStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Home Assistant (optional)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("Connect this pond to a Home Assistant instance to sync sensor data automatically. You can skip this and configure it later.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))

            formField("HA Instance ID", placeholder: "e.g. homeassistant-main", text: $haInstanceId)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color(hex: "#0A84FF").opacity(0.7))
                        .font(.system(size: 13))
                    Text("Sensors connected in HA will automatically push readings to this pond via the ESPHome or MQTT integration.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#0A84FF").opacity(0.06))
            )
        }
    }

    // MARK: Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step.rawValue > 0 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        step = WizardStep(rawValue: step.rawValue - 1) ?? .type
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                if step == .ha {
                    savePond()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        step = WizardStep(rawValue: step.rawValue + 1) ?? .ha
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Text(step == .ha ? "Create Pond" : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canProceed ? Color(hex: "#0A84FF") : Color(hex: "#0A84FF").opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canProceed || isSaving)
        }
    }

    private var canProceed: Bool {
        switch step {
        case .type:    return true
        case .details: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .ha:      return true
        }
    }

    // MARK: Save

    private func savePond() {
        isSaving = true
        let payload = NewPond(
            propertyId: propertyId,
            name: name.trimmingCharacters(in: .whitespaces),
            type: selectedType.rawValue,
            volumeLiters: Double(volumeText),
            surfaceAreaSqm: Double(surfaceAreaText),
            maxDepthCm: Double(maxDepthText),
            haInstanceId: haInstanceId.isEmpty ? nil : haInstanceId,
            notes: notes.isEmpty ? nil : notes
        )
        Task {
            do {
                let created = try await pondService.create(payload)
                onCreated?(created)
                dismiss()
            } catch {
                isSaving = false
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
    }

    private func formField(_ label: String, placeholder: String, text: Binding<String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            Group {
                if multiline {
                    TextField(placeholder, text: text, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(.white)
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

    private func smallField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
            TextField("—", text: text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .frame(maxWidth: .infinity)
    }
}

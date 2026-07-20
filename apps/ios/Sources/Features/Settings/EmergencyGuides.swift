import SwiftUI

// MARK: - Emergency mini-guides
//
// Four static, localized "what do I do if…" checklists: flood, gas leak,
// power outage, fire. Deliberately not AI-generated and not editable — this
// is fixed safety content, written soberly, that must read the same at 2 AM
// with no connectivity. Each guide is 4–5 numbered steps in large type.

enum EmergencyScenario: String, CaseIterable, Identifiable {
    case flood
    case gasLeak
    case powerOutage
    case fire

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flood:       return "drop.fill"
        case .gasLeak:     return "wind"
        case .powerOutage: return "bolt.slash.fill"
        case .fire:        return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .flood:       return Color.brandPrimaryBlue
        case .gasLeak:     return .orange
        case .powerOutage: return Color.brandGold
        case .fire:        return Color.brandDanger
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .flood:       return "emg_guide_flood_title"
        case .gasLeak:     return "emg_guide_gas_title"
        case .powerOutage: return "emg_guide_power_title"
        case .fire:        return "emg_guide_fire_title"
        }
    }

    var steps: [LocalizedStringKey] {
        switch self {
        case .flood:
            return ["emg_guide_flood_step1", "emg_guide_flood_step2", "emg_guide_flood_step3",
                    "emg_guide_flood_step4", "emg_guide_flood_step5"]
        case .gasLeak:
            return ["emg_guide_gas_step1", "emg_guide_gas_step2", "emg_guide_gas_step3",
                    "emg_guide_gas_step4", "emg_guide_gas_step5"]
        case .powerOutage:
            return ["emg_guide_power_step1", "emg_guide_power_step2", "emg_guide_power_step3",
                    "emg_guide_power_step4"]
        case .fire:
            return ["emg_guide_fire_step1", "emg_guide_fire_step2", "emg_guide_fire_step3",
                    "emg_guide_fire_step4", "emg_guide_fire_step5"]
        }
    }
}

// MARK: - Guide sheet

struct EmergencyGuideSheet: View {
    let scenario: EmergencyScenario
    /// Flood only: the household's "main water valve" critical place, if one
    /// exists — step 1 links straight to it (with its photo when available).
    var valvePlace: EmergencyNote? = nil
    var valveImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showValvePhoto = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    header
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        ForEach(Array(scenario.steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, text: step)
                            if scenario == .flood, index == 0, valvePlace != nil {
                                valveCard
                            }
                        }
                    }
                    Text("emg_guide_disclaimer")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, AppSpacing.sm)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.scaled(24))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .fullScreenCover(isPresented: $showValvePhoto) {
            if let valvePlace, let valveImage {
                EmergencyPhotoViewer(title: valvePlace.title, image: valveImage)
            }
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.base) {
            Image(systemName: scenario.icon)
                .font(AppFont.scaled(30, weight: .bold))
                .foregroundStyle(scenario.color)
                .frame(width: 56, height: 56)
                .background(scenario.color.opacity(AppOpacity.tintedFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            Text(scenario.titleKey)
                .font(AppFont.title2)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func stepRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.base) {
            Text("\(number)")
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(scenario.color)
                .frame(width: 40, height: 40)
                .background(scenario.color.opacity(AppOpacity.tintedFill), in: Circle())
            Text(text)
                .font(AppFont.scaled(18, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.xs)
        }
        .accessibilityElement(children: .combine)
    }

    /// The "main water valve" critical place inlined under step 1: photo
    /// thumbnail + where it is. Tapping opens the photo fullscreen when one
    /// exists; without a photo the card is informative only.
    private var valveCard: some View {
        Button {
            if valveImage != nil {
                showValvePhoto = true
                HapticFeedback.impact(.medium)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                if let valveImage {
                    Image(uiImage: valveImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                } else {
                    ColoredIconBadge(icon: "mappin.and.ellipse", color: .orange, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(valvePlace?.title ?? "")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    if let detail = valvePlace?.detail, !detail.isEmpty {
                        Text(detail)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if valveImage != nil {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .padding(.leading, 40 + AppSpacing.base)
        .accessibilityLabel(Text("emg_guide_flood_valve_link"))
    }
}

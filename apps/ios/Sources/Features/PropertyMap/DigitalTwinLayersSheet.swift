import SwiftUI

// MARK: - Digital Twin layers (Faza 3 — "straturi live")
//
// The map is one photo with optional information layers on top: buried
// utilities, open-task badges, health tinting per zone and journal photos
// anchored to their zones. This sheet toggles them; the picks persist in
// UserDefaults so the twin reopens exactly as the user left it.

struct TwinLayersSheet: View {
    @Binding var utilities: Bool
    @Binding var tasks: Bool
    @Binding var health: Bool
    @Binding var journal: Bool
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    /// The glass row shape (the smart-home tile treatment).
    private static let rowShape =
        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Layers")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(Color.smartTextPrimary)
                    Spacer()
                    Button {
                        HapticFeedback.impact(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.smartTextPrimary)
                            .frame(width: 30, height: 30)
                            .background(Color.smartGlassFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(spacing: 10) {
                    layerRow(isOn: $utilities, icon: "pipe.and.drop.fill", color: .blue,
                             title: "Buried utilities",
                             subtitle: "Underground zones outlined on the same photo")
                    layerRow(isOn: $tasks, icon: "exclamationmark.circle.fill", color: .red,
                             title: "Open tasks",
                             subtitle: "Pulsing badge on elements with work to do")
                    layerRow(isOn: $health, icon: "heart.fill", color: Color.brandSuccess,
                             title: "Health tint",
                             subtitle: "Zones colored by the health of what's inside")
                    layerRow(isOn: $journal, icon: "photo.stack.fill", color: .orange,
                             title: "Journal photos",
                             subtitle: "Photo counts anchored to their zones")
                }
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.xl)
            .environment(\.colorScheme, .dark)
        }
    }

    private func layerRow(isOn: Binding<Bool>, icon: String, color: Color,
                          title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.subheadline).foregroundStyle(Color.smartTextPrimary)
                Text(subtitle).font(AppFont.scaled(12)).foregroundStyle(Color.smartTextSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(color)
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background {
            Self.rowShape.fill(.ultraThinMaterial)
            Self.rowShape.fill(Color.smartGlassFill)
        }
        .clipShape(Self.rowShape)
        .overlay(Self.rowShape.strokeBorder(SmartHomeTheme.glassStrokeGradient, lineWidth: 1))
        .contentShape(Rectangle())
        // Tapping anywhere on the row flips the layer; the switch itself
        // keeps its own gesture so the two never double-toggle.
        .onTapGesture {
            HapticFeedback.selection()
            withAnimation(.snappy) { isOn.wrappedValue.toggle() }
        }
    }
}

// MARK: - Legend (discreet, bottom-leading, only for active layers)

struct TwinLayersLegend: View {
    let utilities: Bool
    let tasks: Bool
    let health: Bool
    let journal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if utilities { legendRow(color: .blue, dashed: true, label: "Utilities") }
            if tasks { legendRow(color: .red, dashed: false, label: "Open tasks") }
            if health {
                HStack(spacing: 4) {
                    ForEach([Color.brandSuccess, .orange, .red], id: \.self) { c in
                        Circle().fill(c).frame(width: 7, height: 7)
                    }
                    Text("Health").font(AppFont.scaled(10, weight: .semibold)).foregroundStyle(Color.smartTextPrimary)
                }
            }
            if journal { legendRow(color: .orange, dashed: false, label: "Journal", icon: "photo.fill") }
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.smartGlassFill)
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(SmartHomeTheme.glassStrokeGradient, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .allowsHitTesting(false)
    }

    private func legendRow(color: Color, dashed: Bool, label: LocalizedStringKey, icon: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(AppFont.scaled(8, weight: .bold)).foregroundStyle(color)
            } else if dashed {
                Rectangle().fill(color).frame(width: 12, height: 2)
                    .mask(HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Rectangle().frame(width: 3) } })
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label).font(AppFont.scaled(10, weight: .semibold)).foregroundStyle(Color.smartTextPrimary)
        }
    }
}

// MARK: - Journal badge model (zone-anchored photo counts)

struct TwinJournalBadge: Identifiable, Equatable {
    let id: UUID          // zone id
    let point: CGPoint    // normalized centroid
    let count: Int
}

// MARK: - Pulsing task badge (respects Reduce Motion)

struct PulsingBadge: View {
    let color: Color
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .scaleEffect(expanded ? 1.5 : 0.7)
                    .opacity(expanded ? 0 : 0.9)
            }
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1.5))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
    }
}

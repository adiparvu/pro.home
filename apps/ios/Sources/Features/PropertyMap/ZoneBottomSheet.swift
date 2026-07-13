// Unreferenced since tab 2 became Spațiile casei (user decision) — safe to delete in a cleanup pass.
import SwiftUI

/// The zone inspector shown when a zone is tapped on the Digital Twin map.
/// Wears the smart-home warm glass skin: blurred cover-photo backdrop,
/// glass tiles with the shared hairline, warm-white text and the single
/// amber accent — semantic colors (health, success, destructive, the
/// zone's own tint) stay untouched.
struct ZoneBottomSheet: View {
    let zone: PropertyZone
    var onEdit: () -> Void
    var onReshape: () -> Void
    var onAddObject: () -> Void
    var onDelete: () -> Void
    var onFocus: () -> Void

    @Environment(PropertyElementService.self) private var elementService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(DocumentService.self) private var documentService
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @State private var selectedObject: PropertyElement?

    /// The glass tile shape shared by stats, actions and object rows.
    private static let tileShape =
        RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius, style: .continuous)

    private var objects: [PropertyElement] { elementService.elements(inZone: zone.id) }

    private var zoneHealth: Int {
        guard !objects.isEmpty else { return zone.healthScore }
        return objects.reduce(0) { $0 + $1.healthScore } / objects.count
    }

    private var totalValue: Double {
        objects.compactMap { $0.estimatedValue }.reduce(0, +)
    }

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statsRow
                    actionRow

                    if !objects.isEmpty {
                        Text("OBJECTS IN ZONE")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.smartTextSecondary)
                            .padding(.top, 2)
                        VStack(spacing: 8) {
                            ForEach(objects) { obj in
                                ObjectRow(element: obj) { selectedObject = obj }
                            }
                        }
                    } else {
                        emptyObjects
                    }
                }
                .padding(AppSpacing.xl)
            }
            .environment(\.colorScheme, .dark)
        }
        .sheet(item: $selectedObject) { obj in
            PropertyElementDetailView(element: obj)
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
                .environment(documentService)
                .environment(taskService)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: zone.icon)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(zone.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name)
                    .font(AppFont.scaled(20, weight: .bold))
                    .foregroundStyle(Color.smartTextPrimary)
                HStack(spacing: 6) {
                    Image(systemName: zone.layer.icon).font(AppFont.scaled(11))
                    Text(zone.layer.displayName).font(AppFont.caption)
                }
                .foregroundStyle(Color.smartTextSecondary)
            }
            Spacer()
            healthRing
        }
    }

    private var healthRing: some View {
        ZStack {
            Circle().stroke(Color.smartGlassFill, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(zoneHealth) / 100)
                .stroke(healthColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(zoneHealth)")
                .font(AppFont.scaled(15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.smartTextPrimary)
        }
        .frame(width: 48, height: 48)
    }

    private var healthColor: Color {
        switch zoneHealth {
        case 80...:   return Color.brandSuccess
        case 50..<80: return .orange
        default:      return .red
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(value: "\(objects.count)", label: "Objects", icon: "cube.box.fill", color: Color.smartAmber)
            statTile(value: "\(zoneHealth)%", label: "Health", icon: "heart.fill", color: healthColor)
            statTile(value: valueString, label: "Value", icon: "eurosign.circle.fill", color: Color.brandSuccess)
        }
    }

    private var valueString: String {
        CurrencyService.money(totalValue, code: appSettings.preferredCurrency, whole: true)
    }

    private func statTile(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(AppFont.footnoteEmphasis).foregroundStyle(color)
            Text(value).font(AppFont.scaled(16, weight: .bold, design: .rounded)).foregroundStyle(Color.smartTextPrimary)
            Text(label).font(AppFont.scaled(11)).foregroundStyle(Color.smartTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background {
            Self.tileShape.fill(.ultraThinMaterial)
            Self.tileShape.fill(Color.smartGlassFill)
        }
        .clipShape(Self.tileShape)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            actionButton("Edit", icon: "slider.horizontal.3", tint: Color.smartAmber, action: onEdit)
            actionButton("Reshape", icon: "pencil.and.outline", tint: Color.smartAmber, action: onReshape)
            actionButton("Add object", icon: "plus", tint: Color.brandSuccess, action: onAddObject)
            actionButton("Delete", icon: "trash", tint: .red, action: onDelete)
        }
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(AppFont.subheadline)
                Text(title).font(AppFont.label)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(tint.opacity(AppOpacity.tintedFill), in: Self.tileShape)
        }
        .buttonStyle(.plain)
    }

    private var emptyObjects: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(AppFont.scaled(30))
                .foregroundStyle(Color.smartTextSecondary)
            Text("No objects in this zone")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.smartTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }
}

// MARK: - Object row

private struct ObjectRow: View {
    let element: PropertyElement
    let onTap: () -> Void

    private static let shape =
        RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius, style: .continuous)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: element.elementType.icon)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(element.elementType.accentColor)
                    .frame(width: 38, height: 38)
                    .background(element.elementType.accentColor.opacity(AppOpacity.tintedFill),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.name).font(AppFont.body).foregroundStyle(Color.smartTextPrimary)
                    Text(element.elementType.displayName).font(AppFont.scaled(12)).foregroundStyle(Color.smartTextSecondary)
                }
                Spacer()
                Text("\(element.healthScore)")
                    .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                    .foregroundStyle(element.healthColor)
                Image(systemName: "chevron.right")
                    .font(AppFont.label)
                    .foregroundStyle(Color.smartTextSecondary)
            }
            .padding(.horizontal, AppSpacing.md).padding(.vertical, 10)
            .background {
                Self.shape.fill(.ultraThinMaterial)
                Self.shape.fill(Color.smartGlassFill)
            }
            .clipShape(Self.shape)
        }
        .buttonStyle(.plain)
    }
}

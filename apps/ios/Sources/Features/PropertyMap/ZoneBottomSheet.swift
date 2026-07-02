import SwiftUI

/// Apple-style Liquid Glass bottom sheet shown when a zone is tapped on the
/// Digital Twin map. Presented with `.presentationBackground(.thinMaterial)`.
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
    @State private var selectedObject: PropertyElement?

    private var objects: [PropertyElement] { elementService.elements(inZone: zone.id) }

    private var zoneHealth: Int {
        guard !objects.isEmpty else { return zone.healthScore }
        return objects.reduce(0) { $0 + $1.healthScore } / objects.count
    }

    private var totalValue: Double {
        objects.compactMap { $0.estimatedValue }.reduce(0, +)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsRow
                actionRow

                if !objects.isEmpty {
                    Text("OBJECTS IN ZONE")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(zone.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Image(systemName: zone.layer.icon).font(.system(size: 11))
                    Text(zone.layer.displayName).font(AppFont.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            healthRing
        }
    }

    private var healthRing: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(zoneHealth) / 100)
                .stroke(healthColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(zoneHealth)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
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
            statTile(value: "\(objects.count)", label: "Objects", icon: "cube.box.fill", color: .blue)
            statTile(value: "\(zoneHealth)%", label: "Health", icon: "heart.fill", color: healthColor)
            statTile(value: valueString, label: "Value", icon: "eurosign.circle.fill", color: .green)
        }
    }

    private var valueString: String {
        let sym = currencyService.symbol(for: appSettings.preferredCurrency)
        return "\(sym)\(Int(totalValue))"
    }

    private func statTile(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(AppFont.footnoteEmphasis).foregroundStyle(color)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.primary)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            actionButton("Edit", icon: "slider.horizontal.3", tint: .blue, action: onEdit)
            actionButton("Reshape", icon: "pencil.and.outline", tint: .indigo, action: onReshape)
            actionButton("Add object", icon: "plus", tint: .green, action: onAddObject)
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
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyObjects: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 30))
                .foregroundStyle(Color.primary.opacity(0.25))
            Text("No objects in this zone")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }
}

// MARK: - Object row

private struct ObjectRow: View {
    let element: PropertyElement
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: element.elementType.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(element.elementType.accentColor)
                    .frame(width: 38, height: 38)
                    .background(element.elementType.accentColor.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.name).font(AppFont.body).foregroundStyle(.primary)
                    Text(element.elementType.displayName).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(element.healthScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(element.healthColor)
                Image(systemName: "chevron.right")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .padding(.horizontal, AppSpacing.md).padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

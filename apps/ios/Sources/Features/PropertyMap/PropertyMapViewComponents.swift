import SwiftUI

extension PropertyMapView {

    // MARK: - Health badge

    var healthScoreBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(AppFont.label)
            Text("\(elementService.overallHealthScore)")
                .font(AppFont.scaled(13, weight: .bold))
        }
        .foregroundStyle(healthColor(elementService.overallHealthScore))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(healthColor(elementService.overallHealthScore).opacity(0.15)))
        .overlay(Capsule().strokeBorder(healthColor(elementService.overallHealthScore).opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Layer filter

    var layerFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                GlassFilterChip(
                    label: String(localized: "All"),
                    systemImage: "square.grid.2x2",
                    count: elementService.elements.count,
                    isSelected: selectedLayer == nil
                ) {
                    withAnimation(.spring(response: 0.25)) { selectedLayer = nil }
                }
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    GlassFilterChip(
                        label: layer.displayName,
                        systemImage: layer.icon,
                        count: elementService.elements(for: layer).count,
                        isSelected: selectedLayer == layer
                    ) {
                        withAnimation(.spring(response: 0.25)) {
                            selectedLayer = selectedLayer == layer ? nil : layer
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats strip

    var statsStrip: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(
                icon: "square.grid.2x2.fill",
                label: "Elements",
                value: "\(elementService.elements.count)",
                sub: "on map",
                color: .blue
            )
            statTile(
                icon: "heart.fill",
                label: "Health",
                value: "\(elementService.overallHealthScore)%",
                sub: LocalizedStringKey(healthLabel(elementService.overallHealthScore)),
                color: healthColor(elementService.overallHealthScore)
            )
            statTile(
                icon: "banknote.fill",
                label: "Value",
                value: formattedTotal,
                sub: "estimated",
                color: Color.brandSuccess
            )
            statTile(
                icon: "exclamationmark.triangle.fill",
                label: "Attention",
                value: "\(elementService.elementsNeedingAttention.count)",
                sub: "needs inspection",
                color: elementService.elementsNeedingAttention.isEmpty ? .secondary : .orange
            )
        }
    }

    private func statTile(icon: String, label: LocalizedStringKey, value: String, sub: LocalizedStringKey, color: Color) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(color)
                    Text(label)
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(AppFont.scaled(22, weight: .bold))
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Attention section

    var attentionSection: some View {
        SettingsGroup(title: "Needs attention") {
            ForEach(Array(elementService.criticalElements.prefix(4).enumerated()), id: \.element.id) { idx, element in
                if idx > 0 {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                }
                elementRow(element)
            }
        }
    }

    // MARK: - Element list

    var elementListSection: some View {
        let filtered = elementService.elements(for: selectedLayer)
        return SettingsGroup(title: "All elements") {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, element in
                if idx > 0 {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                }
                elementRow(element)
            }
        }
    }

    private func elementRow(_ element: PropertyElement) -> some View {
        Button {
            HapticFeedback.selection()
            selectedElement = element
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(element.elementType.accentColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: element.elementType.icon)
                        .font(AppFont.headline)
                        .foregroundStyle(element.elementType.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(element.name)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text(element.layer.displayName)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                healthPill(element.healthScore)

                Image(systemName: "chevron.right")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func healthPill(_ score: Int) -> some View {
        Text("\(score)%")
            .font(AppFont.scaled(11, weight: .bold))
            .foregroundStyle(healthColor(score))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(healthColor(score).opacity(0.12), in: Capsule())
    }

    // MARK: - Empty CTA card

    var emptyActionCard: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "map.fill")
                        .font(AppFont.scaled(28))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(spacing: 6) {
                    Text("Start your property map")
                        .font(AppFont.scaled(16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Add rooms, appliances, systems and track their condition")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    HapticFeedback.impact()
                    isEditMode = true
                    addPosition = CGPoint(x: 0.5, y: 0.45)
                    showAddElement = true
                } label: {
                    Text("Add first element")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.xxl)
                        .padding(.vertical, 11)
                        .background(.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Loading state

    var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.primary.opacity(0.6))
            Text("Loading map...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - FAB

    var fabButton: some View {
        Button {
            HapticFeedback.impact()
            if !isEditMode {
                withAnimation(.spring(response: 0.3)) { isEditMode = true }
            }
            addPosition = CGPoint(x: 0.5, y: 0.45)
            showAddElement = true
        } label: {
            Image(systemName: "plus")
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
        }
        .glassCircle()
        .shadow(color: Color.primary.opacity(0.15), radius: 16, y: 4)
    }

    // MARK: - Helpers

    private var formattedTotal: String {
        let total = elementService.totalEstimatedValue()
        if total == 0 { return "—" }
        let preferred = appSettings.preferredCurrency
        return currencyService.formatted(total, from: preferred, preferred: preferred)
    }

    private func healthColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return Color.brandSuccess
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return .orange
        case 25..<50:  return Color.brandWarning
        default:       return .red
        }
    }

    private func healthLabel(_ score: Int) -> String {
        switch score {
        case 90...100: return "excellent"
        case 70..<90:  return "good"
        case 50..<70:  return "satisfactory"
        case 25..<50:  return "poor"
        default:       return "critical"
        }
    }
}


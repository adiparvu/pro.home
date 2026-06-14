import SwiftUI

struct PropertyMapView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings

    @State private var selectedLayer: PropertyLayer? = nil
    @State private var selectedElement: PropertyElement? = nil
    @State private var showAddElement = false
    @State private var isEditMode = false
    @State private var showHealthDashboard = false
    @State private var addPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                layerFilterBar
                    .padding(.horizontal, 20)

                if elementService.isLoading && elementService.elements.isEmpty {
                    loadingState
                } else {
                    PropertyMapCanvas(
                        elements: elementService.elements(for: selectedLayer),
                        isEditMode: isEditMode,
                        onTap: { element in
                            HapticFeedback.selection()
                            selectedElement = element
                        },
                        onLongPress: { position in
                            guard isEditMode else { return }
                            HapticFeedback.impact()
                            addPosition = position
                            showAddElement = true
                        },
                        onMove: { element, newX, newY in
                            Task { await elementService.updatePosition(elementId: element.id, x: newX, y: newY) }
                        }
                    )
                    .padding(.horizontal, 16)
                }

                statsStrip
                    .padding(.horizontal, 20)

                if !elementService.criticalElements.isEmpty {
                    attentionSection
                        .padding(.horizontal, 20)
                }

                if elementService.elements.isEmpty {
                    emptyActionCard
                        .padding(.horizontal, 20)
                } else {
                    elementListSection
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 110)
            }
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Harta Proprietății")
                        .font(.title2.weight(.bold))
                    Text("\(elementService.elements.count) elemente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    Button {
                        HapticFeedback.selection()
                        showHealthDashboard = true
                    } label: {
                        healthScoreBadge
                    }

                    Button {
                        HapticFeedback.selection()
                        withAnimation(.spring(response: 0.3)) { isEditMode.toggle() }
                    } label: {
                        Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isEditMode ? Color(red: 0.2, green: 0.8, blue: 0.4) : Color.secondary)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            fabButton
                .padding(.trailing, 24)
                .padding(.bottom, 100)
        }
        .sheet(item: $selectedElement) { element in
            PropertyElementDetailView(element: element)
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showAddElement) {
            AddPropertyElementView(defaultPosition: addPosition) { payload in
                Task { await elementService.add(payload) }
            }
            .environmentObject(propertyService)
        }
        .sheet(isPresented: $showHealthDashboard) {
            PropertyHealthDashboardView()
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
        }
        .task {
            guard let pid = propertyService.primary?.id else { return }
            await elementService.load(propertyId: pid)
        }
        .refreshable {
            guard let pid = propertyService.primary?.id else { return }
            await elementService.load(propertyId: pid)
        }
    }

    // MARK: - Health badge

    private var healthScoreBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("\(elementService.overallHealthScore)")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(healthColor(elementService.overallHealthScore))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(healthColor(elementService.overallHealthScore).opacity(0.15)))
        .overlay(Capsule().strokeBorder(healthColor(elementService.overallHealthScore).opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Layer filter

    private var layerFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LayerChip(
                    label: "Toate",
                    icon: "square.grid.2x2",
                    count: elementService.elements.count,
                    isSelected: selectedLayer == nil
                ) {
                    withAnimation(.spring(response: 0.25)) { selectedLayer = nil }
                }
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    LayerChip(
                        label: layer.displayName,
                        icon: layer.icon,
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

    private var statsStrip: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(
                icon: "square.grid.2x2.fill",
                label: "Elemente",
                value: "\(elementService.elements.count)",
                sub: "pe hartă",
                color: .blue
            )
            statTile(
                icon: "heart.fill",
                label: "Sănătate",
                value: "\(elementService.overallHealthScore)%",
                sub: healthLabel(elementService.overallHealthScore),
                color: healthColor(elementService.overallHealthScore)
            )
            statTile(
                icon: "banknote.fill",
                label: "Valoare",
                value: formattedTotal,
                sub: "estimată",
                color: Color(red: 0.3, green: 0.82, blue: 0.45)
            )
            statTile(
                icon: "exclamationmark.triangle.fill",
                label: "Atenție",
                value: "\(elementService.elementsNeedingAttention.count)",
                sub: "necesită inspecție",
                color: elementService.elementsNeedingAttention.isEmpty ? .secondary : .orange
            )
        }
    }

    private func statTile(icon: String, label: String, value: String, sub: String, color: Color) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Attention section

    private var attentionSection: some View {
        SettingsGroup(title: "Necesită atenție") {
            ForEach(Array(elementService.criticalElements.prefix(4).enumerated()), id: \.element.id) { idx, element in
                if idx > 0 {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                }
                elementRow(element)
            }
        }
    }

    // MARK: - Element list

    private var elementListSection: some View {
        let filtered = elementService.elements(for: selectedLayer)
        return SettingsGroup(title: "Toate elementele") {
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(element.elementType.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(element.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(element.layer.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                healthPill(element.healthScore)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func healthPill(_ score: Int) -> some View {
        Text("\(score)%")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(healthColor(score))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(healthColor(score).opacity(0.12), in: Capsule())
    }

    // MARK: - Empty CTA card

    private var emptyActionCard: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "map.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(spacing: 6) {
                    Text("Începe harta proprietății")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Adaugă camere, aparate, instalații și urmărește starea lor")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    HapticFeedback.impact()
                    isEditMode = true
                    addPosition = CGPoint(x: 0.5, y: 0.45)
                    showAddElement = true
                } label: {
                    Text("Adaugă primul element")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.primary.opacity(0.6))
            Text("Se încarcă harta...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            HapticFeedback.impact()
            if !isEditMode {
                withAnimation(.spring(response: 0.3)) { isEditMode = true }
            }
            addPosition = CGPoint(x: 0.5, y: 0.45)
            showAddElement = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.29, green: 0.56, blue: 0.89), Color(red: 0.18, green: 0.38, blue: 0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .shadow(color: Color(red: 0.29, green: 0.56, blue: 0.89).opacity(0.4), radius: 10, y: 4)
        }
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
        case 90...100: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return .orange
        case 25..<50:  return Color(red: 1.0, green: 0.45, blue: 0.1)
        default:       return .red
        }
    }

    private func healthLabel(_ score: Int) -> String {
        switch score {
        case 90...100: return "excelentă"
        case 70..<90:  return "bună"
        case 50..<70:  return "satisfăcătoare"
        case 25..<50:  return "slabă"
        default:       return "critică"
        }
    }
}

// MARK: - LayerChip

private struct LayerChip: View {
    let label: String
    let icon: String
    var count: Int = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.1), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Color(red: 0.29, green: 0.56, blue: 0.89) : Color.primary.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

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
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                layerFilterBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

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

                Spacer(minLength: 110)
            }

            // FAB
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    fabMenu
                        .padding(.trailing, 24)
                        .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("")
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

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Harta Proprietății")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(elementService.elements.count) elemente")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

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
        .background(
            Capsule().fill(healthColor(elementService.overallHealthScore).opacity(0.15))
        )
        .overlay(Capsule().strokeBorder(healthColor(elementService.overallHealthScore).opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Layer filter

    private var layerFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LayerChip(label: "Toate", icon: "square.grid.2x2", isSelected: selectedLayer == nil) {
                    withAnimation(.spring(response: 0.25)) { selectedLayer = nil }
                }
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    LayerChip(
                        label: layer.displayName,
                        icon: layer.icon,
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

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.primary.opacity(0.6))
            Text("Se încarcă harta...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FAB

    private var fabMenu: some View {
        VStack(spacing: 10) {
            if isEditMode {
                Button {
                    HapticFeedback.impact()
                    addPosition = CGPoint(x: 0.5, y: 0.45)
                    showAddElement = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
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
        }
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
}

// MARK: - LayerChip

private struct LayerChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Color(red: 0.29, green: 0.56, blue: 0.89) : Color.primary.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? .clear : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct PropertyMapView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyElementService.self) var elementService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings

    @State private var showHealthDashboard = false
    @State var selectedLayer: PropertyLayer? = nil
    @State var selectedElement: PropertyElement? = nil
    @State var showAddElement = false
    @State var isEditMode = false
    @State var addPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                titleKey: "Map",
                subtitleKey: "PROPERTY",
                trailing: {
                    HStack(spacing: 10) {
                        Button {
                            HapticFeedback.selection()
                            showHealthDashboard = true
                        } label: {
                            healthScoreBadge
                        }
                        .buttonStyle(.plain)

                        Button {
                            HapticFeedback.selection()
                            withAnimation(.spring(response: 0.3)) { isEditMode.toggle() }
                        } label: {
                            Image(systemName: isEditMode ? "checkmark" : "pencil")
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(isEditMode ? Color.green : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassRoundedRect(12)
                    }
                }
            )

            layerFilterBar
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
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
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    statsStrip
                        .padding(.horizontal, AppSpacing.xl)

                    if !elementService.criticalElements.isEmpty {
                        attentionSection
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    if elementService.elements.isEmpty {
                        emptyActionCard
                            .padding(.horizontal, AppSpacing.xl)
                    } else {
                        elementListSection
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    Spacer(minLength: 110)
                }
                .padding(.top, AppSpacing.sm)
            }
            .refreshable {
                guard let pid = propertyService.primary?.id else { return }
                await elementService.load(propertyId: pid)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            fabButton
                .padding(.trailing, AppSpacing.xxl)
                .padding(.bottom, 100)
        }
        .sheet(item: $selectedElement) { element in
            PropertyElementDetailView(element: element)
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
        }
        .sheet(isPresented: $showAddElement) {
            AddPropertyElementView(defaultPosition: addPosition) { payload in
                Task { await elementService.add(payload) }
            }
            .environment(propertyService)
        }
        .sheet(isPresented: $showHealthDashboard) {
            PropertyHealthDashboardView()
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
        }
        .task {
            guard let pid = propertyService.primary?.id else { return }
            await elementService.load(propertyId: pid)
        }
    }
}

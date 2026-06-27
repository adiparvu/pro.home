import SwiftUI

// MARK: - Digital Twin (static aerial photo + element pins)
//
// The Digital Twin is the property's aerial photo. There is no map.
// The user taps the "+" pin button, then taps the photo to drop an element
// exactly where they want it. Pins can be dragged to reposition, and tapped
// to open the element detail.

struct DigitalTwinView: View {
    @EnvironmentObject var propertyService: PropertyService
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject var zoneService: PropertyZoneService
    @EnvironmentObject var currencyService: CurrencyService
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var taskService: TaskService

    @State private var selectedElement: PropertyElement?
    @State private var pinMode = false
    @State private var pendingPin: CGPoint?
    @State private var showInsights = false
    @State private var showHealth = false
    @State private var controlsExpanded = false
    @State private var showNames = true
    @State private var sectionFilter: Int? = nil
    @State private var editElementId: UUID?
    @State private var deleteElement: PropertyElement?
    @State private var categoryFilter: ElementCategory? = nil
    @State private var zoneDrawMode = false
    @State private var draftZonePoints: [CGPoint] = []
    @State private var editZone: PropertyZone?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let prop = propertyService.primary {
                AerialCanvasView(
                    property: prop,
                    elements: elementService.elements,
                    zones: zoneService.zones,
                    interactive: true,
                    pinMode: pinMode,
                    zoneDrawMode: zoneDrawMode,
                    draftZonePoints: draftZonePoints,
                    showNames: showNames,
                    sectionFilter: sectionFilter,
                    categoryFilter: categoryFilter,
                    onElementTap: { selectedElement = $0 },
                    onCanvasTap: { pos in
                        pendingPin = pos
                        pinMode = false
                    },
                    onElementMove: { el, pos in
                        Task { await elementService.updatePosition(elementId: el.id, x: pos.x, y: pos.y) }
                    },
                    onElementEdit: { editElementId = $0.id },
                    onElementDelete: { deleteElement = $0 },
                    onElementFavorite: { el in
                        Task { await elementService.toggleFavorite(elementId: el.id) }
                        HapticFeedback.selection()
                    },
                    onZoneTap: { editZone = $0 },
                    onAddZonePoint: { draftZonePoints.append($0) }
                )
                .ignoresSafeArea(edges: .bottom)

                sectionBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if zoneDrawMode {
                    zoneDrawToolbar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Digital Twin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { editElementId != nil },
            set: { if !$0 { editElementId = nil } }
        )) {
            if let id = editElementId,
               let idx = elementService.elements.firstIndex(where: { $0.id == id }) {
                EditPropertyElementView(element: $elementService.elements[idx]) {
                    Task { await elementService.update(elementService.elements[idx]) }
                }
                .environmentObject(propertyService)
            }
        }
        .confirmationDialog(
            "Delete this element?",
            isPresented: Binding(get: { deleteElement != nil }, set: { if !$0 { deleteElement = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let el = deleteElement {
                    Task { await elementService.delete(el) }
                }
                deleteElement = nil
            }
            Button("Cancel", role: .cancel) { deleteElement = nil }
        }
        .sheet(item: $selectedElement) { element in
            PropertyElementDetailView(element: element)
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
                .environmentObject(documentService)
                .environmentObject(taskService)
        }
        .sheet(isPresented: Binding(
            get: { pendingPin != nil },
            set: { if !$0 { pendingPin = nil } }
        )) {
            AddPropertyElementView(defaultPosition: pendingPin ?? CGPoint(x: 0.5, y: 0.5)) { payload in
                Task { await elementService.add(payload) }
            }
            .environmentObject(propertyService)
        }
        .sheet(isPresented: $showInsights) {
            TwinInsightsSheet()
                .environmentObject(propertyService)
                .environmentObject(zoneService)
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showHealth) {
            PropertyHealthDashboardView()
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
        }
        .sheet(item: $editZone) { zone in
            ZoneEditSheet(
                zone: zone,
                onSave: { updated in Task { await zoneService.update(updated) } },
                onDelete: { Task { await zoneService.delete(zone) } }
            )
        }
        .task { await loadData() }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            controlButton(icon: controlsExpanded ? "xmark" : "ellipsis", tint: .white) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { controlsExpanded.toggle() }
                HapticFeedback.impact(.medium)
            }

            if controlsExpanded {
                controlButton(
                    icon: pinMode ? "xmark.circle.fill" : "mappin.and.ellipse",
                    tint: pinMode ? .red : .white,
                    label: pinMode ? "Cancel" : "Add"
                ) {
                    withAnimation(.spring(response: 0.3)) { pinMode.toggle() }
                    HapticFeedback.impact(.medium)
                }
                controlButton(
                    icon: showNames ? "textformat.size" : "textformat.size.smaller",
                    tint: showNames ? .white : Color.accentColor,
                    label: showNames ? "Names" : "Hidden"
                ) {
                    withAnimation(.spring(response: 0.3)) { showNames.toggle() }
                    HapticFeedback.selection()
                }
                categoryMenu
                controlButton(icon: "pentagon", tint: zoneDrawMode ? Color.accentColor : .white, label: "Zone") {
                    withAnimation(.spring(response: 0.3)) {
                        zoneDrawMode = true
                        controlsExpanded = false
                        draftZonePoints = []
                    }
                    HapticFeedback.impact(.medium)
                }
                controlButton(icon: "heart.text.square.fill", tint: .pink) {
                    showHealth = true
                    HapticFeedback.impact(.light)
                }
                controlButton(icon: "sparkles", tint: Color(red: 0.6, green: 0.35, blue: 0.95)) {
                    showInsights = true
                    HapticFeedback.impact(.light)
                }
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                withAnimation { categoryFilter = nil }
            } label: {
                Label("All categories", systemImage: categoryFilter == nil ? "checkmark" : "square.grid.2x2")
            }
            Divider()
            ForEach(ElementCategory.allCases) { cat in
                Button {
                    withAnimation { categoryFilter = cat }
                } label: {
                    Label(cat.displayName, systemImage: categoryFilter == cat ? "checkmark" : cat.icon)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "line.3.horizontal.decrease.circle\(categoryFilter == nil ? "" : ".fill")")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(categoryFilter == nil ? .white : Color.accentColor)
                Text(categoryFilter?.displayName ?? "Filter")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(categoryFilter == nil ? .white : Color.accentColor)
                    .lineLimit(1)
            }
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
    }

    private func controlButton(icon: String, tint: Color, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                if let label {
                    Text(LocalizedStringKey(label))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Zone draw toolbar

    private var zoneDrawToolbar: some View {
        HStack(spacing: 10) {
            zoneToolButton("Cancel", icon: "xmark", tint: .red) {
                withAnimation { zoneDrawMode = false; draftZonePoints = [] }
            }
            zoneToolButton("Undo", icon: "arrow.uturn.backward", tint: .white) {
                if !draftZonePoints.isEmpty { draftZonePoints.removeLast() }
            }
            .opacity(draftZonePoints.isEmpty ? 0.4 : 1)
            zoneToolButton("Save", icon: "checkmark", tint: .green) {
                Task { await saveDraftZone() }
            }
            .opacity(draftZonePoints.count < 3 ? 0.4 : 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(.bottom, 40)
    }

    private func zoneToolButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func saveDraftZone() async {
        guard draftZonePoints.count >= 3, let pid = propertyService.primary?.id else { return }
        let poly = draftZonePoints.map { ImagePoint(x: $0.x, y: $0.y) }
        let created = await zoneService.createImageZone(propertyId: pid, imagePolygon: poly)
        withAnimation { zoneDrawMode = false; draftZonePoints = [] }
        HapticFeedback.success()
        if let created { editZone = created }   // open editor to name/color it
    }

    // MARK: - Section filter bar

    private var sectionBar: some View {
        HStack(spacing: 4) {
            sectionChip(label: "All", value: nil)
            sectionChip(label: "1", value: 0)
            sectionChip(label: "2", value: 1)
            sectionChip(label: "3", value: 2)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .padding(.top, 10)
    }

    private func sectionChip(label: String, value: Int?) -> some View {
        let active = sectionFilter == value
        return Button {
            withAnimation(.spring(response: 0.3)) { sectionFilter = value }
            HapticFeedback.selection()
        } label: {
            Text(LocalizedStringKey(label))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.black : .white)
                .frame(minWidth: 34)
                .padding(.vertical, 7)
                .background(active ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No property yet")
                .font(.headline)
            Text("Add a property to see its Digital Twin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadData() async {
        guard let pid = propertyService.primary?.id else { return }
        if elementService.elements.isEmpty {
            await elementService.load(propertyId: pid)
        }
        if zoneService.zones.isEmpty {
            await zoneService.load(propertyId: pid)
        }
    }
}

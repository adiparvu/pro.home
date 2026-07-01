import SwiftUI

// MARK: - Digital Twin (static aerial photo + element pins)
//
// The Digital Twin is the property's aerial photo. There is no map.
// The user taps the "+" pin button, then taps the photo to drop an element
// exactly where they want it. Pins can be dragged to reposition, and tapped
// to open the element detail.

struct DigitalTwinView: View {
    @EnvironmentObject var propertyService: PropertyService
    @Environment(PropertyElementService.self) var elementService
    @Environment(PropertyZoneService.self) var zoneService
    @Environment(CurrencyService.self) var currencyService
    @EnvironmentObject var appSettings: AppSettings
    @Environment(DocumentService.self) var documentService
    @Environment(TaskService.self) var taskService

    @State private var selectedElement: PropertyElement?
    @State private var pinMode = false
    @State private var pendingPin: CGPoint?
    @State private var showInsights = false
    @State private var showHealth = false
    @State private var controlsExpanded = false
    @State private var showNames = true
    @State private var editElementId: UUID?
    @State private var deleteElement: PropertyElement?
    @State private var categoryFilter: ElementCategory? = nil
    @State private var zoneDrawMode = false
    @State private var draftZonePoints: [CGPoint] = []
    @State private var editZone: PropertyZone?
    @State private var reshapeZoneId: UUID?
    @State private var reshapePoints: [CGPoint] = []
    @State private var zoneView: ZoneViewKind = .hidden

    enum ZoneViewKind: Equatable { case hidden, all, zone(UUID) }

    /// Editing modes force everything visible so the user has context.
    private var editingOverlayActive: Bool { pinMode || zoneDrawMode || reshapeZoneId != nil }

    private var displayedZones: [PropertyZone] {
        let base = reshapeZoneId == nil ? zoneService.zones : zoneService.zones.filter { $0.id != reshapeZoneId }
        if editingOverlayActive { return base }
        switch zoneView {
        case .hidden:        return []
        case .all:           return base
        case .zone(let id):  return base.filter { $0.id == id }
        }
    }

    private var displayedElements: [PropertyElement] {
        if editingOverlayActive { return elementService.elements }
        switch zoneView {
        case .hidden:
            return elementService.elements   // all elements, just no zone outlines
        case .all:
            return elementService.elements
        case .zone(let id):
            guard let z = zoneService.zones.first(where: { $0.id == id }) else { return [] }
            return elementService.elements.filter { el in
                // Prefer geometric containment on the photo; fall back to a saved zoneId link.
                let x = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionX
                let y = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionY
                return z.containsImage(x: x, y: y) || el.zoneId == id
            }
        }
    }

    private var zoneViewLabel: String {
        switch zoneView {
        case .hidden: return String(localized: "Zones")
        case .all:    return String(localized: "All zones")
        case .zone(let id):
            return zoneService.zones.first { $0.id == id }?.name ?? String(localized: "Zone")
        }
    }

    var body: some View {
        @Bindable var elementService = elementService
        return ZStack(alignment: .bottomTrailing) {
            if let prop = propertyService.primary {
                AerialCanvasView(
                    property: prop,
                    elements: displayedElements,
                    zones: displayedZones,
                    interactive: true,
                    pinMode: pinMode,
                    zoneDrawMode: zoneDrawMode,
                    draftZonePoints: draftZonePoints,
                    reshapeMode: reshapeZoneId != nil,
                    reshapePoints: reshapePoints,
                    showNames: showNames,
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
                    onAddZonePoint: { draftZonePoints.append($0) },
                    onZoneReshape: { zone in
                        editZone = nil
                        reshapePoints = zone.imagePoints.map { CGPoint(x: $0.x, y: $0.y) }
                        reshapeZoneId = zone.id
                        HapticFeedback.impact(.medium)
                    },
                    onZoneDelete: { zone in Task { await zoneService.delete(zone) } },
                    onMoveReshapePoint: { idx, p in
                        if idx < reshapePoints.count { reshapePoints[idx] = p }
                    },
                    onRemoveReshapePoint: { idx in
                        if reshapePoints.count > 3, idx < reshapePoints.count {
                            reshapePoints.remove(at: idx)
                            HapticFeedback.impact(.light)
                        }
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                zoneSelectorBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if zoneDrawMode {
                    zoneDrawToolbar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if reshapeZoneId != nil {
                    reshapeToolbar
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
                .environment(elementService)
                .environment(currencyService)
                .environmentObject(appSettings)
                .environment(documentService)
                .environment(taskService)
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
                .environment(zoneService)
                .environment(elementService)
                .environment(currencyService)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showHealth) {
            PropertyHealthDashboardView()
                .environment(elementService)
                .environment(currencyService)
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
        .padding(.trailing, AppSpacing.lg)
        .padding(.top, AppSpacing.sm)
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
                    .font(AppFont.title3)
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
                    .font(AppFont.title3)
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
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(.bottom, 40)
    }

    private func zoneToolButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(LocalizedStringKey(title)).font(AppFont.footnoteEmphasis)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(.plain)
    }

    private func saveDraftZone() async {
        guard draftZonePoints.count >= 3, let pid = propertyService.primary?.id else { return }
        let poly = draftZonePoints.map { ImagePoint(x: $0.x, y: $0.y) }
        let created = await zoneService.createImageZone(propertyId: pid, imagePolygon: poly)
        withAnimation { zoneDrawMode = false; draftZonePoints = [] }
        HapticFeedback.success()
        if let created {
            zoneView = .all          // reveal zones so the new one shows
            editZone = created       // open editor to name/color it
        }
    }

    // MARK: - Reshape toolbar

    private var reshapeToolbar: some View {
        HStack(spacing: 10) {
            zoneToolButton("Cancel", icon: "xmark", tint: .red) {
                withAnimation { reshapeZoneId = nil; reshapePoints = [] }
            }
            zoneToolButton("Add point", icon: "plus", tint: .white) {
                let n = Double(reshapePoints.count)
                let cx = n > 0 ? reshapePoints.map(\.x).reduce(0, +) / n : 0.5
                let cy = n > 0 ? reshapePoints.map(\.y).reduce(0, +) / n : 0.5
                reshapePoints.append(CGPoint(x: min(cx + 0.04, 1), y: min(cy + 0.04, 1)))
            }
            zoneToolButton("Save", icon: "checkmark", tint: .green) {
                Task { await saveReshape() }
            }
            .opacity(reshapePoints.count < 3 ? 0.4 : 1)
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(.bottom, 40)
    }

    private func saveReshape() async {
        guard reshapePoints.count >= 3, let id = reshapeZoneId,
              var zone = zoneService.zones.first(where: { $0.id == id }) else { return }
        zone.imagePolygon = reshapePoints.map { ImagePoint(x: $0.x, y: $0.y) }
        await zoneService.update(zone)
        withAnimation { reshapeZoneId = nil; reshapePoints = [] }
        HapticFeedback.success()
    }

    // MARK: - Zone selector bar (middle) — zones & their elements are hidden
    // until the user picks one here.

    private var zoneSelectorBar: some View {
        Menu {
            Button { withAnimation { zoneView = .hidden } } label: {
                Label("Hide zones", systemImage: zoneView == .hidden ? "checkmark" : "eye.slash")
            }
            Button { withAnimation { zoneView = .all } } label: {
                Label("All zones", systemImage: zoneView == .all ? "checkmark" : "square.stack.3d.up")
            }
            if !zoneService.zones.isEmpty {
                Divider()
                ForEach(zoneService.zones) { z in
                    Button { withAnimation { zoneView = .zone(z.id) } } label: {
                        Label(z.name, systemImage: zoneView == .zone(z.id) ? "checkmark" : z.icon)
                    }
                }
            }
            if case .zone(let id) = zoneView, let z = zoneService.zones.first(where: { $0.id == id }) {
                Divider()
                Button { editZone = z } label: { Label("Edit zone details", systemImage: "pencil") }
                Button {
                    reshapePoints = z.imagePoints.map { CGPoint(x: $0.x, y: $0.y) }
                    reshapeZoneId = z.id
                    HapticFeedback.impact(.medium)
                } label: { Label("Edit zone shape", systemImage: "pencil.and.outline") }
                Button(role: .destructive) {
                    Task { await zoneService.delete(z) }
                    zoneView = .hidden
                } label: { Label("Delete zone", systemImage: "trash") }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: zoneView == .hidden ? "square.on.square.dashed" : "square.on.square")
                    .font(AppFont.captionEmphasis)
                Text(zoneViewLabel)
                    .font(AppFont.captionEmphasis).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .padding(.top, 10)
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

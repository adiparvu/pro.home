import SwiftUI

// MARK: - Digital Twin (static aerial photo + element pins)
//
// The Digital Twin is the property's aerial photo. There is no map.
// The user taps the "+" pin button, then taps the photo to drop an element
// exactly where they want it. Pins can be dragged to reposition, and tapped
// to open the element detail.

struct DigitalTwinView: View {
    @Environment(PropertyService.self) var propertyService
    @Environment(PropertyElementService.self) var elementService
    @Environment(PropertyZoneService.self) var zoneService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings
    @Environment(DocumentService.self) var documentService
    @Environment(TaskService.self) var taskService
    @Environment(PhotoJournalService.self) var photoJournalService

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
    @State private var inspectZone: PropertyZone?
    @State private var mapFocus: MapFocus?
    @State private var showMapSearch = false
    @State private var mapSearchText = ""
    @State private var showZonesList = false
    @State private var showObjectsList = false
    @State private var showLayers = false
    @State private var showJournal = false
    @State private var showTimeMachine = false
    /// Local scans store (LiDAR/USDZ) — the source of pin "3D" badges.
    @State private var blueprintService = BlueprintService()

    // Live layers (Faza 3) — persisted so the twin reopens as it was left.
    @AppStorage("prvio.twin.layer.utilities") private var layerUtilities = false
    @AppStorage("prvio.twin.layer.tasks") private var layerTasks = false
    @AppStorage("prvio.twin.layer.health") private var layerHealth = false
    @AppStorage("prvio.twin.layer.journal") private var layerJournal = false

    private var anyLayerActive: Bool { layerUtilities || layerTasks || layerHealth || layerJournal }

    enum ZoneViewKind: Equatable { case hidden, all, zone(UUID) }

    /// Editing modes force everything visible so the user has context.
    private var editingOverlayActive: Bool { pinMode || zoneDrawMode || reshapeZoneId != nil }

    private var displayedZones: [PropertyZone] {
        let base = reshapeZoneId == nil ? zoneService.zones : zoneService.zones.filter { $0.id != reshapeZoneId }
        if editingOverlayActive { return base }
        var visible: [PropertyZone]
        switch zoneView {
        case .hidden:        visible = []
        case .all:           visible = base
        case .zone(let id):  visible = base.filter { $0.id == id }
        }
        // Health tinting only makes sense over every zone at once.
        if layerHealth { visible = base }
        // The buried-utilities layer surfaces underground zones on the same
        // photo even while the zones lens is off.
        if layerUtilities {
            for z in base where z.layer == .utility && !visible.contains(where: { $0.id == z.id }) {
                visible.append(z)
            }
        }
        return visible
    }

    // MARK: - Live layer data

    private var dashedZoneIds: Set<UUID> {
        guard layerUtilities else { return [] }
        return Set(zoneService.zones.filter { $0.layer == .utility }.map(\.id))
    }

    /// Health tint per zone: the average health of the elements inside it
    /// (geometric containment or saved link), falling back to the zone's own
    /// score when it's empty.
    private var zoneTintOverride: [UUID: Color] {
        guard layerHealth else { return [:] }
        var tint: [UUID: Color] = [:]
        for zone in zoneService.zones {
            let inside = elementService.elements.filter { el in
                let p = normPoint(el)
                return zone.containsImage(x: p.x, y: p.y) || el.zoneId == zone.id
            }
            let score = inside.isEmpty
                ? zone.healthScore
                : inside.reduce(0) { $0 + $1.healthScore } / inside.count
            tint[zone.id] = score >= 80 ? Color.brandSuccess : score >= 50 ? .orange : .red
        }
        return tint
    }

    /// Pulsing badge per element with open work: red for overdue or urgent
    /// tasks, orange for the rest.
    private var elementBadges: [UUID: Color] {
        guard layerTasks else { return [:] }
        var badges: [UUID: Color] = [:]
        for task in taskService.tasks where !task.isCompleted && task.status != "cancelled" {
            guard let elId = task.elementId else { continue }
            let urgent = task.isOverdue || task.priority == "urgent" || task.priority == "high"
            if urgent { badges[elId] = .red }
            else if badges[elId] == nil { badges[elId] = .orange }
        }
        return badges
    }

    /// Elements with a linked 3D scan (LiDAR/USDZ) — badge on the pin,
    /// viewer in the inspector.
    private var threeDElementIds: Set<UUID> {
        Set(blueprintService.scans.compactMap { $0.is3D ? $0.elementId : nil })
    }

    /// Journal photo counts anchored at their zone's centroid.
    private var journalBadges: [TwinJournalBadge] {
        guard layerJournal else { return [] }
        return zoneService.zones.compactMap { zone in
            let pts = zone.imagePoints
            guard !pts.isEmpty else { return nil }
            let count = photoJournalService.entries.filter { $0.zoneId == zone.id }.count
            guard count > 0 else { return nil }
            let n = Double(pts.count)
            return TwinJournalBadge(
                id: zone.id,
                point: CGPoint(x: pts.map(\.x).reduce(0, +) / n,
                               y: pts.map(\.y).reduce(0, +) / n),
                count: count
            )
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
                    focus: mapFocus,
                    dashedZoneIds: dashedZoneIds,
                    zoneTintOverride: zoneTintOverride,
                    elementBadges: elementBadges,
                    journalBadges: journalBadges,
                    onJournalBadgeTap: { _ in showJournal = true },
                    threeDElementIds: threeDElementIds,
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
                    onZoneTap: { inspectZone = $0 },
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

                lensBar
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

                if anyLayerActive && !editingOverlayActive {
                    TwinLayersLegend(utilities: layerUtilities, tasks: layerTasks,
                                     health: layerHealth, journal: layerJournal)
                        .padding(.leading, AppSpacing.lg)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.opacity)
                }

                // Time machine covers the whole twin while active — it's the
                // same view of the property, seen through time.
                if showTimeMachine {
                    TwinTimeMachineOverlay(
                        snapshots: TwinTimeline.snapshots(from: photoJournalService.entries),
                        onClose: { withAnimation(.smooth) { showTimeMachine = false } }
                    )
                    .transition(.opacity)
                    .zIndex(10)
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
                .environment(propertyService)
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
            // Apple Maps-style inspector: compact card first, map stays
            // interactive behind it; deep dives launch from the card.
            ElementInspectorSheet(
                element: element,
                zoneName: zoneName(for: element),
                onEdit: {
                    // Let the inspector finish dismissing before presenting
                    // the edit sheet, or SwiftUI drops the presentation.
                    let id = element.id
                    Task {
                        try? await Task.sleep(for: .milliseconds(380))
                        editElementId = id
                    }
                }
            )
            .environment(elementService)
            .environment(currencyService)
            .environment(appSettings)
            .environment(documentService)
            .environment(taskService)
            .environment(blueprintService)
            .presentationDetents([.height(320), .medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $inspectZone) { zone in
            ZoneBottomSheet(
                zone: zone,
                onEdit: {
                    inspectZone = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(380))
                        editZone = zone
                    }
                },
                onReshape: {
                    inspectZone = nil
                    reshapePoints = zone.imagePoints.map { CGPoint(x: $0.x, y: $0.y) }
                    reshapeZoneId = zone.id
                    HapticFeedback.impact(.medium)
                },
                onAddObject: {
                    inspectZone = nil
                    withAnimation(.spring(response: 0.3)) { pinMode = true }
                },
                onDelete: {
                    inspectZone = nil
                    Task { await zoneService.delete(zone) }
                },
                onFocus: {
                    inspectZone = nil
                    flyTo(zone: zone)
                }
            )
            .environment(elementService)
            .environment(currencyService)
            .environment(appSettings)
            .environment(documentService)
            .environment(taskService)
            .presentationDetents([.height(360), .medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLayers) {
            TwinLayersSheet(utilities: $layerUtilities, tasks: $layerTasks,
                            health: $layerHealth, journal: $layerJournal)
                .presentationDetents([.height(430)])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showJournal) {
            NavigationStack { PhotoJournalView() }
                .environment(photoJournalService)
                .environment(propertyService)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showZonesList) {
            NavigationStack { ZonesListView() }
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showObjectsList) {
            NavigationStack { ObjectsListView() }
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { pendingPin != nil },
            set: { if !$0 { pendingPin = nil } }
        )) {
            AddPropertyElementView(defaultPosition: pendingPin ?? CGPoint(x: 0.5, y: 0.5)) { payload in
                Task { await elementService.add(payload) }
            }
            .environment(propertyService)
        }
        .sheet(isPresented: $showInsights) {
            TwinInsightsSheet()
                .environment(propertyService)
                .environment(zoneService)
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
        }
        .sheet(isPresented: $showHealth) {
            PropertyHealthDashboardView()
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
        }
        .sheet(item: $editZone) { zone in
            ZoneEditSheet(
                zone: zone,
                onSave: { updated in Task { await zoneService.update(updated) } },
                onDelete: { Task { await zoneService.delete(zone) } }
            )
        }
        .task(id: propertyService.primary?.id) { await loadData() }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            controlButton(icon: controlsExpanded ? "xmark" : "ellipsis", tint: .white) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { controlsExpanded.toggle() }
                HapticFeedback.impact(.medium)
            }

            // The layers switcher is always one tap away — it's how the twin
            // becomes "live" (utilities, tasks, health, journal).
            controlButton(
                icon: "square.3.layers.3d\(anyLayerActive ? ".top.filled" : "")",
                tint: anyLayerActive ? Color.accentColor : .white,
                label: "Layers"
            ) {
                showLayers = true
                HapticFeedback.impact(.light)
            }

            // Time machine: the yard through its seasons, from journal photos.
            controlButton(icon: "clock.arrow.circlepath", tint: .white, label: "Time") {
                withAnimation(.smooth) { showTimeMachine = true }
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
                controlButton(icon: "sparkles", tint: Color.brandPurple) {
                    showInsights = true
                    HapticFeedback.impact(.light)
                }
            }
        }
        .padding(.trailing, AppSpacing.lg)
        // Sits below the lens bar so the two glass layers never collide.
        .padding(.top, 64)
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

    // MARK: - Lens bar — "one map, many lenses": zones, categories, lists
    // and search are filters over the same photo, never separate pages.

    private var lensBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                zoneSelectorBar
                categoryLensChip
                Spacer()
                listsMenu
                SearchIconButton(isActive: $showMapSearch, style: .glass)
            }
            .padding(.horizontal, AppSpacing.lg)

            if showMapSearch {
                mapSearchOverlay
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.opacity)
            }
        }
        .padding(.top, 10)
    }

    private var categoryLensChip: some View {
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
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle\(categoryFilter == nil ? "" : ".fill")")
                    .font(AppFont.captionEmphasis)
                Text(categoryFilter?.displayName ?? String(localized: "Objects"))
                    .font(AppFont.captionEmphasis).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(categoryFilter == nil ? .white : Color.accentColor)
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
    }

    private var listsMenu: some View {
        Menu {
            Button { showZonesList = true } label: {
                Label("Zones list", systemImage: "square.stack.3d.up")
            }
            Button { showObjectsList = true } label: {
                Label("Objects list", systemImage: "cube.box")
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 40, height: 40)
                .glassCircle()
        }
        .accessibilityLabel("Lists")
    }

    // MARK: - Map search ("fly-to")

    private var searchMatches: [PropertyElement] {
        let q = mapSearchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return elementService.elements.filter {
            $0.name.matchesSearch(q) || $0.elementType.displayName.matchesSearch(q)
        }
    }

    private var mapSearchOverlay: some View {
        VStack(spacing: 8) {
            PageSearchField(text: $mapSearchText, placeholder: "Search the map…")
            if !mapSearchText.isEmpty {
                VStack(spacing: 0) {
                    if searchMatches.isEmpty {
                        Text("No results")
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, AppSpacing.base)
                    } else {
                        ForEach(searchMatches.prefix(6)) { el in
                            Button {
                                HapticFeedback.impact(.light)
                                withAnimation(.easeOut(duration: 0.12)) {
                                    showMapSearch = false
                                    mapSearchText = ""
                                }
                                flyTo(element: el)
                                selectedElement = el
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: el.elementType.icon)
                                        .font(AppFont.footnoteEmphasis)
                                        .foregroundStyle(el.elementType.accentColor)
                                        .frame(width: 28)
                                    Text(el.name)
                                        .font(AppFont.footnote)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "location.fill")
                                        .font(AppFont.label)
                                        .foregroundStyle(Color.primary.opacity(0.35))
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .liquidGlass(cornerRadius: 14)
            }
        }
    }

    /// Normalized on-photo position of an element (legacy rows default to centre).
    private func normPoint(_ el: PropertyElement) -> CGPoint {
        let nx = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionX
        let ny = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionY
        return CGPoint(x: nx, y: ny)
    }

    private func flyTo(element: PropertyElement) {
        mapFocus = MapFocus(point: normPoint(element))
    }

    private func flyTo(zone: PropertyZone) {
        let pts = zone.imagePoints
        guard !pts.isEmpty else { return }
        let n = Double(pts.count)
        mapFocus = MapFocus(point: CGPoint(
            x: pts.map(\.x).reduce(0, +) / n,
            y: pts.map(\.y).reduce(0, +) / n
        ))
    }

    /// The zone an element belongs to — geometric containment first, saved
    /// link second. Shown in the inspector header.
    private func zoneName(for el: PropertyElement) -> String? {
        let p = normPoint(el)
        if let z = zoneService.zones.first(where: { $0.containsImage(x: p.x, y: p.y) }) { return z.name }
        if let id = el.zoneId { return zoneService.zones.first(where: { $0.id == id })?.name }
        return nil
    }

    // MARK: - Zone selector — zones & their elements are hidden
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "photo.on.rectangle.angled",
            title: "No property yet",
            message: "Add a property to see its Digital Twin."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadData() async {
        guard let pid = propertyService.primary?.id else { return }
        // Reload whenever the cached data belongs to another property, so a
        // property switch swaps the twin's contents too.
        if elementService.elements.first?.propertyId != pid {
            await elementService.load(propertyId: pid)
        }
        if zoneService.zones.first?.propertyId != pid {
            await zoneService.load(propertyId: pid)
        }
    }
}

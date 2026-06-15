import SwiftUI
import MapKit
import CoreLocation

/// Digital Property Twin — an immersive satellite map with interactive zones
/// (MapPolygon) and geo-located objects, all native SwiftUI + MapKit.
struct DigitalTwinView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedZone: PropertyZone?
    @State private var selectedElement: PropertyElement?
    @State private var activeLayer: PropertyLayer?
    @State private var heatmap = false
    @State private var is3D = false
    @State private var drawMode = false
    @State private var draftPoints: [GeoPoint] = []
    @State private var editingZone: PropertyZone?
    @State private var addingToZone: PropertyZone?
    @State private var reshapeZone: PropertyZone?
    @State private var reshapePoints: [GeoPoint] = []
    @State private var moveStartCenter: CLLocationCoordinate2D?
    @State private var moveStartPoints: [GeoPoint]?
    @State private var draggingObject: (id: UUID, coord: CLLocationCoordinate2D)?
    @State private var showAddObject = false
    @State private var showInsights = false
    @State private var showHealth = false
    @State private var showLabels = false
    @State private var didCenter = false

    private var dragTargetZoneId: UUID? {
        guard let d = draggingObject else { return nil }
        return zoneService.zone(containing: d.coord)?.id
    }

    private var editingShape: Bool { reshapeZone != nil }

    // MARK: - Derived

    private var propertyCoordinate: CLLocationCoordinate2D {
        if let lat = propertyService.primary?.latitude,
           let lon = propertyService.primary?.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025)
    }

    private var visibleZones: [PropertyZone] {
        guard let activeLayer else { return zoneService.zones }
        return zoneService.zones.filter { $0.layer == activeLayer }
    }

    private var visibleObjects: [PropertyElement] {
        elementService.elements.filter { el in
            el.coordinate != nil && (activeLayer == nil || el.layer == activeLayer)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        MapReader { proxy in
            Map(position: $camera) {
                Annotation("", coordinate: propertyCoordinate) {
                    PropertyHomeMarker()
                }

                ForEach(visibleZones) { zone in
                    if zone.isDrawable {
                        MapPolygon(coordinates: zone.coordinates)
                            .foregroundStyle(zoneFill(zone))
                            .stroke(zoneStroke(zone),
                                    lineWidth: (selectedZone?.id == zone.id || zone.id == dragTargetZoneId) ? 3 : 1.5)
                    }
                    Annotation("", coordinate: zone.center) {
                        ZoneBadge(zone: zone,
                                  heatmap: heatmap,
                                  selected: selectedZone?.id == zone.id) {
                            select(zone)
                        }
                    }
                }

                ForEach(visibleObjects) { obj in
                    Annotation("", coordinate: objectCoord(obj)) {
                        VStack(spacing: 2) {
                            ObjectMarker(element: obj)
                            if showLabels {
                                Text(obj.name)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.black.opacity(0.5), in: Capsule())
                            }
                        }
                        .onTapGesture { if draggingObject == nil { selectedElement = obj } }
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .named("twinmap"))
                                .onChanged { value in
                                    if let c = proxy.convert(value.location, from: .named("twinmap")) {
                                        draggingObject = (obj.id, c)
                                    }
                                }
                                .onEnded { _ in Task { await commitObjectDrag(obj) } }
                        )
                    }
                }

                // Draw-in-progress polygon
                if draftPoints.count >= 3 {
                    MapPolygon(coordinates: draftPoints.map(\.coordinate))
                        .foregroundStyle(Color.blue.opacity(0.25))
                        .stroke(Color.blue, lineWidth: 2)
                }
                ForEach(Array(draftPoints.enumerated()), id: \.offset) { _, pt in
                    Annotation("", coordinate: pt.coordinate) {
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().fill(Color.blue).frame(width: 8, height: 8))
                            .shadow(color: .black.opacity(0.3), radius: 3)
                    }
                }

                // Reshape-in-progress polygon + draggable vertex handles
                if editingShape {
                    if reshapePoints.count >= 3 {
                        MapPolygon(coordinates: reshapePoints.map(\.coordinate))
                            .foregroundStyle(Color.blue.opacity(0.28))
                            .stroke(Color.blue, lineWidth: 2.5)
                    }
                    ForEach(Array(reshapePoints.enumerated()), id: \.offset) { idx, pt in
                        Annotation("", coordinate: pt.coordinate) {
                            VertexHandle()
                                .gesture(
                                    DragGesture(coordinateSpace: .named("twinmap"))
                                        .onChanged { value in
                                            if idx < reshapePoints.count,
                                               let c = proxy.convert(value.location, from: .named("twinmap")) {
                                                reshapePoints[idx] = GeoPoint(lat: c.latitude, lon: c.longitude)
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    if reshapePoints.count > 3, idx < reshapePoints.count {
                                        reshapePoints.remove(at: idx)
                                        HapticFeedback.impact(.medium)
                                    }
                                }
                        }
                    }
                    if reshapePoints.count >= 3 {
                        Annotation("", coordinate: reshapeCenter) {
                            MoveHandle()
                                .gesture(
                                    DragGesture(coordinateSpace: .named("twinmap"))
                                        .onChanged { value in
                                            guard let c = proxy.convert(value.location, from: .named("twinmap")) else { return }
                                            if moveStartCenter == nil {
                                                moveStartCenter = c
                                                moveStartPoints = reshapePoints
                                            }
                                            if let sc = moveStartCenter, let sp = moveStartPoints {
                                                let dLat = c.latitude - sc.latitude
                                                let dLon = c.longitude - sc.longitude
                                                reshapePoints = sp.map { GeoPoint(lat: $0.lat + dLat, lon: $0.lon + dLon) }
                                            }
                                        }
                                        .onEnded { _ in
                                            moveStartCenter = nil
                                            moveStartPoints = nil
                                        }
                                )
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .coordinateSpace(.named("twinmap"))
            .mapControls { MapCompass(); MapScaleView() }
            .onTapGesture { location in
                guard let coord = proxy.convert(location, from: .local) else { return }
                handleTap(at: coord)
            }
        }
        .overlay(alignment: .top) { if !drawMode && !editingShape { layerBar } }
        .overlay(alignment: .bottomLeading) { if heatmap && !drawMode && !editingShape { heatmapLegend } }
        .overlay(alignment: .bottom) { if drawMode { drawToolbar } }
        .overlay(alignment: .top) { if drawMode { drawBanner } }
        .overlay(alignment: .bottom) { if editingShape { reshapeToolbar } }
        .overlay(alignment: .top) { if editingShape { reshapeBanner } }
        .overlay(alignment: .top) { if draggingObject != nil { objectDragBanner } }
        .navigationTitle("Digital Twin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedZone) { zone in
            ZoneBottomSheet(
                zone: zone,
                onEdit: {
                    selectedZone = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { editingZone = zone }
                },
                onReshape: {
                    selectedZone = nil
                    startReshape(zone)
                },
                onAddObject: {
                    selectedZone = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { addingToZone = zone }
                },
                onDelete: { Task { await zoneService.delete(zone); selectedZone = nil } },
                onFocus: { focus(on: zone) }
            )
            .environmentObject(elementService)
            .environmentObject(currencyService)
            .environmentObject(appSettings)
            .presentationDetents([.height(320), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .height(320)))
            .presentationBackground(.thinMaterial)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingZone) { zone in
            ZoneEditSheet(
                zone: zone,
                onSave: { updated in Task { await zoneService.update(updated) } },
                onDelete: { Task { await zoneService.delete(zone) } }
            )
        }
        .sheet(item: $addingToZone) { zone in
            AddPropertyElementView(defaultPosition: CGPoint(x: 0.5, y: 0.5)) { payload in
                var p = payload
                p.zoneId = zone.id
                p.latitude = zone.center.latitude
                p.longitude = zone.center.longitude
                Task { await elementService.add(p) }
            }
        }
        .sheet(isPresented: $showAddObject) {
            AddPropertyElementView(defaultPosition: CGPoint(x: 0.5, y: 0.5)) { payload in
                Task { await elementService.add(payload) }
            }
        }
        .sheet(item: $selectedElement) { element in
            PropertyElementDetailView(element: element)
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
        .sheet(isPresented: $showInsights) {
            TwinInsightsSheet()
                .environmentObject(propertyService)
                .environmentObject(zoneService)
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
        }
        .task { await loadData() }

        // sideControls is placed here, outside MapReader, so MKMapView's
        // internal gesture recognizers cannot intercept button taps.
        if !drawMode && !editingShape { sideControls }
        } // ZStack
    }

    // MARK: - Controls

    private var layerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                layerChip(nil, label: "All", icon: "square.stack.3d.up.fill")
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    layerChip(layer, label: layer.displayName, icon: layer.icon)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.clear)
    }

    private func layerChip(_ layer: PropertyLayer?, label: String, icon: String) -> some View {
        let active = activeLayer == layer
        return Button {
            withAnimation(.spring(response: 0.3)) { activeLayer = layer }
            HapticFeedback.selection()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? .primary : Color.primary.opacity(0.65))
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassCapsule()
        .overlay {
            if active {
                Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2)
            }
        }
    }

    private var sideControls: some View {
        VStack(spacing: 12) {
            controlButton(icon: "sparkles", tint: Color(red: 0.6, green: 0.35, blue: 0.95)) {
                showInsights = true
                HapticFeedback.impact(.light)
            }
            controlButton(icon: is3D ? "rotate.3d.fill" : "rotate.3d",
                          tint: is3D ? .blue : .primary) {
                toggle3D()
            }
            controlButton(icon: heatmap ? "flame.fill" : "flame",
                          tint: heatmap ? .orange : .primary) {
                withAnimation(.spring(response: 0.3)) { heatmap.toggle() }
            }
            controlButton(icon: showLabels ? "tag.fill" : "tag",
                          tint: showLabels ? .blue : .primary) {
                withAnimation(.spring(response: 0.3)) { showLabels.toggle() }
            }
            controlButton(icon: "heart.text.square.fill", tint: .pink) {
                showHealth = true
            }
            controlButton(icon: "cube.box.fill", tint: .primary) {
                showAddObject = true
                HapticFeedback.impact(.light)
            }
            controlButton(icon: "plus.viewfinder", tint: .primary) {
                startDrawing()
            }
            controlButton(icon: "scope", tint: .primary) {
                recenter()
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 36)
    }

    private var heatmapLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEALTH")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [.red, .orange, Color(red: 0.2, green: 0.8, blue: 0.45)],
                        startPoint: .bottom, endPoint: .top))
                    .frame(width: 8, height: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text("100").font(.system(size: 9, weight: .semibold))
                    Spacer()
                    Text("50").font(.system(size: 9, weight: .semibold))
                    Spacer()
                    Text("0").font(.system(size: 9, weight: .semibold))
                }
                .frame(height: 56)
                .foregroundStyle(.primary)
            }
        }
        .padding(10)
        .glassRoundedRect(14)
        .allowsHitTesting(false)
        .padding(.leading, 16)
        .padding(.bottom, 36)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .transition(.opacity)
    }

    private func controlButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .glassCircle()
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 3)
    }

    private var drawBanner: some View {
        Text(draftPoints.count < 3
             ? "Tap the map to add corners (\(draftPoints.count)/3)"
             : "\(draftPoints.count) corners · tap to add more")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .allowsHitTesting(false)
            .padding(.top, 60)
            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var drawToolbar: some View {
        HStack(spacing: 10) {
            drawButton("Cancel", icon: "xmark", tint: .red) { cancelDrawing() }
            drawButton("Undo", icon: "arrow.uturn.backward", tint: .primary) {
                if !draftPoints.isEmpty { draftPoints.removeLast() }
            }
            .disabled(draftPoints.isEmpty)
            drawButton("Save", icon: "checkmark", tint: .green) {
                Task { await saveDrawnZone() }
            }
            .disabled(draftPoints.count < 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCapsule()
        .padding(.bottom, 40)
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var objectDragBanner: some View {
        let targetName = dragTargetZoneId.flatMap { id in zoneService.zones.first { $0.id == id }?.name }
        return HStack(spacing: 6) {
            Image(systemName: targetName != nil ? "arrow.down.to.line" : "mappin.slash")
                .font(.system(size: 12, weight: .bold))
            Text(targetName != nil ? "→ \(targetName!)" : "Outside zones")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(targetName != nil ? Color(red: 0.2, green: 0.75, blue: 0.4) : .secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassCapsule()
        .allowsHitTesting(false)
        .padding(.top, 60)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var reshapeBanner: some View {
        Text("Drag corners · double-tap to remove a corner")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .allowsHitTesting(false)
            .padding(.top, 60)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var reshapeToolbar: some View {
        HStack(spacing: 10) {
            drawButton("Cancel", icon: "xmark", tint: .red) { cancelReshape() }
            drawButton("Save", icon: "checkmark", tint: .green) {
                Task { await saveReshape() }
            }
            .disabled(reshapePoints.count < 3)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCapsule()
        .padding(.bottom, 40)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func drawButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Styling

    private func zoneFill(_ zone: PropertyZone) -> some ShapeStyle {
        let base = heatmap ? zone.healthColor : zone.tint
        let opacity: Double = zone.id == dragTargetZoneId ? 0.55
            : (selectedZone?.id == zone.id ? 0.45 : 0.26)
        return base.opacity(opacity)
    }

    private func zoneStroke(_ zone: PropertyZone) -> some ShapeStyle {
        (heatmap ? zone.healthColor : zone.tint).opacity(0.9)
    }

    // MARK: - Actions

    private func handleTap(at coord: CLLocationCoordinate2D) {
        if editingShape { return }   // vertex handles own the gestures while reshaping
        if drawMode {
            draftPoints.append(GeoPoint(lat: coord.latitude, lon: coord.longitude))
            HapticFeedback.selection()
        } else if let zone = zoneService.zone(containing: coord) {
            select(zone)
        }
    }

    private func startReshape(_ zone: PropertyZone) {
        reshapePoints = zone.polygon
        withAnimation { reshapeZone = zone }
        focus(on: zone)
        HapticFeedback.impact(.light)
    }

    private func cancelReshape() {
        withAnimation { reshapeZone = nil }
        reshapePoints = []
    }

    private func saveReshape() async {
        guard var zone = reshapeZone, reshapePoints.count >= 3 else { return }
        zone.polygon = reshapePoints
        await zoneService.update(zone)
        HapticFeedback.success()
        withAnimation { reshapeZone = nil }
        reshapePoints = []
    }

    private var reshapeCenter: CLLocationCoordinate2D {
        guard !reshapePoints.isEmpty else { return propertyCoordinate }
        let lat = reshapePoints.map(\.lat).reduce(0, +) / Double(reshapePoints.count)
        let lon = reshapePoints.map(\.lon).reduce(0, +) / Double(reshapePoints.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func objectCoord(_ obj: PropertyElement) -> CLLocationCoordinate2D {
        if let d = draggingObject, d.id == obj.id { return d.coord }
        return obj.coordinate ?? propertyCoordinate
    }

    private func commitObjectDrag(_ obj: PropertyElement) async {
        guard let d = draggingObject, d.id == obj.id else { return }
        let coord = d.coord
        draggingObject = nil
        let zone = zoneService.zone(containing: coord)
        await elementService.updateGeo(
            elementId: obj.id,
            latitude: coord.latitude,
            longitude: coord.longitude,
            zoneId: zone?.id
        )
        HapticFeedback.success()
    }

    private func startDrawing() {
        HapticFeedback.impact(.light)
        selectedZone = nil
        draftPoints = []
        withAnimation { drawMode = true }
    }

    private func cancelDrawing() {
        withAnimation { drawMode = false }
        draftPoints = []
    }

    private func saveDrawnZone() async {
        guard draftPoints.count >= 3, let pid = propertyService.primary?.id else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewPropertyZone(
            propertyId: pid,
            name: "New zone",
            icon: "square.dashed",
            colorHex: PropertyLayer.property.color.hexString(),
            layer: PropertyLayer.property.rawValue,
            healthScore: 100,
            polygon: draftPoints,
            sortOrder: zoneService.zones.count,
            createdAt: now,
            updatedAt: now
        )
        let created = await zoneService.add(payload)
        HapticFeedback.success()
        withAnimation { drawMode = false }
        draftPoints = []
        if let created { editingZone = created }   // open editor to name it
    }

    private func select(_ zone: PropertyZone) {
        HapticFeedback.impact(.light)
        selectedZone = zone
        focus(on: zone)
    }

    private func focus(on zone: PropertyZone) {
        withAnimation(.easeInOut(duration: 0.7)) {
            if is3D {
                camera = .camera(MapCamera(centerCoordinate: zone.center, distance: 200, heading: 0, pitch: 60))
            } else {
                camera = .region(zone.region)
            }
        }
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.7)) {
            if is3D {
                camera = .camera(MapCamera(centerCoordinate: propertyCoordinate, distance: 360, heading: 0, pitch: 55))
            } else {
                camera = .region(MKCoordinateRegion(
                    center: propertyCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.0016, longitudeDelta: 0.0016)
                ))
            }
        }
        HapticFeedback.selection()
    }

    private func toggle3D() {
        withAnimation(.spring(response: 0.3)) { is3D.toggle() }
        HapticFeedback.impact(.light)
        if let zone = selectedZone { focus(on: zone) } else { recenter() }
    }

    private func loadData() async {
        guard let pid = propertyService.primary?.id else { return }
        await zoneService.load(propertyId: pid)
        if elementService.elements.isEmpty { await elementService.load(propertyId: pid) }
        if !didCenter {
            didCenter = true
            recenter()
        }
    }
}

// MARK: - Markers

private struct PropertyHomeMarker: View {
    var body: some View {
        Image(systemName: "house.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.95),
                                        Color(red: 0.25, green: 0.5, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

private struct ZoneBadge: View {
    let zone: PropertyZone
    let heatmap: Bool
    let selected: Bool
    let onTap: () -> Void

    private var color: Color { heatmap ? zone.healthColor : zone.tint }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Image(systemName: zone.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.95), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: selected ? 2.5 : 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                Text(zone.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            .scaleEffect(selected ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.plain)
    }
}

private struct VertexHandle: View {
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 26, height: 26)
            .overlay(Circle().fill(Color.blue).frame(width: 13, height: 13))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .contentShape(Circle())
    }
}

private struct MoveHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.blue, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .contentShape(Circle())
    }
}

private struct ObjectMarker: View {
    let element: PropertyElement

    var body: some View {
        Image(systemName: element.elementType.icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(element.healthColor.opacity(0.95), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .contentShape(Circle())
    }
}

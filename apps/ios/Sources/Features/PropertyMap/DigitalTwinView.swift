import SwiftUI
import MapKit
import CoreLocation

struct DigitalTwinView: View {
    @EnvironmentObject var propertyService: PropertyService
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject var zoneService: PropertyZoneService
    @EnvironmentObject var currencyService: CurrencyService
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var taskService: TaskService

    @State var camera: MapCameraPosition = .automatic
    @State var selectedZone: PropertyZone?
    @State var selectedElement: PropertyElement?
    @State var activeLayer: PropertyLayer?
    @State var heatmap = false
    @State var is3D = false
    @State var drawMode = false
    @State var draftPoints: [GeoPoint] = []
    @State var editingZone: PropertyZone?
    @State var addingToZone: PropertyZone?
    @State var reshapeZone: PropertyZone?
    @State var reshapePoints: [GeoPoint] = []
    @State var moveStartCenter: CLLocationCoordinate2D?
    @State var moveStartPoints: [GeoPoint]?
    @State var draggingObject: (id: UUID, coord: CLLocationCoordinate2D)?
    @State var showAddObject = false
    @State var showInsights = false
    @State var showHealth = false
    @State var showLabels = false
    @State var didCenter = false
    @State var isAerial = false
    @State var showStylePicker = false
    @AppStorage("prvio.mapStyle") var savedMapStyle: String = "hybrid"

    var currentMapStyle: MapStyle {
        switch savedMapStyle {
        case "standard":  return .standard
        case "satellite": return .imagery(elevation: .realistic)
        default:          return .hybrid(elevation: .realistic)
        }
    }

    var dragTargetZoneId: UUID? {
        guard let d = draggingObject else { return nil }
        return zoneService.zone(containing: d.coord)?.id
    }

    var editingShape: Bool { reshapeZone != nil }

    // MARK: - Derived

    var propertyCoordinate: CLLocationCoordinate2D {
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
        if isAerial {
            AerialPropertyView(
                property: propertyService.primary,
                zones: zoneService.zones,
                elements: elementService.elements
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) { if !drawMode { layerBar } }
            .overlay(alignment: .bottomTrailing) {
                if !drawMode { sideControls }
            }
            .task { await loadData() }
        } else {
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
                        .foregroundStyle(Color.accentColor.opacity(0.25))
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                ForEach(Array(draftPoints.enumerated()), id: \.offset) { _, pt in
                    Annotation("", coordinate: pt.coordinate) {
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().fill(Color.accentColor).frame(width: 8, height: 8))
                            .shadow(color: .black.opacity(0.3), radius: 3)
                    }
                }

                // Reshape-in-progress polygon + draggable vertex handles
                if editingShape {
                    if reshapePoints.count >= 3 {
                        MapPolygon(coordinates: reshapePoints.map(\.coordinate))
                            .foregroundStyle(Color.accentColor.opacity(0.28))
                            .stroke(Color.accentColor, lineWidth: 2.5)
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
            .mapStyle(currentMapStyle)
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
            .environmentObject(documentService)
            .environmentObject(taskService)
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
                .environmentObject(documentService)
                .environmentObject(taskService)
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
        .sheet(isPresented: $showStylePicker) {
            MapStylePickerSheet(selected: $savedMapStyle)
        }
        .task { await loadData() }

        // sideControls is placed outside MapReader so MKMapView's
        // internal gesture recognizers cannot intercept button taps.
        if !drawMode && !editingShape { sideControls }
        } // else (map mode)
        } // ZStack
    }
}

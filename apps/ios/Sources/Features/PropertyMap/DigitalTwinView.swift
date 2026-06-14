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
    @State private var placingZone = false
    @State private var showHealth = false
    @State private var didCenter = false

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
                                    lineWidth: selectedZone?.id == zone.id ? 3 : 1.5)
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
                    if let coord = obj.coordinate {
                        Annotation("", coordinate: coord) {
                            ObjectMarker(element: obj) { selectedElement = obj }
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView() }
            .onTapGesture { location in
                guard let coord = proxy.convert(location, from: .local) else { return }
                handleTap(at: coord)
            }
        }
        .overlay(alignment: .top) { layerBar }
        .overlay(alignment: .bottomTrailing) { sideControls }
        .overlay(alignment: .top) { if placingZone { placingBanner } }
        .navigationTitle("Digital Twin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedZone) { zone in
            ZoneBottomSheet(
                zone: zone,
                onAddObject: { /* future: place object in zone */ },
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
        .task { await loadData() }
    }

    // MARK: - Controls

    private var layerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                layerChip(nil, label: "Toate", icon: "square.stack.3d.up.fill")
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
            .glassCapsule()
            .overlay {
                if active {
                    Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var sideControls: some View {
        VStack(spacing: 12) {
            controlButton(icon: heatmap ? "flame.fill" : "flame",
                          tint: heatmap ? .orange : .primary) {
                withAnimation(.spring(response: 0.3)) { heatmap.toggle() }
            }
            controlButton(icon: "heart.text.square.fill", tint: .pink) {
                showHealth = true
            }
            controlButton(icon: placingZone ? "xmark" : "plus.viewfinder",
                          tint: placingZone ? .red : .primary) {
                withAnimation { placingZone.toggle() }
                HapticFeedback.impact(.light)
            }
            controlButton(icon: "scope", tint: .primary) {
                recenter()
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 36)
    }

    private func controlButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .glassCircle()
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var placingBanner: some View {
        Text("Atinge harta pentru a plasa o zonă nouă")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .padding(.top, 60)
            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Styling

    private func zoneFill(_ zone: PropertyZone) -> some ShapeStyle {
        let base = heatmap ? zone.healthColor : zone.tint
        return base.opacity(selectedZone?.id == zone.id ? 0.45 : 0.26)
    }

    private func zoneStroke(_ zone: PropertyZone) -> some ShapeStyle {
        (heatmap ? zone.healthColor : zone.tint).opacity(0.9)
    }

    // MARK: - Actions

    private func handleTap(at coord: CLLocationCoordinate2D) {
        if placingZone {
            Task { await placeZone(at: coord) }
            withAnimation { placingZone = false }
        } else if let zone = zoneService.zone(containing: coord) {
            select(zone)
        }
    }

    private func select(_ zone: PropertyZone) {
        HapticFeedback.impact(.light)
        selectedZone = zone
        focus(on: zone)
    }

    private func focus(on zone: PropertyZone) {
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(zone.region)
        }
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(
                center: propertyCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.0016, longitudeDelta: 0.0016)
            ))
        }
        HapticFeedback.selection()
    }

    private func placeZone(at coord: CLLocationCoordinate2D) async {
        guard let pid = propertyService.primary?.id else { return }
        if let created = await zoneService.createDefaultZone(propertyId: pid, center: coord) {
            HapticFeedback.success()
            select(created)
        }
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

private struct ObjectMarker: View {
    let element: PropertyElement
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: element.elementType.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(element.healthColor.opacity(0.95), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }
}

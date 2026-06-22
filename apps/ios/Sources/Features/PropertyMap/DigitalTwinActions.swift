import SwiftUI
import MapKit
import CoreLocation

extension DigitalTwinView {

    // MARK: - Styling

    func zoneFill(_ zone: PropertyZone) -> Color {
        switch zoneStyle {
        case .transparent:
            return .clear
        case .outlined:
            let base = heatmap ? zone.healthColor : zone.tint
            return base.opacity(zone.id == dragTargetZoneId ? 0.14 : 0.06)
        case .filled:
            let base = heatmap ? zone.healthColor : zone.tint
            let opacity: Double = zone.id == dragTargetZoneId ? 0.55
                : (selectedZone?.id == zone.id ? 0.45 : 0.26)
            return base.opacity(opacity)
        }
    }

    func zoneStroke(_ zone: PropertyZone) -> Color {
        guard zoneStyle != .transparent else { return .clear }
        let strokeOpacity: Double = zoneStyle == .outlined ? 0.95 : 0.9
        return (heatmap ? zone.healthColor : zone.tint).opacity(strokeOpacity)
    }

    // MARK: - Tap & Selection

    func handleTap(at coord: CLLocationCoordinate2D) {
        if editingShape { return }
        if drawMode {
            draftPoints.append(GeoPoint(lat: coord.latitude, lon: coord.longitude))
            HapticFeedback.selection()
        } else if let zone = zoneService.zone(containing: coord) {
            select(zone)
        }
    }

    func select(_ zone: PropertyZone) {
        HapticFeedback.impact(.light)
        selectedZone = zone
        focus(on: zone)
    }

    func focus(on zone: PropertyZone) {
        withAnimation(.easeInOut(duration: 0.7)) {
            if is3D {
                camera = .camera(MapCamera(centerCoordinate: zone.center, distance: 200, heading: 0, pitch: 60))
            } else {
                camera = .region(zone.region)
            }
        }
    }

    // MARK: - Reshape

    func startReshape(_ zone: PropertyZone) {
        reshapePoints = zone.polygon
        withAnimation { reshapeZone = zone }
        focus(on: zone)
        HapticFeedback.impact(.light)
    }

    func cancelReshape() {
        withAnimation { reshapeZone = nil }
        reshapePoints = []
    }

    func saveReshape() async {
        guard var zone = reshapeZone, reshapePoints.count >= 3 else { return }
        zone.polygon = reshapePoints
        await zoneService.update(zone)
        HapticFeedback.success()
        withAnimation { reshapeZone = nil }
        reshapePoints = []
    }

    var reshapeCenter: CLLocationCoordinate2D {
        guard !reshapePoints.isEmpty else { return propertyCoordinate }
        let lat = reshapePoints.map(\.lat).reduce(0, +) / Double(reshapePoints.count)
        let lon = reshapePoints.map(\.lon).reduce(0, +) / Double(reshapePoints.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Object Drag

    func objectCoord(_ obj: PropertyElement) -> CLLocationCoordinate2D {
        if let d = draggingObject, d.id == obj.id { return d.coord }
        return obj.coordinate ?? propertyCoordinate
    }

    func commitObjectDrag(_ obj: PropertyElement) async {
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

    // MARK: - Draw Zone

    func startDrawing() {
        HapticFeedback.impact(.light)
        selectedZone = nil
        draftPoints = []
        withAnimation { drawMode = true }
    }

    func cancelDrawing() {
        withAnimation { drawMode = false }
        draftPoints = []
    }

    func saveDrawnZone() async {
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
        if let created { editingZone = created }
    }

    // MARK: - Camera

    func recenter() {
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

    func toggle3D() {
        withAnimation(.spring(response: 0.3)) { is3D.toggle() }
        HapticFeedback.impact(.light)
        if let zone = selectedZone { focus(on: zone) } else { recenter() }
    }

    // MARK: - Data

    func loadData() async {
        guard let pid = propertyService.primary?.id else { return }
        await zoneService.load(propertyId: pid)
        if elementService.elements.isEmpty { await elementService.load(propertyId: pid) }
        if !didCenter {
            didCenter = true
            recenter()
        }
    }
}

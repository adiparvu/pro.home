import SwiftUI
import MapKit
import CoreLocation

/// Lets the user place an object on the satellite map. The tapped point is
/// saved as the object's coordinate and auto-assigned to the containing zone.
struct ObjectLocationPicker: View {
    let element: PropertyElement

    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var elementService: PropertyElementService
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition
    @State private var picked: CLLocationCoordinate2D?

    init(element: PropertyElement, propertyCenter: CLLocationCoordinate2D? = nil) {
        self.element = element
        _picked = State(initialValue: element.coordinate)
        let center = element.coordinate
            ?? propertyCenter
            ?? CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.0016, longitudeDelta: 0.0016)
        )))
    }

    private var pickedZone: PropertyZone? {
        guard let picked else { return nil }
        return zoneService.zone(containing: picked)
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(zoneService.zones) { zone in
                        if zone.isDrawable {
                            MapPolygon(coordinates: zone.coordinates)
                                .foregroundStyle(zone.tint.opacity(pickedZone?.id == zone.id ? 0.4 : 0.22))
                                .stroke(zone.tint.opacity(0.85), lineWidth: pickedZone?.id == zone.id ? 3 : 1.5)
                        }
                    }
                    if let picked {
                        Annotation("", coordinate: picked) {
                            Image(systemName: element.elementType.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(element.elementType.accentColor, in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .onTapGesture { location in
                    if let coord = proxy.convert(location, from: .local) {
                        withAnimation(.spring(response: 0.3)) { picked = coord }
                        HapticFeedback.selection()
                    }
                }
            }
            .overlay(alignment: .top) { hint }
            .overlay(alignment: .bottom) { saveBar }
            .navigationTitle("Place on map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var hint: some View {
        Group {
            if picked == nil {
                Text("Tap the map to place the object")
            } else if let zone = pickedZone {
                Text("In zone: \(zone.name)")
            } else {
                Text("Outside all zones")
            }
        }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .allowsHitTesting(false)
            .padding(.top, 12)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            Text("Save location")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(picked == nil ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.blue),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(picked == nil)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private func save() async {
        guard let picked else { return }
        await elementService.updateGeo(
            elementId: element.id,
            latitude: picked.latitude,
            longitude: picked.longitude,
            zoneId: pickedZone?.id
        )
        HapticFeedback.success()
        dismiss()
    }
}

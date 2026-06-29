import SwiftUI
import MapKit
import CoreLocation

// MARK: - Location Bubble

struct LocationBubble: View {
    let lat: Double
    let lon: Double
    let isOwn: Bool

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Marker("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                .tint(.blue)
        }
        .frame(width: 220, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            let q = "\(lat),\(lon)"
            if let url = URL(string: "maps://?q=\(q)&ll=\(q)") { UIApplication.shared.open(url) }
        }
    }
}

// MARK: - Location Share Sheet

struct LocationShareSheet: View {
    let onShare: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locMgr = LocationManager()

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    if let loc = locMgr.location {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: loc.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker("", coordinate: loc.coordinate)
                                .tint(.blue)
                        }
                        .frame(maxWidth: .infinity).frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)

                        Button {
                            onShare(loc.coordinate.latitude, loc.coordinate.longitude)
                            dismiss()
                        } label: {
                            Label("Share This Location", systemImage: "location.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing),
                                            in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)

                        Menu {
                            Button("15 minutes") { onShare(loc.coordinate.latitude, loc.coordinate.longitude); dismiss() }
                            Button("1 hour")     { onShare(loc.coordinate.latitude, loc.coordinate.longitude); dismiss() }
                            Button("8 hours")    { onShare(loc.coordinate.latitude, loc.coordinate.longitude); dismiss() }
                        } label: {
                            Label("Share live location", systemImage: "location.circle.fill")
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .liquidGlass(cornerRadius: 14)
                        }
                        .padding(.horizontal, 20)

                        Text("Live updates require continuous background location (coming soon); for now your current location is shared.")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    } else {
                        Spacer()
                        ProgressView().tint(.white)
                        Text(LocalizedStringKey(locMgr.denied ? "Location access denied. Enable in Settings." : "Getting your location…"))
                            .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.5))
                        Spacer()
                    }
                }
                .padding(.top, 16)
            }
            .navigationTitle("Share Location").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
            }
        }
        .task { locMgr.requestLocation() }
    }
}

// MARK: - Mention Picker Sheet

struct MentionPickerSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Binding var selectedIds: [String]
    @Binding var selectedNames: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        MemberPickerView(selectedIds: $selectedIds, selectedNames: $selectedNames)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Mention").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Location Manager

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var denied = false
    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        let status = mgr.authorizationStatus
        if status == .notDetermined { mgr.requestWhenInUseAuthorization() }
        else if status == .denied { denied = true }
        else { mgr.requestLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied { denied = true }
        else if manager.authorizationStatus != .notDetermined { mgr.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

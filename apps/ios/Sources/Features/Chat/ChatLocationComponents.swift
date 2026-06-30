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
    var propertyId: UUID? = nil
    var myName: String = ""
    let onShare: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locMgr = LocationManager()
    @ObservedObject private var live = LiveLocationService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    if let loc = locMgr.location {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: loc.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker("Me", coordinate: loc.coordinate).tint(.blue)
                            ForEach(live.othersSharing) { s in
                                Marker(s.userName, systemImage: "dot.radiowaves.left.and.right", coordinate: s.coordinate)
                                    .tint(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)

                        if !live.othersSharing.isEmpty {
                            Text(live.othersSharing.count == 1
                                 ? String(format: String(localized: "%@ is sharing live location"), live.othersSharing[0].userName)
                                 : String(format: String(localized: "%d people are sharing live location"), live.othersSharing.count))
                                .font(.system(size: 12)).foregroundStyle(.orange)
                        }

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

                        if live.isSharing {
                            VStack(spacing: 6) {
                                Button(role: .destructive) { live.stop() } label: {
                                    Label("Stop sharing live location", systemImage: "location.slash.fill")
                                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.red)
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .liquidGlass(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                                if let exp = live.sharingExpiresAt {
                                    Text("Sharing live until \(exp, style: .time)")
                                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            Menu {
                                Button("15 minutes") { startLive(900) }
                                Button("1 hour")     { startLive(3600) }
                                Button("8 hours")    { startLive(28800) }
                            } label: {
                                Label("Share live location", systemImage: "location.circle.fill")
                                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .liquidGlass(cornerRadius: 14)
                            }
                            .padding(.horizontal, 20)
                            .disabled(propertyId == nil)
                        }

                        Text("Live location updates while the app is open. Continuous background updates require the Always location permission.")
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
        .task(id: propertyId) {
            guard let pid = propertyId else { return }
            while !Task.isCancelled {
                await live.load(propertyId: pid)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func startLive(_ duration: TimeInterval) {
        guard let pid = propertyId else { return }
        live.start(propertyId: pid, userName: myName, duration: duration)
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

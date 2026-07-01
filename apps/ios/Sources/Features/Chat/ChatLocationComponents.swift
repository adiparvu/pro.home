import SwiftUI
import MapKit
import CoreLocation

// MARK: - Navigation app hand-off (Hărți / Hărți Google / Waze)

/// Launches turn-by-turn directions to a coordinate in the user's choice of
/// installed navigation app. Apple Maps is always offered; Google Maps and
/// Waze only appear when actually installed (checked via canOpenURL, which
/// requires their schemes in LSApplicationQueriesSchemes).
enum NavigationAppLauncher {
    struct Option: Identifiable { let id: String; let label: String }

    static func availableOptions() -> [Option] {
        var opts = [Option(id: "apple", label: String(localized: "Hărți"))]
        if canOpen("comgooglemaps://") { opts.append(Option(id: "google", label: String(localized: "Hărți Google"))) }
        if canOpen("waze://") { opts.append(Option(id: "waze", label: "Waze")) }
        return opts
    }

    private static func canOpen(_ scheme: String) -> Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens directions to (lat, lon) in the chosen app. `label` names the
    /// destination (e.g. the sender's name) in Apple Maps' pin/callout.
    static func open(_ optionId: String, lat: Double, lon: Double, label: String) {
        let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        let url: URL?
        switch optionId {
        case "google":
            url = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")
        case "waze":
            url = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")
        default:
            // daddr= (directions to) triggers Apple Maps' driving-ETA callout,
            // matching the native "car icon + N minutes" preview.
            url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&q=\(encodedLabel)")
        }
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Location Bubble

struct LocationBubble: View {
    let lat: Double
    let lon: Double
    let isOwn: Bool
    var label: String = ""

    @State private var showAppChooser = false

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
        .overlay(alignment: .bottomLeading) {
            // Car/ETA-style badge — tapping it (or the map) offers a choice of
            // navigation app, then hands off with turn-by-turn directions.
            Image(systemName: "car.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.accentColor, in: Circle())
                .padding(8)
        }
        .onTapGesture { showAppChooser = true }
        .confirmationDialog("Alege aplicația", isPresented: $showAppChooser, titleVisibility: .visible) {
            ForEach(NavigationAppLauncher.availableOptions()) { opt in
                Button(opt.label) {
                    NavigationAppLauncher.open(opt.id, lat: lat, lon: lon, label: label.isEmpty ? "Location" : label)
                }
            }
        }
    }
}

// MARK: - Address search (live suggestions as you type)

final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        guard !query.isEmpty else { results = []; return }
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        await withCheckedContinuation { cont in
            let request = MKLocalSearch.Request(completion: completion)
            MKLocalSearch(request: request).start { response, _ in
                cont.resume(returning: response?.mapItems.first)
            }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Nearby places (no query needed — points of interest around a coordinate)

@MainActor
final class NearbyPlacesFinder: ObservableObject {
    @Published var places: [MKMapItem] = []

    func search(around coordinate: CLLocationCoordinate2D) {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 800)
        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let response else { return }
            Task { @MainActor in self?.places = Array(response.mapItems.prefix(6)) }
        }
    }
}

// MARK: - Location Share Sheet
//
// Styled after the native iOS "Trimitere locație" (Send Location) picker: a
// search bar for addresses, the current-location map, a prominent live-share
// row, and a "Locuri din apropiere" (nearby places) list.

struct LocationShareSheet: View {
    var propertyId: UUID? = nil
    var myName: String = ""
    let onShare: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locMgr = LocationManager()
    @ObservedObject private var live = LiveLocationService.shared
    @StateObject private var completer = AddressSearchCompleter()
    @StateObject private var nearby = NearbyPlacesFinder()

    @State private var searchText = ""
    /// A place picked from search or the nearby list; nil = share current location.
    @State private var pickedPlace: MKMapItem?

    private var mapCenter: CLLocationCoordinate2D? {
        pickedPlace?.placemark.coordinate ?? locMgr.location?.coordinate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                    if let center = mapCenter {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: center,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker(pickedPlace?.name ?? "Me", coordinate: center).tint(.blue)
                            ForEach(live.othersSharing) { s in
                                Marker(s.userName, systemImage: "dot.radiowaves.left.and.right", coordinate: s.coordinate)
                                    .tint(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 260)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if !completer.results.isEmpty {
                                    searchResultsList
                                } else {
                                    if !live.othersSharing.isEmpty {
                                        Text(live.othersSharing.count == 1
                                             ? String(format: String(localized: "%@ is sharing live location"), live.othersSharing[0].userName)
                                             : String(format: String(localized: "%d people are sharing live location"), live.othersSharing.count))
                                            .font(.system(size: 12)).foregroundStyle(.orange)
                                    }
                                    liveShareRow
                                    nearbyPlacesSection
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 30)
                        }
                    } else {
                        Spacer()
                        ProgressView().tint(.white)
                        Text(LocalizedStringKey(locMgr.denied ? "Location access denied. Enable in Settings." : "Getting your location…"))
                            .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.5))
                        Spacer()
                    }
                }
            }
            .navigationTitle("Trimitere locație").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary.opacity(0.7)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { locMgr.requestLocation() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task {
            locMgr.onLocation = { [weak nearby] loc in nearby?.search(around: loc.coordinate) }
            locMgr.requestLocation()
        }
        .task(id: propertyId) {
            guard let pid = propertyId else { return }
            while !Task.isCancelled {
                await live.load(propertyId: pid)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onChange(of: searchText) { _, text in completer.update(query: text) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.primary.opacity(0.4))
            TextField("Caută sau introdu o adresă", text: $searchText)
                .font(.system(size: 15))
            if !searchText.isEmpty {
                Button { searchText = ""; pickedPlace = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(completer.results.enumerated()), id: \.offset) { _, r in
                Button {
                    Task {
                        if let item = await completer.resolve(r) {
                            pickedPlace = item
                            searchText = r.title
                            completer.results = []
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                        if !r.subtitle.isEmpty {
                            Text(r.subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
    }

    private var liveShareRow: some View {
        Group {
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
            } else {
                Menu {
                    Button("15 minutes") { startLive(900) }
                    Button("1 hour")     { startLive(3600) }
                    Button("8 hours")    { startLive(28800) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.circle.fill").font(.system(size: 18))
                        Text("Distribuie locația în timp real").font(.system(size: 15, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).padding(.horizontal, 14)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(propertyId == nil)
            }
        }
    }

    private var nearbyPlacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Locuri din apropiere")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))

            Button {
                pickedPlace = nil
                if let loc = locMgr.location {
                    onShare(loc.coordinate.latitude, loc.coordinate.longitude)
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trimite locația curentă").font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                        if let acc = locMgr.location?.horizontalAccuracy, acc > 0 {
                            Text("Cu o aproximație de \(Int(acc))m")
                                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            Divider().opacity(0.3)

            ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, item in
                Button {
                    pickedPlace = item
                    onShare(item.placemark.coordinate.latitude, item.placemark.coordinate.longitude)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(Color.primary.opacity(0.4))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? "").font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                            if let addr = item.placemark.title {
                                Text(addr).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5)).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
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
    /// Fires once a location arrives. CLLocation isn't Equatable, so callers
    /// that need to react to updates (e.g. nearby-places search) hook this
    /// instead of using SwiftUI's onChange(of:).
    var onLocation: ((CLLocation) -> Void)?
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
        guard let loc = location else { return }
        let callback = onLocation
        Task { @MainActor in callback?(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

import SwiftUI
import Observation
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
        // Always offer all three — when the app isn't installed we fall back
        // to its universal link (which routes to web or the App Store).
        [Option(id: "apple",  label: String(localized: "Hărți")),
         Option(id: "google", label: String(localized: "Hărți Google")),
         Option(id: "waze",   label: "Waze")]
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
            url = canOpen("comgooglemaps://")
                ? URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")
                : URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)")
        case "waze":
            url = canOpen("waze://")
                ? URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")
                : URL(string: "https://waze.com/ul?ll=\(lat),\(lon)&navigate=yes")
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
    var hasTail: Bool = true
    var senderId: UUID? = nil

    @State private var showDetail = false

    /// The sender's ACTIVE live share, if any — turns this bubble into the
    /// WhatsApp-style live variant that follows their position.
    private var liveRow: LiveLocation? {
        LiveLocationService.shared.active.first {
            ($0.userId == senderId || $0.userName == label)
                && ($0.expiresDate ?? .distantPast) > Date()
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        liveRow?.coordinate ?? CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        let live = liveRow
        VStack(spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Annotation("", coordinate: coordinate) {
                    ChatMapAvatar(name: label, senderId: senderId, size: live != nil ? 38 : 30)
                }
            }
            .frame(width: 220, height: live != nil ? 120 : 140)
            .id(live?.updatedAt)
            .allowsHitTesting(false)

            if let live {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.brandSuccess)
                        if let end = live.expiresDate {
                            Text("Se distribuie până la \(end, style: .time)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                    if isOwn {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                        Button {
                            HapticFeedback.impact(.medium)
                            LiveLocationService.shared.stop()
                        } label: {
                            Text("Oprește distribuirea")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.brandDanger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 220)
                .background(.thinMaterial)
            }
        }
        .clipShape(ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
        .overlay(alignment: .topLeading) {
            if live == nil {
                Image(systemName: "car.fill")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.white)
                    .padding(AppSpacing.sm)
                    .background(Color.accentColor, in: Circle())
                    .padding(AppSpacing.sm)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        // Collapse the map + badge into one VoiceOver stop — otherwise it exposes
        // MapKit's own complex accessibility tree, which reads poorly here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? Text("Shared location") : Text(label))
        .accessibilityHint("Choose a navigation app to get directions")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showDetail) {
            LocationDetailSheet(lat: lat, lon: lon, label: label, isOwn: isOwn, senderId: senderId)
        }
    }
}

// MARK: - Map avatar marker

/// Sender avatar rendered as a map marker (photo when the member directory
/// has one, initials otherwise) — the WhatsApp live-location look.
struct ChatMapAvatar: View {
    let name: String
    let senderId: UUID?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            if let id = senderId, let url = MemberDirectory.shared.avatarURL(for: id) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.85))
            Text(String(name.prefix(2)).uppercased())
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Full-screen location detail (live map + navigation hand-off)

struct LocationDetailSheet: View {
    let lat: Double
    let lon: Double
    let label: String
    let isOwn: Bool
    var senderId: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    private var liveRow: LiveLocation? {
        LiveLocationService.shared.active.first {
            ($0.userId == senderId || $0.userName == label)
                && ($0.expiresDate ?? .distantPast) > Date()
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        liveRow?.coordinate ?? CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                ))) {
                    Annotation(isOwn ? String(localized: "Tu") : label, coordinate: coordinate) {
                        ChatMapAvatar(name: label, senderId: senderId, size: 46)
                    }
                }
                .id(liveRow?.updatedAt)
                .ignoresSafeArea(edges: .bottom)

                bottomCard
            }
            .navigationTitle(liveRow != nil ? String(localized: "Locație în timp real")
                                            : String(localized: "Locație"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            // Follow the sharer while the sheet is open.
            while !Task.isCancelled {
                await LiveLocationService.shared.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var bottomCard: some View {
        VStack(spacing: 12) {
            if let live = liveRow {
                HStack(spacing: 12) {
                    ChatMapAvatar(name: label, senderId: senderId, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isOwn ? String(localized: "Tu") : label)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text(String(format: String(localized: "Timp rămas: %d min"), live.minutesLeft))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    if isOwn {
                        Button {
                            HapticFeedback.impact(.medium)
                            LiveLocationService.shared.stop()
                            dismiss()
                        } label: {
                            Text("Oprește distribuirea")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.brandDanger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: AppSpacing.sm) {
                ForEach(NavigationAppLauncher.availableOptions()) { opt in
                    Button {
                        NavigationAppLauncher.open(opt.id, lat: coordinate.latitude,
                                                   lon: coordinate.longitude,
                                                   label: label.isEmpty ? "Location" : label)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.system(size: 13))
                            Text(opt.label)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(AppSpacing.lg)
    }
}

// MARK: - Address search (live suggestions as you type)

@Observable
final class AddressSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
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
@Observable
final class NearbyPlacesFinder {
    var places: [MKMapItem] = []

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
    @State private var locMgr = LocationManager()
    private let live = LiveLocationService.shared
    @State private var completer = AddressSearchCompleter()
    @State private var nearby = NearbyPlacesFinder()

    @State private var searchText = ""
    @State private var pendingLiveDuration: TimeInterval? = nil
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
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.top, AppSpacing.base)
                            .padding(.bottom, 30)
                        }
                    } else {
                        Spacer()
                        ProgressView().tint(.white)
                        Text(LocalizedStringKey(locMgr.denied ? "Location access denied. Enable in Settings." : "Getting your location…"))
                            .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                    }
                }
            }
            .navigationTitle("Trimitere locație").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { locMgr.requestLocation() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh location")
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
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
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
                        Text(r.title).font(AppFont.body).foregroundStyle(.primary)
                        if !r.subtitle.isEmpty {
                            Text(r.subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                            .font(AppFont.body).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .liquidGlass(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    if let exp = live.sharingExpiresAt {
                        Text("Sharing live until \(exp, style: .time)")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
            } else {
                Menu {
                    Button("15 minutes") { pendingLiveDuration = 900 }
                    Button("1 hour")     { pendingLiveDuration = 3600 }
                    Button("8 hours")    { pendingLiveDuration = 28800 }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.circle.fill").font(.system(size: 18))
                        Text("Distribuie locația în timp real").font(AppFont.body)
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).padding(.horizontal, AppSpacing.base)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(propertyId == nil)
            }
        }
        // WhatsApp-style consent alert before the live share actually starts.
        .alert("Distribuie locația în timp real", isPresented: Binding(
            get: { pendingLiveDuration != nil },
            set: { if !$0 { pendingLiveDuration = nil } }
        )) {
            Button("Anulează", role: .cancel) { pendingLiveDuration = nil }
            Button("OK") {
                if let d = pendingLiveDuration { startLive(d) }
                pendingLiveDuration = nil
            }
        } message: {
            Text("People in this conversation will see your live location for the selected period. You can stop sharing at any time.")
        }
    }

    private var nearbyPlacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Locuri din apropiere")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))

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
                        Text("Trimite locația curentă").font(AppFont.body).foregroundStyle(.primary)
                        if let acc = locMgr.location?.horizontalAccuracy, acc > 0 {
                            Text("Cu o aproximație de \(Int(acc))m")
                                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                            Text(item.name ?? "").font(AppFont.body).foregroundStyle(.primary)
                            if let addr = item.placemark.title {
                                Text(addr).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText)).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.sm)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
    }

    private func startLive(_ duration: TimeInterval) {
        guard let pid = propertyId else { return }
        live.start(propertyId: pid, userName: myName, duration: duration)
        // The share must be visible in the conversation: drop the current
        // coordinate into the chat immediately, then close the sheet — the
        // live marker keeps updating via LiveLocationService.
        if let loc = locMgr.location {
            onShare(loc.coordinate.latitude, loc.coordinate.longitude)
        }
        dismiss()
    }
}

// MARK: - Mention Picker Sheet

struct MentionPickerSheet: View {
    @Environment(FamilyService.self) private var familyService
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
                            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                    }
                }
            }
            .navigationTitle("Mention").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Location Manager

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    var denied = false
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

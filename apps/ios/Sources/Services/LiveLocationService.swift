import SwiftUI
import Observation
import CoreLocation
import Supabase

// MARK: - Live location model

struct LiveLocation: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    let userId: UUID
    let userName: String
    let lat: Double
    let lon: Double
    let startedAt: String
    let expiresAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, lat, lon
        case propertyId = "property_id"
        case userId     = "user_id"
        case userName   = "user_name"
        case startedAt  = "started_at"
        case expiresAt  = "expires_at"
        case updatedAt  = "updated_at"
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var expiresDate: Date? { ISODate.date(from: expiresAt) }

    /// Whole minutes until the share ends (never negative).
    var minutesLeft: Int {
        guard let end = expiresDate else { return 0 }
        return max(0, Int(end.timeIntervalSinceNow / 60))
    }
}

// MARK: - Live location service (singleton)
//
// Foreground real-time sharing: while sharing is on, the device pushes its
// coordinate (on movement) to live_locations until the chosen window expires.
// Members see each other's markers via load + realtime. Continuous *background*
// updates additionally require the "Always" location permission.

@MainActor
@Observable
final class LiveLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LiveLocationService()

    var active: [LiveLocation] = []
    var isSharing = false
    private(set) var sharingExpiresAt: Date?

    private let mgr = CLLocationManager()
    private var propertyId: UUID?
    private var userName = ""

    private var uid: UUID? { supabase.auth.currentSession?.user.id }

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        mgr.distanceFilter = 25
        mgr.pausesLocationUpdatesAutomatically = false
    }

    /// Background delivery keeps the share alive with the app closed — legal
    /// only with the `location` background mode (declared in Info.plist) AND
    /// an authorization that permits it, otherwise CoreLocation traps.
    private func configureBackgroundUpdates() {
        let status = mgr.authorizationStatus
        let canBackground = status == .authorizedAlways
        mgr.allowsBackgroundLocationUpdates = canBackground
        if canBackground {
            mgr.showsBackgroundLocationIndicator = true
        }
    }

    // MARK: Sharing

    func start(propertyId: UUID, userName: String, duration: TimeInterval) {
        self.propertyId = propertyId
        self.userName = userName
        sharingExpiresAt = Date().addingTimeInterval(duration)
        isSharing = true
        switch mgr.authorizationStatus {
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Upgrade prompt so sharing survives backgrounding, WhatsApp-style.
            mgr.requestAlwaysAuthorization()
        default:
            break
        }
        configureBackgroundUpdates()
        mgr.startUpdatingLocation()
        HapticFeedback.success()
    }

    func stop() {
        isSharing = false
        sharingExpiresAt = nil
        mgr.allowsBackgroundLocationUpdates = false
        mgr.stopUpdatingLocation()
        guard let pid = propertyId, let uid else { return }
        Task {
            _ = try? await supabase.from("live_locations").delete()
                .eq("property_id", value: pid.uuidString)
                .eq("user_id", value: uid.uuidString)
                .execute()
            await load(propertyId: pid)
        }
    }

    // MARK: Loading

    func load(propertyId: UUID) async {
        self.propertyId = propertyId
        let nowISO = ISO8601DateFormatter().string(from: Date())
        guard let rows: [LiveLocation] = try? await supabase
            .from("live_locations")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .gt("expires_at", value: nowISO)
            .execute().value
        else { return }
        active = rows
    }

    var othersSharing: [LiveLocation] { active.filter { $0.userId != uid } }

    /// Re-fetches using the last known property — for views that follow a
    /// share without knowing which property it belongs to.
    func refresh() async {
        guard let pid = propertyId else { return }
        await load(propertyId: pid)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let lat = last.coordinate.latitude
        let lon = last.coordinate.longitude
        Task { @MainActor in await self.push(lat: lat, lon: lon) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.configureBackgroundUpdates()
            if self.isSharing { self.mgr.startUpdatingLocation() }
        }
    }

    private func push(lat: Double, lon: Double) async {
        guard isSharing, let pid = propertyId, let uid, let exp = sharingExpiresAt else { return }
        if Date() > exp { stop(); return }
        struct Payload: Encodable {
            let property_id: String
            let user_id: String
            let user_name: String
            let lat: Double
            let lon: Double
            let expires_at: String
            let updated_at: String
        }
        let p = Payload(
            property_id: pid.uuidString, user_id: uid.uuidString, user_name: userName,
            lat: lat, lon: lon,
            expires_at: ISO8601DateFormatter().string(from: exp),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        _ = try? await supabase.from("live_locations").upsert(p, onConflict: "property_id,user_id").execute()
        await load(propertyId: pid)
    }
}

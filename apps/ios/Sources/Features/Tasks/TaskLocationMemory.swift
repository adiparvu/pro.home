import Foundation
import CoreLocation
import MapKit
import Observation

// MARK: - Remembered task locations (personal, per device)
//
// Every location the user actually picks in the task location sheet is
// remembered here — a personal shortcut list, deliberately keyed per device
// (UserDefaults) and not per property, mirroring RecentAssigneeNames in
// AssigneePickerSheet. The sheet surfaces the list as "Frecvente" (most
// picked) and "Recente" (most recently picked) before any search query.

struct RememberedTaskLocation: Codable, Equatable, Identifiable {
    var name: String
    var lat: Double?
    var lon: Double?
    var pickCount: Int
    var lastUsedAt: Date

    /// Identity is the case-folded name — picking "Hornbach" twice must
    /// increment one entry, not create "hornbach" next to "Hornbach".
    var id: String { Self.key(for: name) }

    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var value: TaskLocationValue { TaskLocationValue(name: name, lat: lat, lon: lon) }
}

enum TaskLocationMemory {
    private static let storageKey = "task.location.recentPicks"
    private static let capacity = 50
    /// "Frecvente" is only honest for places picked more than once — a
    /// single pick is merely recent.
    private static let frequentThreshold = 2

    // MARK: Persistence (UserDefaults JSON blob, capped)

    static func load() -> [RememberedTaskLocation] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RememberedTaskLocation].self, from: data)) ?? []
    }

    private static func save(_ list: [RememberedTaskLocation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: Recording picks

    /// Records a pick: bumps the existing entry (count + recency) or appends
    /// a new one, evicting the least recently used past the cap.
    @discardableResult
    static func remember(_ value: TaskLocationValue) -> [RememberedTaskLocation] {
        let trimmed = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        var list = load()
        let key = RememberedTaskLocation.key(for: trimmed)
        if let index = list.firstIndex(where: { $0.id == key }) {
            var item = list[index]
            item.pickCount += 1
            item.lastUsedAt = Date()
            // A real map pick upgrades a coordinate-less memory of the same
            // place; a later free-text pick never strips known coordinates.
            if value.lat != nil, value.lon != nil {
                item.name = trimmed
                item.lat = value.lat
                item.lon = value.lon
            }
            list[index] = item
        } else {
            list.append(RememberedTaskLocation(name: trimmed, lat: value.lat, lon: value.lon,
                                               pickCount: 1, lastUsedAt: Date()))
        }
        if list.count > capacity {
            list.sort { $0.lastUsedAt > $1.lastUsedAt }
            list = Array(list.prefix(capacity))
        }
        save(list)
        return list
    }

    @discardableResult
    static func forget(id: String) -> [RememberedTaskLocation] {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
        return list
    }

    // MARK: Presentation split

    /// "Frecvente" = top picks by count (picked at least twice, max 5);
    /// "Recente" = everything else by recency (max 8). Disjoint by design so
    /// a favorite never shows twice.
    static func sections(of list: [RememberedTaskLocation])
        -> (frequent: [RememberedTaskLocation], recent: [RememberedTaskLocation]) {
        let frequent = list
            .filter { $0.pickCount >= frequentThreshold }
            .sorted {
                $0.pickCount != $1.pickCount ? $0.pickCount > $1.pickCount
                                             : $0.lastUsedAt > $1.lastUsedAt
            }
            .prefix(5)
        let frequentIds = Set(frequent.map(\.id))
        let recent = list
            .filter { !frequentIds.contains($0.id) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(8)
        return (Array(frequent), Array(recent))
    }
}

// MARK: - Nearby places for the task location sheet
//
// Suggests common errand stops (supermarket, pharmacy, gas station, retail —
// hardware stores fall under MapKit's generic `.store` on this deployment
// target) around the user's position. Honesty rules: it only runs when the
// app ALREADY holds location permission — this sheet never prompts — and the
// section only renders when results actually exist.

@MainActor
@Observable
final class TaskNearbyPlacesModel: NSObject, CLLocationManagerDelegate {
    private(set) var places: [MKMapItem] = []

    @ObservationIgnored private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return m
    }()
    @ObservationIgnored private var started = false

    /// One-shot: fetches the current position only if permission was already
    /// granted elsewhere in the app (chat location share, live sharing).
    /// `.notDetermined`/`.denied` mean the section silently stays absent.
    func startIfAuthorized() {
        guard !started else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        started = true
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in await self?.search(around: coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {}

    private func search(around coordinate: CLLocationCoordinate2D) async {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 1200)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .foodMarket, .pharmacy, .gasStation, .store,
        ])
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        places = Array(response.mapItems.filter { $0.name?.isEmpty == false }.prefix(6))
    }
}

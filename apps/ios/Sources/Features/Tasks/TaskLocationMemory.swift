import Foundation
import CoreLocation
import MapKit
import Observation

// MARK: - Remembered task locations (personal, per device)
//
// Every location the user actually picks in the task location sheet is
// remembered here — a personal shortcut list, deliberately keyed per device
// (UserDefaults) and not per property, mirroring RecentAssigneeNames in
// AssigneePickerSheet. The sheet surfaces the list as "Favorite" (user-pinned
// stars), "Frecvente" (most picked) and "Recente" (most recently picked)
// before any search query.

struct RememberedTaskLocation: Codable, Equatable, Identifiable {
    var name: String
    var lat: Double?
    var lon: Double?
    var pickCount: Int
    var lastUsedAt: Date
    /// User-pinned star. Favorites render in their own section, stay out of
    /// Frecvente/Recente, and are never evicted by the LRU cap.
    var isFavorite: Bool = false

    /// Identity is the case-folded name — picking "Hornbach" twice must
    /// increment one entry, not create "hornbach" next to "Hornbach".
    var id: String { Self.key(for: name) }

    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var value: TaskLocationValue { TaskLocationValue(name: name, lat: lat, lon: lon) }

    private enum CodingKeys: String, CodingKey {
        case name, lat, lon, pickCount, lastUsedAt, isFavorite
    }
}

extension RememberedTaskLocation {
    /// Tolerant decoding: `isFavorite` was added after blobs were already in
    /// the wild, and a Swift property default does NOT make synthesized
    /// Codable lenient — old JSON without the key must keep decoding.
    /// (Defined in an extension so the memberwise initializer survives.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name       = try c.decode(String.self, forKey: .name)
        lat        = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon        = try c.decodeIfPresent(Double.self, forKey: .lon)
        pickCount  = try c.decode(Int.self, forKey: .pickCount)
        lastUsedAt = try c.decode(Date.self, forKey: .lastUsedAt)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
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
            // Favorites are pinned — the LRU cap only ever evicts unpinned
            // entries, so a starred place survives any amount of new picks.
            let pinned = list.filter(\.isFavorite)
            let others = list.filter { !$0.isFavorite }
                .sorted { $0.lastUsedAt > $1.lastUsedAt }
            list = pinned + others.prefix(max(0, capacity - pinned.count))
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

    /// Stars/unstars a remembered place in storage and returns the new list.
    @discardableResult
    static func toggleFavorite(id: String) -> [RememberedTaskLocation] {
        var list = load()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return list }
        list[index].isFavorite.toggle()
        save(list)
        return list
    }

    // MARK: Presentation split

    /// "Favorite" = user-pinned stars, by recency; "Frecvente" = top unpinned
    /// picks by count (picked at least twice, max 5); "Recente" = the rest by
    /// recency (max 8). The three are disjoint by design so a place never
    /// shows twice.
    static func sections(of list: [RememberedTaskLocation])
        -> (favorites: [RememberedTaskLocation],
            frequent: [RememberedTaskLocation],
            recent: [RememberedTaskLocation]) {
        let favorites = list
            .filter(\.isFavorite)
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        let unpinned = list.filter { !$0.isFavorite }
        let frequent = unpinned
            .filter { $0.pickCount >= frequentThreshold }
            .sorted {
                $0.pickCount != $1.pickCount ? $0.pickCount > $1.pickCount
                                             : $0.lastUsedAt > $1.lastUsedAt
            }
            .prefix(5)
        let frequentIds = Set(frequent.map(\.id))
        let recent = unpinned
            .filter { !frequentIds.contains($0.id) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(8)
        return (favorites, Array(frequent), Array(recent))
    }
}

// MARK: - Current position + nearby places for the task location sheet
//
// Suggests common errand stops (supermarket, pharmacy, gas station, retail —
// hardware stores fall under MapKit's generic `.store` on this deployment
// target) around the user's position. Honesty rules: the sheet never prompts
// for permission on its own — the system dialog appears only when the user
// taps "Folosește poziția mea" while status is .notDetermined (the one moment
// a prompt is exactly what they asked for). Denied/restricted is surfaced to
// the sheet so it can render the "open Settings" row instead of silence.

@MainActor
@Observable
final class TaskNearbyPlacesModel: NSObject, CLLocationManagerDelegate {
    private(set) var places: [MKMapItem] = []
    /// Mirror of CLLocationManager's status, kept observable so the sheet's
    /// rows can honestly track the request → grant/deny transition live.
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// The latest fix, cached so a "Folosește poziția mea" tap after the
    /// nearby fetch resolves instantly.
    private(set) var currentLocation: CLLocation?
    /// True while a "use my position" tap is waiting on the permission dialog
    /// and/or the first fix — drives the row's inline spinner.
    private(set) var isLocating = false

    @ObservationIgnored private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return m
    }()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var fixInFlight = false
    /// Completion for the pending "use my position" tap. nil result means the
    /// position could not be resolved (denied or fix failure) — never a fake.
    @ObservationIgnored private var onFix: ((CLLocation?) -> Void)?

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Called when the sheet appears: reads the status and, when permission
    /// already exists, fetches one fix to feed the "În apropiere" section.
    /// Never prompts.
    func start() {
        guard !started else { return }
        started = true
        authorization = manager.authorizationStatus
        if isAuthorized { requestFix() }
    }

    /// The "Folosește poziția mea" tap. `.notDetermined` triggers the system
    /// whenInUse dialog — a grant continues into a one-shot fix, a deny calls
    /// back with nil (and `isDenied` flips the row to the Settings state).
    func useMyPosition(completion: @escaping (CLLocation?) -> Void) {
        if let location = currentLocation {
            completion(location)
            return
        }
        onFix = completion
        isLocating = true
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestFix()
        default:
            resolvePendingFix(with: nil)
        }
    }

    private func requestFix() {
        guard !fixInFlight else { return }
        fixInFlight = true
        manager.requestLocation()
    }

    private func resolvePendingFix(with location: CLLocation?) {
        isLocating = false
        guard let pending = onFix else { return }
        onFix = nil
        pending(location)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            if self.isAuthorized {
                if self.currentLocation == nil { self.requestFix() }
            } else if self.isDenied {
                // The user answered the dialog with "Don't Allow" (or Screen
                // Time restricts it) — fail the pending tap honestly.
                self.resolvePendingFix(with: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.fixInFlight = false
            self.currentLocation = location
            self.resolvePendingFix(with: location)
            await self.search(around: location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.fixInFlight = false
            self.resolvePendingFix(with: nil)
        }
    }

    private func search(around coordinate: CLLocationCoordinate2D) async {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 1200)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .foodMarket, .pharmacy, .gasStation, .store,
        ])
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        places = Array(response.mapItems.filter { $0.name?.isEmpty == false }.prefix(6))
    }
}

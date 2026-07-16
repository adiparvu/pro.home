import Foundation
import CoreLocation
import Observation
import Supabase

// MARK: - Home presence — the geofenced "who's home" truth (wave 3B)
//
// One CLCircularRegion (~150 m) around the property's stored coordinates,
// region monitoring ONLY — no continuous location updates, that's the
// battery contract. Strictly opt-in (`homePresence.share`, default OFF,
// mirroring the chat presence toggle); arming further requires real
// coordinates and Always authorization, and every degradation is stated in
// UI copy, never guessed. Opting out DELETES the member's own state row.
//
// Region transitions arrive even when iOS relaunches the app in the
// background; the handler does exactly two PostgREST writes (state upsert +
// event insert) and nothing else — "background = silence" stays intact.
// The household's live state streams over realtime (migration 160) in the
// foreground only; `recentEvents` feeds the house timeline on demand, and
// `lastTransition` is the rules engine's geofence signal.

struct HomePresenceRow: Codable, Identifiable {
    let propertyId: UUID
    let userId: UUID
    let userName: String
    let isHome: Bool
    let since: String
    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case userId     = "user_id"
        case userName   = "user_name"
        case isHome     = "is_home"
        case since
    }

    var sinceDate: Date? { AppDate.timestamp(from: since) }
}

struct HomePresenceEvent: Codable, Identifiable {
    let id: UUID
    let userName: String
    let event: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, event
        case userName  = "user_name"
        case createdAt = "created_at"
    }
}

@MainActor
@Observable
final class HomePresenceService: NSObject, CLLocationManagerDelegate {
    /// Singleton: the delegate must exist the moment iOS relaunches the app
    /// for a region event, before any view hierarchy is up.
    static let shared = HomePresenceService()

    enum Transition: String { case arrive, leave }

    /// The opt-in switch (Settings), default OFF — privacy first.
    static let shareKey = "homePresence.share"

    /// The most recent geofence transition observed on THIS device — the
    /// rules engine's geofence condition reads it (10-minute freshness).
    private(set) var lastTransition: (kind: Transition, at: Date)?
    /// The household's live states (everyone who opted in).
    private(set) var household: [HomePresenceRow] = []
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var pgSubs: [RealtimeSubscription] = []
    /// Region-state seed: `didDetermineState` fires right after arming with
    /// the CURRENT state — that seeds the state row silently (no event; the
    /// user didn't move, we just started looking).
    @ObservationIgnored private var seededRegionIds: Set<String> = []

    private static let regionIdentifier = "com.prvio.home-presence"
    private static let radius: CLLocationDistance = 150
    // A background relaunch delivers the region event before any world load
    // runs — the write context must survive the process, not the session.
    private static let propertyKey = "homePresence.propertyId"
    private static let nameKey = "homePresence.userName"
    private static let latKey = "homePresence.lat"
    private static let lonKey = "homePresence.lon"

    private override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    // MARK: Derived state

    var sharing: Bool { UserDefaults.standard.bool(forKey: Self.shareKey) }

    var hasCoordinates: Bool {
        UserDefaults.standard.object(forKey: Self.latKey) != nil
    }

    /// True only when monitoring is genuinely running: opted in, a real
    /// region center, and Always authorization.
    var isArmed: Bool {
        sharing && hasCoordinates && authorization == .authorizedAlways
    }

    private var propertyId: UUID? {
        UserDefaults.standard.string(forKey: Self.propertyKey).flatMap(UUID.init)
    }

    // MARK: Configure / opt-in

    /// Points the geofence at the primary property. Called from reloadWorld
    /// phase 3; a property switch re-arms around the new home.
    func configure(propertyId: UUID?, latitude: Double?, longitude: Double?, userName: String) {
        let defaults = UserDefaults.standard
        defaults.set(propertyId?.uuidString, forKey: Self.propertyKey)
        defaults.set(userName, forKey: Self.nameKey)
        if let latitude, let longitude {
            defaults.set(latitude, forKey: Self.latKey)
            defaults.set(longitude, forKey: Self.lonKey)
        } else {
            defaults.removeObject(forKey: Self.latKey)
            defaults.removeObject(forKey: Self.lonKey)
        }
        rearm()
        if let propertyId {
            Task {
                await load(propertyId: propertyId)
                await subscribe(propertyId: propertyId)
            }
        }
    }

    /// The Settings toggle's landing point. Off = stop monitoring AND erase
    /// the member's own row — opting out leaves no trace.
    func setSharing(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.shareKey)
        if on {
            // Two-step system flow: When-In-Use first when undetermined,
            // then the Always upgrade — the same ladder live location uses.
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
            default: break
            }
            rearm()
        } else {
            stopMonitoring()
            if let propertyId {
                Task { await deleteOwnRow(propertyId: propertyId) }
            }
        }
    }

    private func rearm() {
        stopMonitoring()
        guard isArmed,
              let lat = UserDefaults.standard.object(forKey: Self.latKey) as? Double,
              let lon = UserDefaults.standard.object(forKey: Self.lonKey) as? Double,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        else { return }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: Self.radius, identifier: Self.regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        // Seed the state row from the CURRENT side of the fence.
        manager.requestState(for: region)
    }

    private func stopMonitoring() {
        for region in manager.monitoredRegions where region.identifier == Self.regionIdentifier {
            manager.stopMonitoring(for: region)
        }
        seededRegionIds.removeAll()
    }

    // MARK: CLLocationManagerDelegate (nonisolated → main-actor hops)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.rearm()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionIdentifier else { return }
        Task { @MainActor in await self.transition(.arrive) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.regionIdentifier else { return }
        Task { @MainActor in await self.transition(.leave) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didDetermineState state: CLRegionState,
                                     for region: CLRegion) {
        guard region.identifier == Self.regionIdentifier, state != .unknown else { return }
        let isHome = state == .inside
        Task { @MainActor in
            // First determination after arming seeds the row silently.
            guard !self.seededRegionIds.contains(region.identifier) else { return }
            self.seededRegionIds.insert(region.identifier)
            await self.upsertState(isHome: isHome)
        }
    }

    // MARK: Writes — exactly two rows per transition, nothing else

    private func transition(_ kind: Transition) async {
        guard sharing else { return }
        lastTransition = (kind, Date())
        await upsertState(isHome: kind == .arrive)
        await insertEvent(kind)
    }

    private struct StateUpsert: Encodable {
        let property_id: String
        let user_id: String
        let user_name: String
        let is_home: Bool
        let since: String
        let updated_at: String
    }

    private func upsertState(isHome: Bool) async {
        guard let propertyId,
              let userId = supabase.auth.currentSession?.user.id else { return }
        let name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        let now = ISODate.string(from: Date())
        _ = try? await supabase.from("home_presence")
            .upsert(StateUpsert(property_id: propertyId.uuidString,
                                user_id: userId.uuidString,
                                user_name: name, is_home: isHome,
                                since: now, updated_at: now),
                    onConflict: "property_id,user_id")
            .execute()
    }

    private struct EventInsert: Encodable {
        let property_id: String
        let user_name: String
        let event: String
    }

    private func insertEvent(_ kind: Transition) async {
        guard let propertyId else { return }
        let name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        _ = try? await supabase.from("home_presence_events")
            .insert(EventInsert(property_id: propertyId.uuidString,
                                user_name: name, event: kind.rawValue))
            .execute()
    }

    private func deleteOwnRow(propertyId: UUID) async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        _ = try? await supabase.from("home_presence").delete()
            .eq("property_id", value: propertyId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        household.removeAll { $0.userId == userId }
    }

    // MARK: Household reads

    func load(propertyId: UUID) async {
        do {
            household = try await supabase.from("home_presence")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .execute().value
        } catch { /* glanceable — next foreground retries */ }
    }

    /// The freshest arrivals/departures — the house timeline's source.
    func recentEvents(propertyId: UUID, limit: Int = 20) async -> [HomePresenceEvent] {
        (try? await supabase.from("home_presence_events")
            .select("id,user_name,event,created_at")
            .eq("property_id", value: propertyId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value) ?? []
    }

    /// Foreground-only realtime on the state table (migration 160 put it in
    /// the publication) — background stays silent; foreground load catches up.
    private func subscribe(propertyId: UUID) async {
        guard !AppLifecycle.isBackgrounded else { return }
        if let channel { await realtimeAnon.removeChannel(channel) }
        pgSubs.removeAll()
        let ch = realtimeAnon.channel("home_presence:\(propertyId.uuidString)")
        pgSubs.append(ch.onPostgresChange(
            AnyAction.self, schema: "public", table: "home_presence",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard !AppLifecycle.isBackgrounded else { return }
                await self?.load(propertyId: propertyId)
            }
        })
        try? await withRealtimeTimeout(seconds: 15) { try await ch.subscribeWithError() }
        channel = ch
    }
}

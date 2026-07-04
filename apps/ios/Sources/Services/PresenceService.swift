import Foundation
import Observation
import SwiftUI
import Supabase

/// WhatsApp-style presence: a per-member heartbeat gives each conversation an
/// "online" / "last seen {relative}" status.
///
/// Deliberately heartbeat-based rather than Realtime Presence: the client
/// upserts its own `presence` row every ~45s while foregrounded and reads the
/// property's rows to derive status. This keeps presence off the realtime
/// postgres-change subscriptions (leaving that path untouched) and costs one
/// tiny upsert + one select per interval. Sharing is opt-out — a member who
/// turns it off simply stops heartbeating and reads as offline to everyone.
@MainActor
@Observable
final class PresenceService {
    /// user_name → last heartbeat time, for every member of the loaded property.
    private(set) var lastSeen: [String: Date] = [:]

    /// Whether this device advertises its own presence. Off ⇒ no heartbeat.
    @ObservationIgnored
    @AppStorage("presence.shareStatus") private var shareStatus = true

    @ObservationIgnored private var channel: RealtimeChannelV2?
    /// onPostgresChange handles remove their callback on deinit, so they must be
    /// retained for the callbacks to keep firing; cleared on unsubscribe.
    @ObservationIgnored private var postgresSubs: [RealtimeSubscription] = []
    @ObservationIgnored private var subscribedPropertyId: UUID?

    /// A member counts as "online" if seen within this window.
    static let onlineWindow: TimeInterval = 90

    enum Status: Equatable {
        case online
        case lastSeen(Date)
        /// No data, or the member hasn't shared presence — show nothing.
        case hidden
    }

    func status(for userName: String) -> Status {
        guard !userName.isEmpty, let seen = lastSeen[userName] else { return .hidden }
        return Date().timeIntervalSince(seen) < Self.onlineWindow ? .online : .lastSeen(seen)
    }

    func load(propertyId: UUID) async {
        do {
            let rows: [PresenceRow] = try await supabase
                .from("presence")
                .select("user_name,last_seen_at")
                .eq("property_id", value: propertyId.uuidString)
                .execute()
                .value
            var map: [String: Date] = [:]
            for r in rows where !r.userName.isEmpty {
                if let d = ISODate.date(from: r.lastSeenAt) { map[r.userName] = d }
            }
            lastSeen = map
        } catch {
            // presence table may not exist yet (migration 086 not applied) —
            // degrade silently to "no presence data".
        }
    }

    /// Live presence: reload the property's statuses whenever any member's row
    /// changes (a heartbeat upsert), so "online" flips within seconds instead of
    /// on the next poll. Idempotent — re-subscribing to the same property is a
    /// no-op; switching properties tears down the old channel first.
    func subscribe(propertyId: UUID) async {
        guard subscribedPropertyId != propertyId else { return }
        await unsubscribe()
        let ch = supabase.realtimeV2.channel("presence:\(propertyId.uuidString)")
        // Callbacks must be registered before subscribing.
        postgresSubs.append(ch.onPostgresChange(
            InsertAction.self, schema: "public", table: "presence",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in await self?.load(propertyId: propertyId) }
        })
        postgresSubs.append(ch.onPostgresChange(
            UpdateAction.self, schema: "public", table: "presence",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in await self?.load(propertyId: propertyId) }
        })
        try? await ch.subscribeWithError()
        channel = ch
        subscribedPropertyId = propertyId
    }

    func unsubscribe() async {
        if let ch = channel {
            await supabase.realtimeV2.removeChannel(ch)
            channel = nil
        }
        postgresSubs.removeAll()
        subscribedPropertyId = nil
    }

    func heartbeat(propertyId: UUID, userId: UUID, userName: String) async {
        guard shareStatus, !userName.isEmpty else { return }
        let now = ISODate.plain.string(from: Date())
        let row = PresenceUpsert(
            property_id: propertyId.uuidString,
            user_id: userId.uuidString,
            user_name: userName,
            last_seen_at: now,
            updated_at: now
        )
        _ = try? await supabase
            .from("presence")
            .upsert(row, onConflict: "property_id,user_id")
            .execute()
    }
}

private struct PresenceRow: Decodable {
    let userName: String
    let lastSeenAt: String
    enum CodingKeys: String, CodingKey {
        case userName = "user_name"
        case lastSeenAt = "last_seen_at"
    }
}

private struct PresenceUpsert: Encodable {
    let property_id: String
    let user_id: String
    let user_name: String
    let last_seen_at: String
    let updated_at: String
}

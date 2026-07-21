import Foundation
import Observation
import SwiftUI
import Supabase

/// WhatsApp-style presence: "online" / "last seen {relative}" per member.
///
/// Two complementary sources, both keyed by AUTH USER ID (display names are
/// snapshots that drift and — in production — carry stray whitespace, so they
/// can never be a key):
///
///  1. Realtime channel presence (track / join / leave / sync): the instant
///     signal. A client tracks `{user_id}` on the property's presence channel
///     while foregrounded, so peers flip online the moment it joins and back
///     to "last seen just now" the moment it leaves — no heartbeat lag.
///  2. The `presence` table heartbeat (one upsert per ~45s, primary key
///     (property_id, user_id)): the durable "last seen" timestamp that
///     survives app restarts and covers clients that predate channel
///     presence. Row changes are pushed via postgres-changes (migration 087),
///     so a heartbeat also refreshes peers within seconds.
///
/// Sharing is opt-out — a member who turns it off stops heartbeating and
/// untracks, reading as offline/hidden to everyone.
@MainActor
@Observable
final class PresenceService {
    /// auth user id → last heartbeat time, for every member of the loaded
    /// property (server rows).
    private(set) var lastSeenById: [UUID: Date] = [:]
    /// TRIMMED display name → last heartbeat. Legacy fallback only, for
    /// callers that know a member by name alone (no linked account id).
    private(set) var lastSeenByName: [String: Date] = [:]
    /// User ids currently tracked on the realtime presence channel — the
    /// instant "online" signal, ahead of any heartbeat row.
    private(set) var onlineUserIds: Set<UUID> = []

    /// Whether this device advertises its own presence. Off ⇒ no heartbeat.
    @ObservationIgnored
    @AppStorage("presence.shareStatus") private var shareStatus = true

    @ObservationIgnored private var channel: RealtimeChannelV2?
    /// onPostgresChange/onPresenceChange handles remove their callback on
    /// deinit, so they must be retained for the callbacks to keep firing;
    /// cleared on unsubscribe.
    @ObservationIgnored private var postgresSubs: [RealtimeSubscription] = []
    @ObservationIgnored private var presenceSub: RealtimeSubscription?
    @ObservationIgnored private var subscribedPropertyId: UUID?

    /// A member counts as "online" if seen within this window (heartbeat
    /// fallback; channel presence flips instantly regardless).
    static let onlineWindow: TimeInterval = 90

    enum Status: Equatable {
        case online
        case lastSeen(Date)
        /// No data, or the member hasn't shared presence — show nothing.
        case hidden
    }

    /// Presence status by identity. The auth user id is authoritative; the
    /// (trimmed) name only covers legacy rows for members without a known id.
    /// Pass the render clock (`TimelineView` date) as `now` so relative
    /// statuses re-evaluate while visible instead of freezing.
    func status(userId: UUID?, name: String? = nil, at now: Date = Date()) -> Status {
        if let uid = userId {
            if onlineUserIds.contains(uid) { return .online }
            if let seen = lastSeenById[uid] {
                return now.timeIntervalSince(seen) < Self.onlineWindow ? .online : .lastSeen(seen)
            }
        }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let seen = lastSeenByName[trimmed] else { return .hidden }
        return now.timeIntervalSince(seen) < Self.onlineWindow ? .online : .lastSeen(seen)
    }

    func load(propertyId: UUID) async {
        do {
            let rows: [PresenceRow] = try await supabase
                .from("presence")
                .select("user_id,user_name,last_seen_at")
                .eq("property_id", value: propertyId.uuidString)
                .execute()
                .value
            var byId: [UUID: Date] = [:]
            var byName: [String: Date] = [:]
            for r in rows {
                guard let d = ISODate.date(from: r.lastSeenAt) else { continue }
                if let uid = UUID(uuidString: r.userId) { byId[uid] = d }
                // Names are display data and may carry stray whitespace
                // ("Adi " in production) — key the fallback map TRIMMED.
                let name = r.userName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { byName[name] = d }
            }
            lastSeenById = byId
            lastSeenByName = byName
        } catch {
            // presence table may not exist yet (migration 086 not applied) —
            // degrade silently to "no presence data".
        }
    }

    /// Live presence. Two push paths on one channel:
    ///  - channel presence join/leave/sync → `onlineUserIds` flips instantly;
    ///  - postgres-changes on the `presence` table → heartbeat timestamps
    ///    refresh within seconds of any member's upsert.
    /// Idempotent — re-subscribing to the same property is a no-op; switching
    /// properties tears down the old channel first.
    func subscribe(propertyId: UUID) async {
        // Liveness-based idempotency (audit 2026-07-21): a channel whose
        // subscribe FAILED must not satisfy the guard and silence the
        // session — only a genuinely .subscribed same-scope channel is
        // a no-op (the resilient pattern from the chat engines).
        if let ch = channel, subscribedPropertyId == propertyId,
           ch.status == .subscribed || ch.status == .subscribing { return }
        // Rejoin grace: right after a RE-connect the SDK's rejoinChannels()
        // owns recovery, and our previous topic may live server-side as an
        // orphan whose stale phx_close kills any join added in the window
        // (the b1182 anatomy). The foreground pulse retries post-grace.
        if RealtimeFlightRecorder.shared.inRejoinGrace(seconds: 10),
           channel == nil || subscribedPropertyId == propertyId { return }
        await unsubscribe()
        let myId = supabase.auth.currentSession?.user.id
        // The presence key IS the auth user id, so join/leave maps arrive
        // keyed by identity and need no payload decoding.
        let ch = realtimeAnon.channel("presence:\(propertyId.uuidString)") {
            $0.presence.key = myId?.uuidString ?? ""
        }
        // Callbacks must be registered before subscribing.
        presenceSub = ch.onPresenceChange { [weak self] action in
            let joins = action.joins.keys.compactMap(UUID.init(uuidString:))
            let leaves = action.leaves.keys.compactMap(UUID.init(uuidString:))
            Task { @MainActor [weak self] in self?.applyPresenceDiff(joins: joins, leaves: leaves) }
        }
        postgresSubs.append(ch.onPostgresChange(
            InsertAction.self, schema: "public", table: "presence",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Quiet in the background (0x8BADF00D watchdog, b1036).
                guard !AppLifecycle.isBackgrounded else { return }
                await self?.load(propertyId: propertyId)
            }
        })
        postgresSubs.append(ch.onPostgresChange(
            UpdateAction.self, schema: "public", table: "presence",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Quiet in the background (0x8BADF00D watchdog, b1036).
                guard !AppLifecycle.isBackgrounded else { return }
                await self?.load(propertyId: propertyId)
            }
        })
        do {
            // Timeboxed: a subscribe awaiting a never-recovering socket
            // must not hang the caller's foreground pulse forever.
            try await withRealtimeTimeout(seconds: 15) {
                try await ch.subscribeWithError()
            }
        } catch {
            // A failed subscribe leaves NO trace — recording it as live is
            // what made presence go permanently silent. unsubscribe() FIRST:
            // it sends phx_leave from every state; removeChannel alone skips
            // the leave and breeds the server orphan (b1173).
            debugLog("Presence realtime subscribe failed:", error)
            presenceSub = nil
            postgresSubs.removeAll()
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            return
        }
        channel = ch
        subscribedPropertyId = propertyId
        // Advertise ourselves the moment the channel is live (heartbeat
        // re-tracks on every beat, but peers shouldn't wait for it).
        if shareStatus, let myId {
            await ch.track(state: ["user_id": .string(myId.uuidString)])
        }
    }

    func unsubscribe() async {
        if let ch = channel {
            // Real leave from EVERY state (b1173): removeChannel skips the
            // phx_leave when the channel isn't .subscribed, and the orphan
            // join it left behind is whose stale close killed the next
            // foreground rejoin of this very topic. unsubscribe() also
            // emits our presence "leave" to every peer.
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            channel = nil
        }
        presenceSub = nil
        postgresSubs.removeAll()
        subscribedPropertyId = nil
        onlineUserIds.removeAll()
    }

    func heartbeat(propertyId: UUID, userId: UUID, userName: String) async {
        guard shareStatus, !userName.isEmpty else {
            // Sharing turned off: stop advertising on the live channel too.
            if let ch = channel { await ch.untrack() }
            return
        }
        let now = ISODate.plain.string(from: Date())
        let row = PresenceUpsert(
            property_id: propertyId.uuidString,
            user_id: userId.uuidString,
            user_name: userName.trimmingCharacters(in: .whitespacesAndNewlines),
            last_seen_at: now,
            updated_at: now
        )
        _ = try? await supabase
            .from("presence")
            .upsert(row, onConflict: "property_id,user_id")
            .execute()
        // Keep the channel-presence advertisement alive alongside the row
        // (also self-heals if sharing was re-enabled after subscribe).
        if let ch = channel, subscribedPropertyId == propertyId, ch.status == .subscribed {
            await ch.track(state: ["user_id": .string(userId.uuidString)])
        }
    }

    // MARK: - Private

    /// Applies a presence join/leave diff. A leaver's timestamp is stamped
    /// locally so their subtitle flips to "last seen just now" immediately —
    /// the heartbeat row (up to ~45s stale) catches up on its own.
    private func applyPresenceDiff(joins: [UUID], leaves: [UUID]) {
        for uid in joins {
            onlineUserIds.insert(uid)
            lastSeenById[uid] = Date()
        }
        for uid in leaves {
            onlineUserIds.remove(uid)
            lastSeenById[uid] = Date()
        }
    }
}

private struct PresenceRow: Decodable {
    let userId: String
    let userName: String
    let lastSeenAt: String
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
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

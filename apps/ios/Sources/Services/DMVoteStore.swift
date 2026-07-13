import Foundation
import Observation
import Supabase

// MARK: - DM event RSVP store
//
// The direct-message counterpart of MessageService's poll-vote section:
// event bubbles in a 1-on-1 thread store their Going / Can't go answers in
// `dm_poll_votes` (migration 152), a mirror of the group `message_poll_votes`
// table keyed on direct_messages ids. It lives outside DirectMessageService
// (frozen) as a small, self-contained property-scoped store.
//
// Lifecycle: like the DM message channel itself, the realtime channel is
// PROPERTY-scoped and stays alive for the session — DirectMessageView never
// tears the DM channel down on disappear (the conversation list depends on
// it), so this store follows the same contract. `subscribeRealtime` is
// idempotent (status-checked), re-binds itself when the property changes,
// and `unsubscribe()` exists for that internal switch and for tests.
@MainActor
@Observable
final class DMVoteStore {
    static let shared = DMVoteStore()
    private init() {}

    /// RSVP rows grouped by DM message id. Reuses the group `PollVote` model:
    /// its coding keys (id / message_id / user_id / voter_name / option_index)
    /// match `dm_poll_votes` column-for-column — the migration mirrors
    /// `message_poll_votes` — and the extra columns (property_id, created_at)
    /// are simply not decoded.
    var votes: [UUID: [PollVote]] = [:]

    @ObservationIgnored private var channel: RealtimeChannelV2?
    /// Property the live channel is bound to — makes subscribeRealtime
    /// idempotent (see DirectMessageService.subscribedPropertyId).
    @ObservationIgnored private var subscribedPropertyId: UUID?
    /// Retained postgres-change handles; deinit removes the callback, so they
    /// must be held for the callbacks to keep firing (see MessageService).
    @ObservationIgnored private var postgresSubs: [RealtimeSubscription] = []
    /// Coalesces bursts of realtime events into one reload per quiet window.
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    func load(propertyId: UUID) async {
        guard let rows: [PollVote] = try? await supabase
            .from("dm_poll_votes")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .execute()
            .value
        else { return }
        votes = Dictionary(grouping: rows, by: { $0.messageId })
    }

    /// Single-choice toggle — RSVP is Going XOR Can't go, exactly
    /// `MessageService.togglePollVote` with `multi: false`: tapping my current
    /// answer withdraws it; picking the other answer replaces it (my previous
    /// row is deleted before the insert, so the unique index never trips).
    func toggle(messageId: UUID, propertyId: UUID, optionIndex: Int, voterName: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        let mine = votes[messageId]?.filter { $0.userId == uid } ?? []
        let already = mine.contains { $0.optionIndex == optionIndex }

        if already {
            _ = try? await supabase.from("dm_poll_votes").delete()
                .eq("message_id", value: messageId.uuidString)
                .eq("user_id", value: uid.uuidString)
                .eq("option_index", value: optionIndex)
                .execute()
        } else {
            _ = try? await supabase.from("dm_poll_votes").delete()
                .eq("message_id", value: messageId.uuidString)
                .eq("user_id", value: uid.uuidString)
                .execute()
            struct V: Encodable {
                let message_id: String; let property_id: String
                let user_id: String; let voter_name: String; let option_index: Int
            }
            _ = try? await supabase.from("dm_poll_votes").insert(
                V(message_id: messageId.uuidString, property_id: propertyId.uuidString,
                  user_id: uid.uuidString, voter_name: voterName, option_index: optionIndex)
            ).execute()
        }
        await load(propertyId: propertyId)
    }

    func subscribeRealtime(propertyId: UUID) async {
        // Idempotent: already GENUINELY live for this property → keep it. The
        // status check matters — a channel whose initial subscribe failed
        // must not satisfy the guard and silence the session (the resilient
        // pattern from DirectMessageService.subscribeRealtime).
        if let ch = channel, subscribedPropertyId == propertyId,
           ch.status == .subscribed { return }
        if channel != nil { await unsubscribe() }

        let ch = supabase.realtimeV2.channel("dm_poll_votes:\(propertyId.uuidString)")
        // Callbacks must be registered before subscribing.
        postgresSubs.append(ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "dm_poll_votes",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReload(propertyId: propertyId) }
        })
        // DELETE: no property filter — under the default replica identity a
        // delete's old-record carries only the primary key, so filtering on
        // property_id would discard every delete (see the DM message channel's
        // DELETE handler). The debounced property-scoped reload re-narrows it.
        postgresSubs.append(ch.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "dm_poll_votes"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReload(propertyId: propertyId) }
        })
        do {
            try await ch.subscribeWithError()
        } catch {
            // A failed subscribe must leave NO trace: keeping the dead channel
            // would make the idempotent guard treat the session as live.
            debugLog("DM poll-vote realtime subscribe failed:", error)
            postgresSubs.removeAll()
            await supabase.realtimeV2.removeChannel(ch)
            return
        }
        channel = ch
        subscribedPropertyId = propertyId
    }

    private func scheduleReload(propertyId: UUID) {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.load(propertyId: propertyId)
        }
    }

    func unsubscribe() async {
        reloadTask?.cancel()
        reloadTask = nil
        postgresSubs.removeAll()
        subscribedPropertyId = nil
        if let ch = channel {
            await supabase.realtimeV2.removeChannel(ch)
            channel = nil
        }
    }
}

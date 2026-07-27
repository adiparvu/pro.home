import Foundation
import Supabase

// MARK: - ChatEngineCore (chat unification P5)
//
// The mechanical shapes BOTH chat engines still carried verbatim after
// P0–P4d-2: the optimistic-send skeleton, the reliable-delivery broadcast
// ping (send + receive side), the typing-broadcast handler, the realtime
// DELETE handler, and the `message_reactions` side-table write sequence.
// Everything here is engine-agnostic mechanics — each engine keeps its own
// model (`DirectMessage` / `Message`), its own tables, its own post-success
// bookkeeping (heads refresh vs sync cursor) and its own semantics, passed
// in through the closures. Nothing here decides WHAT to write, only runs
// the shared HOW both engines had independently converged on.
enum ChatEngineCore {

    // MARK: - Optimistic send skeleton

    /// The send pipeline's invariant, shared by both engines: append the
    /// optimistic row so the bubble appears the moment you hit send; run the
    /// (engine-provided, timeout-bounded) insert; swap the authoritative
    /// server row in by id — or append it if the optimistic row is somehow
    /// gone; run the engine's post-success bookkeeping; and on ANY failure
    /// roll the optimistic row back and rethrow so the caller's error path
    /// (the offline outbox hand-off) takes over instead of leaving a
    /// permanent fake-"sent" bubble that was never persisted.
    ///
    /// Generic over the service and its row array (via key path) so each
    /// engine keeps its own model and observable storage — writes go through
    /// the property's setter, so `revision` bumps exactly as before.
    @MainActor
    @discardableResult
    static func runOptimisticSend<Service: AnyObject, Row: Identifiable>(
        on service: Service,
        rows: ReferenceWritableKeyPath<Service, [Row]>,
        optimistic: Row,
        insert: @MainActor () async throws -> Row,
        onSent: @MainActor (Row) -> Void
    ) async throws -> Row {
        service[keyPath: rows].append(optimistic)
        do {
            let sent = try await insert()
            if let i = service[keyPath: rows].firstIndex(where: { $0.id == sent.id }) {
                service[keyPath: rows][i] = sent
            } else {
                service[keyPath: rows].append(sent)
            }
            onSent(sent)
            return sent
        } catch {
            service[keyPath: rows].removeAll { $0.id == optimistic.id }
            throw error
        }
    }

    // MARK: - Reliable-delivery broadcast ping

    /// Fires the engine's delivery ping ("dm_new"/"msg_new") after a
    /// successful send. postgres_changes INSERTs can be withheld from the
    /// recipient by Realtime's per-subscriber RLS evaluation of the table's
    /// SELECT policy, so the peer's client would never see the new row until
    /// it reloads. A broadcast is RLS-free — the same path the typing signal
    /// already uses — so it guarantees every peer learns of the new message
    /// and fetches it immediately (WhatsApp-grade live delivery).
    @MainActor
    static func broadcastDeliveryPing(on channel: RealtimeChannelV2?,
                                      event: String, from: String) {
        guard let ch = channel else { return }
        Task { await ch.broadcast(event: event, message: ["from": .string(from)]) }
    }

    /// Receive-side twin: whether a delivery-ping broadcast is our own echo
    /// (the channel receives its own broadcasts for the liveness self-test).
    /// Our own send already placed the row, so the echo must not trigger a
    /// refetch. A ping without a "from" field is NOT ours — old clients'
    /// pings still refetch.
    @MainActor
    static func isOwnDeliveryPing(_ json: [String: AnyJSON]) -> Bool {
        guard let from = broadcastString(json, "from") else { return false }
        return from == supabase.auth.currentSession?.user.id.uuidString
    }

    // MARK: - Shared realtime handlers

    /// Registers the typing/recording broadcast handler both engines carried
    /// byte-identically. The broadcast fields live inside the envelope's
    /// payload (see RealtimeBroadcast) — reading them off the top level is
    /// what left typing/recording dead while the channel was "subscribed".
    /// Older clients broadcast no kind — they're treated as typing.
    /// `activity` is the engine's sync hook: it re-syncs channel/name into
    /// its `ChatActivityIndicator` and returns it (nil once the engine is
    /// gone), preserving the exact pre-extraction freshness semantics.
    @MainActor
    static func registerTypingHandler(
        on ch: RealtimeChannelV2,
        activity: @escaping @Sendable @MainActor () -> ChatActivityIndicator?
    ) -> RealtimeSubscription {
        ch.onBroadcast(event: "typing") { json in
            if let name = broadcastString(json, "name") {
                let kind = broadcastString(json, "kind") ?? "typing"
                Task { @MainActor in
                    activity()?.handleTyping(name, kind: kind)
                }
            }
        }
    }

    /// Registers the realtime DELETE handler both engines carried
    /// byte-identically. Registered WITHOUT a property filter on purpose: a
    /// delete's replicated old-record only carries the primary key under the
    /// default replica identity, so a `property_id` filter would discard
    /// every delete event. Removing by id is naturally scoped — only ids
    /// already in the engine's (property-scoped) list can match. The engine
    /// supplies the removal (plus any bookkeeping, e.g. the DM heads
    /// refresh) through `onDelete`.
    @MainActor
    static func registerDeleteHandler(
        on ch: RealtimeChannelV2, table: String,
        onDelete: @escaping @Sendable @MainActor (UUID) -> Void
    ) -> RealtimeSubscription {
        ch.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: table
        ) { action in
            Task { @MainActor in
                guard let row = try? action.decodeOldRecord(decoder: JSONDecoder()) as RealtimeRowID
                else { return }
                onDelete(row.id)
            }
        }
    }

    // MARK: - Reaction side-table write

    /// The `message_reactions` write sequence both engines duplicated: drop
    /// my existing row (DELETE RLS: own rows), then insert the new emoji
    /// (INSERT RLS: conversation/property member). Only the caller's own
    /// (message_id, user_id) row is ever touched. The engines' local-state
    /// models stay their own — the group patches its grouped dictionary
    /// optimistically with rollback, the DM patches its legacy jsonb-shaped
    /// map after success — so only the wire sequence lives here.
    /// Throws to the caller's existing error handling; sequential on purpose
    /// (delete must land before the replacement insert).
    static func persistReactionToggle(messageId: UUID, propertyId: UUID,
                                      userId: UUID, reactorName: String,
                                      emoji: String, removeExisting: Bool,
                                      insertNew: Bool) async throws {
        if removeExisting {
            try await supabase
                .from("message_reactions")
                .delete()
                .eq("message_id", value: messageId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        }
        if insertNew {
            struct ReactInsert: Encodable {
                let message_id: String
                let property_id: String
                let user_id: String
                let reactor_name: String
                let emoji: String
            }
            try await supabase
                .from("message_reactions")
                .insert(ReactInsert(
                    message_id: messageId.uuidString,
                    property_id: propertyId.uuidString,
                    user_id: userId.uuidString,
                    reactor_name: reactorName,
                    emoji: emoji))
                .execute()
        }
    }
}

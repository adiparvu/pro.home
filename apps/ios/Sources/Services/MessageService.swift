import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class MessageService {
    /// Bumped on every mutation of `messages` — views memoize their derived,
    /// filtered lists on it so a body pass that didn't change the data
    /// (every keystroke!) costs O(1) instead of re-filtering the whole chat.
    private(set) var revision = 0
    var messages: [Message] = [] { didSet { revision &+= 1 } }
    var isLoading = false
    var error: String?

    /// The shared realtime channel lifecycle (chat unification P3d): owns the
    /// channel, subscribe/rebuild, the stale-close kill watch, the storm
    /// breaker/rejoin grace and the broadcast round-trip self-test — which
    /// this engine previously LACKED, so a dead broadcast relay read as
    /// "live". This engine contributes only its topic, handlers and refetch —
    /// see `realtimeConfiguration`.
    @ObservationIgnored private let realtime = ChatRealtimeChannel()

    /// Live realtime diagnostic, surfaced by the chat view's warning banner —
    /// see `ChatRealtimeChannel.realtimeStatus` ("live" only once the
    /// broadcast round-trip is proven).
    var realtimeStatus: String { realtime.realtimeStatus }
    var unreadCount = 0
    /// Read receipts grouped by message id (excludes the receipts I created for myself).
    var reads: [UUID: [MessageRead]] = [:]
    /// Delivery receipts grouped by message id (excludes my own device's receipts).
    var deliveries: [UUID: [MessageDelivery]] = [:]
    /// Emoji reactions grouped by message id.
    var reactions: [UUID: [MessageReaction]] = [:]

    /// The live main messages channel — `send()` broadcasts its "msg_new"
    /// delivery ping on it, and the activity indicator is synced from it
    /// before each use.
    private var realtimeChannel: RealtimeChannelV2? { realtime.channel }
    private var readsChannel: RealtimeChannelV2?
    private var deliveriesChannel: RealtimeChannelV2?
    private var reactionsChannel: RealtimeChannelV2?
    /// Retained postgres-change subscription handles for the RECEIPT
    /// channels. `onPostgresChange` (which replaced the removed async-stream
    /// `postgresChange`) returns a handle whose deinit removes the callback,
    /// so it must be held for the callback to keep firing. Each channel owns
    /// its handles — when the main channel (whose handles now live in
    /// `ChatRealtimeChannel`) shared an array with the receipt channels, its
    /// failed-subscribe cleanup left them subscribed but deaf.
    private var readsSubs: [RealtimeSubscription] = []
    private var deliveriesSubs: [RealtimeSubscription] = []
    private var reactionsSubs: [RealtimeSubscription] = []
    private var pollVotesSubs: [RealtimeSubscription] = []

    // MARK: - Typing indicator (shared subsystem — chat unification P3a)
    /// The shared typing/recording indicator; the engine syncs channel/name
    /// into it before each use (see `syncActivity`).
    private let activity = ChatActivityIndicator()
    var typingNames: Set<String> { activity.typingNames }
    var recordingNames: Set<String> { activity.recordingNames }
    var myName: String = ""
    /// Coalesces bursts of realtime events so a flurry of changes triggers a
    /// single reload per quiet window instead of one reload per event (C2). Same
    /// reload code runs — just debounced — so the displayed data stays correct.
    private var reloadTasks: [String: Task<Void, Never>] = [:]

    func sendTyping() { syncActivity(); activity.sendTyping() }

    /// Periodic signal while the voice recorder is live — see
    /// `ChatActivityIndicator.sendRecording`.
    func sendRecording() { syncActivity(); activity.sendRecording() }

    /// The indicator never owns realtime lifecycle: the engine hands it the
    /// current channel + name right before each use, so it is always exactly
    /// as fresh as the engine's own state was in the pre-extraction code.
    private func syncActivity() {
        activity.channel = realtimeChannel
        activity.myName = myName
    }

    /// Communities: the group this service instance is scoped to. nil = main group.
    /// Set on load() and reused by pagination / send so a group chat stays inside
    /// its group_id without threading it through every call site.
    private(set) var currentGroupId: UUID?

    /// created_at of the newest row we've actually seen from the SERVER. The
    /// `loadNewer` cursor rides this instead of `messages.last?.createdAt`, whose
    /// last entry can be an optimistic row stamped with a (possibly skewed)
    /// client clock — a future client stamp would make `gt(created_at)` skip
    /// real rows. Server timestamps are authoritative and monotonic.
    @ObservationIgnored private var lastSyncedCreatedAt: String?

    func load(propertyId: UUID, groupId: UUID? = nil) async {
        // Teardown only on a genuine conversation switch: load() reruns on
        // every appear/foreground for the SAME scope, and an unconditional
        // unsubscribeAll() here raced the parallel subscribe .task into a
        // leave-less teardown (removeChannel sends no phx_leave from a
        // non-.subscribed channel in SDK 2.52.0) — the orphaned server join
        // then closed the next confirmed join (the b1173 field log).
        if realtime.subscribedTopic != nil,
           realtime.subscribedTopic != Self.realtimeTopic(propertyId: propertyId,
                                                          groupId: groupId) {
            await unsubscribeAll()
        }
        currentGroupId = groupId
        // Session gate (same law as PropertyRepo): a fetch riding the anon
        // key gets a SUCCESSFUL empty page under RLS — the "chat opens
        // empty on first entry" field report — and the realtime join that
        // follows it rides the same stale credential, which the server
        // answers by closing the channel. Refresh-or-throw first; if the
        // refresh fails this load simply ends and the cached page stands.
        guard (try? await supabase.auth.session) != nil else { return }
        // Offline hydration (audit: the flagship feature opened EMPTY
        // offline while every record module hydrated from disk). Paint the
        // last cached page instantly — guarded on empty, so a refresh never
        // clobbers richer live state — then let the network win below. The
        // group scope folds into the entity key because ServiceCache only
        // scopes by property. Receipts/reactions stay network-only.
        let cacheEntity = "messages.\(groupId?.uuidString ?? "main")"
        if messages.isEmpty,
           let cached = ServiceCache.load([Message].self, entity: cacheEntity,
                                          propertyId: propertyId) {
            let hidden = hiddenIds()
            messages = cached.filter { !hidden.contains($0.id) }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // Load the most recent page (newest first from the DB, shown oldest→newest).
            var query = supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                // Unified-store guard (P4c): DM rows now live in this table
                // too (conversation_id set) — group/main queries must never
                // pull them, on any flag state.
                .is("conversation_id", value: nil)
            // Scope is symmetric: a group chat sees only its group, and the
            // main chat sees only NULL-group rows — otherwise every community
            // message would also land in the main conversation.
            if let gid = groupId { query = query.eq("group_id", value: gid.uuidString) }
            else { query = query.or("group_id.is.null") }
            let rows: [Message] = try await query
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value
            let hidden = hiddenIds()
            messages = rows.reversed().filter { !hidden.contains($0.id) }
            hasMoreOlder = rows.count == Self.pageSize
            // rows are newest-first, so rows.first is the newest server row.
            if let newest = rows.first?.createdAt { lastSyncedCreatedAt = newest }
            // Snapshot the fresh page for the next cold/offline open —
            // naturally bounded at pageSize rows.
            ServiceCache.save(messages, entity: cacheEntity, propertyId: propertyId)
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// Page size for chat history loads / pagination.
    static let pageSize = 50
    /// True while older messages remain to be loaded.
    var hasMoreOlder = false
    var isLoadingOlder = false

    /// Loads the next older page and prepends it (for "load older" / scroll-to-top).
    func loadOlder(propertyId: UUID) async {
        guard hasMoreOlder, !isLoadingOlder, let oldest = messages.first?.createdAt else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            var query = supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .is("conversation_id", value: nil)
                .lt("created_at", value: oldest)
            if let gid = currentGroupId { query = query.eq("group_id", value: gid.uuidString) }
            else { query = query.or("group_id.is.null") }
            let rows: [Message] = try await query
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value
            let hidden = hiddenIds()
            let existing = Set(messages.map { $0.id })
            let older = rows.reversed().filter { !hidden.contains($0.id) && !existing.contains($0.id) }
            messages.insert(contentsOf: older, at: 0)
            hasMoreOlder = rows.count == Self.pageSize
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// Appends messages newer than the newest loaded (used on realtime insert so
    /// expanded older history isn't collapsed by a full reload).
    func loadNewer(propertyId: UUID) async -> Int {
        do {
            var query = supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .is("conversation_id", value: nil)
            if let gid = currentGroupId { query = query.eq("group_id", value: gid.uuidString) }
            else { query = query.or("group_id.is.null") }
            // Cursor on the last SERVER-acked row, not the last in-memory row
            // (which may be an optimistic message stamped with a skewed client
            // clock). Falls back to the newest loaded row before the first sync.
            if let cursor = lastSyncedCreatedAt ?? messages.last?.createdAt {
                query = query.gt("created_at", value: cursor)
            }
            let rows: [Message] = try await query
                .order("created_at", ascending: true)
                .limit(Self.pageSize)
                .execute()
                .value
            let hidden = hiddenIds()
            let existing = Set(messages.map { $0.id })
            let fresh = rows.filter { !hidden.contains($0.id) && !existing.contains($0.id) }
            messages.append(contentsOf: fresh)
            // rows are ascending, so the last is the newest server row this page saw.
            if let newest = rows.last?.createdAt { lastSyncedCreatedAt = newest }
            return fresh.count
        } catch {
            return 0
        }
    }

    // MARK: - Realtime (shared lifecycle — chat unification P3d)

    /// Topic includes the group scope so a community thread's channel never
    /// collides with the main chat's channel for the same property.
    private static func realtimeTopic(propertyId: UUID, groupId: UUID?) -> String {
        "messages:\(propertyId.uuidString):\(groupId?.uuidString ?? "main")"
    }

    func subscribeRealtime(propertyId: UUID, groupId: UUID? = nil) async {
        await realtime.subscribe(
            realtimeConfiguration(propertyId: propertyId, groupId: groupId))
    }

    /// Delivery safety net for an OPEN conversation — see
    /// `ChatRealtimeChannel.ensureLiveDelivery`. On rebuild the refetch is the
    /// cursor-driven `onNewMessagesSignal`, so nothing that arrived during
    /// the outage is missed (and nothing double-counts).
    func ensureLiveDelivery(propertyId: UUID, groupId: UUID? = nil) async {
        await realtime.ensureLiveDelivery(
            realtimeConfiguration(propertyId: propertyId, groupId: groupId))
    }

    /// This engine's seam into the shared lifecycle: the scoped topic, the
    /// handler registrations and the post-rebuild refetch. Built fresh per
    /// call — the closures capture the scope exactly like the pre-extraction
    /// code captured its parameters.
    private func realtimeConfiguration(propertyId: UUID,
                                       groupId: UUID?) -> ChatRealtimeChannel.Configuration {
        ChatRealtimeChannel.Configuration(
            topic: Self.realtimeTopic(propertyId: propertyId, groupId: groupId),
            tag: "chat",
            register: { [weak self] ch in
                self?.registerRealtimeHandlers(on: ch, propertyId: propertyId,
                                               groupId: groupId) ?? []
            },
            refetch: { [weak self] in
                await self?.onNewMessagesSignal(propertyId: propertyId)
            },
            onDetach: { [weak self] in
                // The activity indicator re-syncs from the live channel
                // before each use — drop its handle with the channel.
                self?.activity.channel = nil
            })
    }

    /// Registers this engine's handlers on a fresh channel — callbacks must
    /// be registered before subscribing — and returns the retained handles
    /// (the shared lifecycle stores and clears them).
    private func registerRealtimeHandlers(on channel: RealtimeChannelV2, propertyId: UUID,
                                          groupId: UUID?) -> [RealtimeSubscription] {
        // The group scope arrives EXPLICITLY: subscribing races load()
        // (separate .task), and deriving the topic from a not-yet-set
        // currentGroupId subscribed a community thread to the MAIN chat's
        // topic — the realtime client returns the already-subscribed channel
        // for a duplicate topic and silently drops callbacks registered after
        // subscribe. Stamp the scope at the same point the pre-extraction
        // code did: right before the handlers go on.
        currentGroupId = groupId
        var subs: [RealtimeSubscription] = []
        subs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.onNewMessagesSignal(propertyId: propertyId)
            }
        })
        // UPDATE: reconcile the changed row in place by id so edits, pin/mark,
        // "delete for everyone" tombstones (body arrives null) and the
        // disappearing sweep's blanking propagate live to every open client.
        subs.append(channel.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                guard let self,
                      let updated = try? action.decodeRecord(decoder: JSONDecoder()) as Message
                else { return }
                self.applyRealtimeUpdate(updated)
            }
        })
        // DELETE handler (shared shape — P5): drop the row by id.
        subs.append(ChatEngineCore.registerDeleteHandler(
            on: channel, table: "messages"
        ) { [weak self] id in
            self?.messages.removeAll { $0.id == id }
        })
        // Typing handler (shared shape — P5): the hook re-syncs channel/name
        // into the indicator right before each event, exactly as before.
        subs.append(ChatEngineCore.registerTypingHandler(on: channel) { [weak self] in
            guard let self else { return nil }
            self.syncActivity()
            return self.activity
        })
        // Reliable delivery: a sender broadcasts "msg_new"; fetch newer rows so
        // the message appears live even when postgres_changes was withheld by
        // RLS. Skip my own echo. loadNewer's cursor dedupes against the
        // postgres_changes path, so a message that arrives via BOTH is added once.
        subs.append(channel.onBroadcast(event: "msg_new") { [weak self] json in
            Task { @MainActor [weak self] in
                guard let self, !ChatEngineCore.isOwnDeliveryPing(json) else { return }
                await self.onNewMessagesSignal(propertyId: propertyId)
            }
        })
        return subs
    }

    /// Fetch messages newer than the sync cursor and fold them in: count the
    /// ones from others as unread and play the incoming tone. Shared by the
    /// postgres_changes INSERT handler and the "msg_new" broadcast, both of
    /// which may fire for the same message — loadNewer's cursor makes the
    /// second a no-op, so nothing double-counts.
    private func onNewMessagesSignal(propertyId: UUID) async {
        // Quiet in the background: a realtime-driven refetch mutates observable
        // state → SwiftUI scene updates while backgrounded → the exact
        // 0x8BADF00D scene-update watchdog kill captured on Build 1036. The
        // foreground hooks refetch everything on activation.
        guard !AppLifecycle.isBackgrounded else { return }
        let added = await loadNewer(propertyId: propertyId)
        guard added > 0 else { return }
        let myId = supabase.auth.currentSession?.user.id
        let fromOthers = messages.suffix(added).filter { $0.senderId != myId }.count
        unreadCount += fromOthers
        if fromOthers > 0 {
            ChatToneStore.playIncoming(currentGroupId?.uuidString ?? "group")
        }
    }

    func unsubscribe() async {
        // The channel handles, the kill watch and the real
        // leave-from-every-state (b1173) live in the shared lifecycle.
        await realtime.unsubscribe()
    }

    /// Reconciles a realtime UPDATE against the loaded window: the server row is
    /// authoritative, so we swap it in wholesale (handles edits, pin/mark,
    /// deleted_for_all tombstones whose body is now null, and disappearing
    /// blanking). Rows outside the window — or hidden via "delete for me" — are
    /// simply absent and correctly ignored.
    private func applyRealtimeUpdate(_ updated: Message) {
        guard let idx = messages.firstIndex(where: { $0.id == updated.id }) else { return }
        messages[idx] = updated
    }

    /// Unread group messages from others since this device last had the chat
    /// open — derived from the persisted last-seen marker so it stays correct
    /// no matter which screen is showing (unlike the incremental `unreadCount`,
    /// which only ticked while ChatView itself was on-screen and reset there).
    func groupUnread(propertyId: UUID, myId: UUID?) -> Int {
        let seen = lastSeen(propertyId: propertyId)
        return messages.filter { $0.senderId != myId && ($0.date ?? .distantPast) > seen }.count
    }

    func deleteMessage(id: UUID) async {
        if await ChatMessageStore.deleteRow(table: "messages", id: id, tag: "Chat") {
            messages.removeAll { $0.id == id }
        }
    }

    /// Delete for everyone — keeps the row but replaces it with a tombstone.
    func deleteForEveryone(id: UUID) async {
        if await ChatMessageStore.tombstoneRow(table: "messages", id: id, tag: "Chat"),
           let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i].deletedForAll = true
        }
    }

    /// Delete for me — hides the message locally only (persists across reloads).
    func deleteForMe(id: UUID) {
        ChatMessageStore.hide(id, key: Self.hiddenKey)
        messages.removeAll { $0.id == id }
    }

    func editMessage(id: UUID, newBody: String) async {
        let nowISO = ISODate.string(from: Date())
        if await ChatMessageStore.editRow(table: "messages", id: id, newBody: newBody,
                                          editedAtISO: nowISO, tag: "Chat"),
           let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i].body = newBody
            messages[i].editedAt = nowISO
        }
    }

    private static let hiddenKey = "chat.hidden.ids"
    private func hiddenIds() -> Set<UUID> {
        ChatMessageStore.hiddenIds(key: Self.hiddenKey)
    }

    func send(propertyId: UUID, senderName: String, body: String?,
              attachmentUrl: String? = nil, attachmentType: String? = nil,
              latitude: Double? = nil, longitude: Double? = nil,
              mentionedIds: [String] = [], replyTo: UUID? = nil) async throws {
        guard let senderId = supabase.auth.currentSession?.user.id else { return }

        // Disappearing messages: stamp expires_at from the conversation's TTL so
        // the server sweep deletes the row (enforcement, not just view-hiding).
        let convKey = currentGroupId?.uuidString ?? "group"
        let ttl = ChatDisappearStore.ttl(convKey)
        let expiresAt: String? = ttl > 0
            ? ISODate.string(from: Date().addingTimeInterval(ttl))
            : nil

        let payload = NewMessage(
            id: UUID(),
            property_id: propertyId,
            sender_id: senderId,
            sender_name: senderName,
            body: body,
            attachment_url: attachmentUrl,
            attachment_type: attachmentType,
            latitude: latitude,
            longitude: longitude,
            mentioned_ids: mentionedIds,
            reply_to: replyTo,
            group_id: currentGroupId,
            expires_at: expiresAt
        )

        // Optimistic pipeline (shared skeleton — P5, ChatEngineCore): the
        // bubble appears the moment you hit send instead of after the network
        // round-trip. The id is client-generated, so the realtime echo and
        // loadNewer dedup against it; on ack the server row (authoritative
        // timestamp) is swapped in, on failure the optimistic row rolls back
        // and the error rethrows so the caller's error path (outbox) takes over.
        let optimistic = Message(
            id: payload.id!,
            propertyId: propertyId,
            senderId: senderId,
            senderName: senderName,
            body: body,
            attachmentUrl: attachmentUrl,
            attachmentType: attachmentType,
            latitude: latitude,
            longitude: longitude,
            mentionedIds: mentionedIds,
            replyTo: replyTo,
            pinned: nil, isMarked: nil, editedAt: nil, deletedForAll: nil,
            groupId: currentGroupId,
            expiresAt: expiresAt,
            createdAt: ISODate.string(from: Date())
        )
        try await ChatEngineCore.runOptimisticSend(
            on: self, rows: \MessageService.messages, optimistic: optimistic,
            insert: {
                // Bounded insert: a hung network call resolves to a timeout
                // the caller routes to the outbox, instead of leaving a
                // permanent fake-"sent" optimistic bubble that was never
                // persisted.
                try await withChatTimeout {
                    try await supabase
                        .from("messages")
                        .insert(payload)
                        .select()
                        .single()
                        .execute()
                        .value
                }
            },
            onSent: { sent in
                // Advance the sync cursor to the server-stamped time of what
                // we just inserted, so loadNewer never rides an optimistic
                // client stamp.
                self.lastSyncedCreatedAt = sent.createdAt
                // Reliable delivery ping (see subscribeRealtime and
                // ChatEngineCore.broadcastDeliveryPing): RLS-free broadcast so
                // every member's client fetches the new message even if
                // postgres_changes was withheld.
                ChatEngineCore.broadcastDeliveryPing(
                    on: self.realtimeChannel, event: "msg_new",
                    from: supabase.auth.currentSession?.user.id.uuidString ?? "")
            })
    }

    func resetUnread() { unreadCount = 0 }

    // MARK: - Local "last seen" marker (drives the unread-messages divider)

    /// The shared cursor for the group conversation — same key the
    /// hand-rolled code used, so no stored data moves.
    private func lastSeenCursor(_ propertyId: UUID) -> LastSeenCursor {
        LastSeenCursor(key: "chat.lastseen.\(propertyId.uuidString)")
    }

    /// The moment this device last had the conversation open. Device-local (not
    /// synced) — its only job is to place the "unread messages" divider.
    func lastSeen(propertyId: UUID) -> Date { lastSeenCursor(propertyId).date }

    /// The id of the first message the viewer hasn't seen yet — the earliest
    /// message from someone else newer than `since`. nil when all is caught up.
    /// Computed from the frozen `since` captured on open, so the divider stays
    /// put while reading instead of chasing `markRead`.
    func firstUnreadId(since: Date, myId: UUID?) -> UUID? {
        messages.first { $0.senderId != myId && ($0.date ?? .distantPast) > since }?.id
    }

    func markSeen(propertyId: UUID) {
        lastSeenCursor(propertyId).markSeen()
    }

    func togglePin(_ message: Message) async {
        let newValue = !(message.pinned ?? false)
        if let idx = messages.firstIndex(where: { $0.id == message.id }) { messages[idx].pinned = newValue }
        // Pins are group-wide, so go through a SECURITY DEFINER RPC that authorises
        // on property membership — the table's RLS only lets you update your own rows.
        struct P: Encodable { let p_message_id: String; let p_pinned: Bool }
        do {
            try await supabase.rpc("set_message_pinned",
                                   params: P(p_message_id: message.id.uuidString, p_pinned: newValue)).execute()
        } catch {
            // Roll back the optimistic toggle if the write was rejected.
            if let idx = messages.firstIndex(where: { $0.id == message.id }) { messages[idx].pinned = !newValue }
        }
    }

    func toggleMark(_ message: Message) async {
        let newValue = !(message.isMarked ?? false)
        if let idx = messages.firstIndex(where: { $0.id == message.id }) { messages[idx].isMarked = newValue }
        struct M: Encodable { let p_message_id: String; let p_marked: Bool }
        do {
            try await supabase.rpc("set_message_marked",
                                   params: M(p_message_id: message.id.uuidString, p_marked: newValue)).execute()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == message.id }) { messages[idx].isMarked = !newValue }
        }
    }

    // MARK: - Read receipts

    /// Builds a receipt query scoped to ONE conversation. The receipt tables
    /// carry no group column, so the scope rides an inner join on the parent
    /// message's group_id (null-safe: the main chat is group_id IS NULL).
    /// Property-wide loads made the main chat and every community group load
    /// each other's receipts.
    private static func scopedReceiptQuery(
        _ table: String, propertyId: UUID, groupId: UUID?
    ) -> PostgrestFilterBuilder {
        let query = supabase
            .from(table)
            .select("*, messages!inner(group_id)")
            .eq("property_id", value: propertyId.uuidString)
        if let gid = groupId {
            return query.eq("messages.group_id", value: gid.uuidString)
        }
        return query.filter("messages.group_id", operator: "is", value: "null")
    }

    /// Loads this conversation's read receipts and groups them by message id.
    /// Fails silently if the table isn't available yet so chat keeps working.
    func loadReads(propertyId: UUID, groupId: UUID?) async {
        let myId = supabase.auth.currentSession?.user.id
        guard let rows: [MessageRead] = try? await Self.scopedReceiptQuery(
            "message_reads", propertyId: propertyId, groupId: groupId)
            .execute()
            .value
        else { return }

        // A receipt only counts as "seen by someone else" if another user read it.
        let others = rows.filter { $0.userId != myId }
        reads = Dictionary(grouping: others, by: { $0.messageId })
    }

    /// Marks every message I didn't send as read by me (upsert, idempotent).
    func markRead(propertyId: UUID, readerName: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        let toMark = messages.filter { $0.senderId != uid }
        guard !toMark.isEmpty else { return }

        struct ReadUpsert: Encodable {
            let message_id: String
            let property_id: String
            let user_id: String
            let reader_name: String
        }
        let payload = toMark.map {
            ReadUpsert(
                message_id: $0.id.uuidString,
                property_id: propertyId.uuidString,
                user_id: uid.uuidString,
                reader_name: readerName
            )
        }
        _ = try? await supabase
            .from("message_reads")
            .upsert(payload, onConflict: "message_id,user_id", ignoreDuplicates: true)
            .execute()
        unreadCount = 0
    }

    /// Subscribes to read receipt changes so the sender sees "seen" updates
    /// live. The topic carries the group scope: the main chat and a community
    /// group used to claim the SAME "message_reads:{propertyId}" topic, and
    /// the realtime client returns the already-subscribed channel for a
    /// duplicate topic — the second conversation's callbacks were silently
    /// dropped and its receipts never updated.
    func subscribeReads(propertyId: UUID, groupId: UUID?) async {
        let scope = groupId?.uuidString ?? "main"
        let topic = "message_reads:\(propertyId.uuidString):\(scope)"
        // Liveness idempotency (audit 2026-07-21): a repeat call for the
        // SAME scope keeps the live channel — a second call used to append
        // duplicate handlers and re-join the topic. A scope change tears
        // down cleanly (real leave) first.
        if let ch = readsChannel, ch.topic.hasSuffix(topic),
           ch.status == .subscribed || ch.status == .subscribing { return }
        if readsChannel != nil { await unsubscribeReads() }
        let channel = realtimeAnon.channel(topic)
        readsSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reads",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadTasks["reads"]?.cancel()
                self.reloadTasks["reads"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
                    await self?.loadReads(propertyId: propertyId, groupId: groupId)
                }
            }
        })
        do {
            // Timeboxed: a hung handshake must not stall the thread's
            // appear chain on a never-recovering socket.
            try await withRealtimeTimeout(seconds: 15) {
                try await channel.subscribeWithError()
            }
            readsChannel = channel
        } catch {
            // No trace on failure (b1173: leave from every state).
            debugLog("Reads realtime subscribe failed:", error)
            readsSubs.removeAll()
            await channel.unsubscribe()
            await realtimeAnon.removeChannel(channel)
        }
    }

    func unsubscribeReads() async {
        readsSubs.removeAll()
        if let ch = readsChannel {
            await ch.unsubscribe()   // real leave from every state (b1173)
            await realtimeAnon.removeChannel(ch)
            readsChannel = nil
        }
    }

    // MARK: - Delivery receipts

    /// Loads this conversation's delivery receipts, grouped by message id
    /// (excludes my own device's receipts so they count as "delivered to others").
    func loadDeliveries(propertyId: UUID, groupId: UUID?) async {
        let myId = supabase.auth.currentSession?.user.id
        guard let rows: [MessageDelivery] = try? await Self.scopedReceiptQuery(
            "message_deliveries", propertyId: propertyId, groupId: groupId)
            .execute()
            .value
        else { return }
        let others = rows.filter { $0.userId != myId }
        deliveries = Dictionary(grouping: others, by: { $0.messageId })
    }

    /// Records that my device received every message I didn't send (upsert, idempotent).
    func markDelivered(propertyId: UUID, delivererName: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        let toMark = messages.filter { $0.senderId != uid }
        guard !toMark.isEmpty else { return }

        struct DeliveryUpsert: Encodable {
            let message_id: String
            let property_id: String
            let user_id: String
            let deliverer_name: String
        }
        let payload = toMark.map {
            DeliveryUpsert(
                message_id: $0.id.uuidString,
                property_id: propertyId.uuidString,
                user_id: uid.uuidString,
                deliverer_name: delivererName
            )
        }
        _ = try? await supabase
            .from("message_deliveries")
            .upsert(payload, onConflict: "message_id,user_id", ignoreDuplicates: true)
            .execute()
    }

    /// Subscribes to delivery changes so the sender's ticks advance live.
    /// Topic is group-scoped — see subscribeReads for why.
    func subscribeDeliveries(propertyId: UUID, groupId: UUID?) async {
        let scope = groupId?.uuidString ?? "main"
        let topic = "message_deliveries:\(propertyId.uuidString):\(scope)"
        // Liveness idempotency (audit 2026-07-21): a repeat call for the
        // SAME scope keeps the live channel — a second call used to append
        // duplicate handlers and re-join the topic. A scope change tears
        // down cleanly (real leave) first.
        if let ch = deliveriesChannel, ch.topic.hasSuffix(topic),
           ch.status == .subscribed || ch.status == .subscribing { return }
        if deliveriesChannel != nil { await unsubscribeDeliveries() }
        let channel = realtimeAnon.channel(topic)
        deliveriesSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_deliveries",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadTasks["deliveries"]?.cancel()
                self.reloadTasks["deliveries"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
                    await self?.loadDeliveries(propertyId: propertyId, groupId: groupId)
                }
            }
        })
        do {
            // Timeboxed: a hung handshake must not stall the thread's
            // appear chain on a never-recovering socket.
            try await withRealtimeTimeout(seconds: 15) {
                try await channel.subscribeWithError()
            }
            deliveriesChannel = channel
        } catch {
            // No trace on failure (b1173: leave from every state).
            debugLog("Deliveries realtime subscribe failed:", error)
            deliveriesSubs.removeAll()
            await channel.unsubscribe()
            await realtimeAnon.removeChannel(channel)
        }
    }

    func unsubscribeDeliveries() async {
        deliveriesSubs.removeAll()
        if let ch = deliveriesChannel {
            await ch.unsubscribe()   // real leave from every state (b1173)
            await realtimeAnon.removeChannel(ch)
            deliveriesChannel = nil
        }
    }

    // MARK: - Reactions

    func loadReactions(propertyId: UUID, groupId: UUID?) async {
        guard let rows: [MessageReaction] = try? await Self.scopedReceiptQuery(
            "message_reactions", propertyId: propertyId, groupId: groupId)
            .execute()
            .value
        else { return }
        reactions = Dictionary(grouping: rows, by: { $0.messageId })
    }

    func toggleReaction(messageId: UUID, propertyId: UUID, emoji: String, reactorName: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }

        let existing = reactions[messageId]?.first(where: { $0.userId == uid })
        let removing = existing?.emoji == emoji
        // Snapshot for rollback if the network write fails.
        let snapshot = reactions[messageId]

        // --- Optimistic local update so the reaction appears instantly ---
        reactions[messageId]?.removeAll { $0.userId == uid }
        if !removing {
            let local = MessageReaction(
                id: UUID(),
                messageId: messageId,
                propertyId: propertyId,
                userId: uid,
                reactorName: reactorName,
                emoji: emoji,
                createdAt: ISODate.string(from: Date())
            )
            reactions[messageId, default: []].append(local)
        }
        if reactions[messageId]?.isEmpty == true { reactions.removeValue(forKey: messageId) }

        // --- Persist (shared sequence — P5, ChatEngineCore) ---
        do {
            try await ChatEngineCore.persistReactionToggle(
                messageId: messageId, propertyId: propertyId, userId: uid,
                reactorName: reactorName, emoji: emoji,
                removeExisting: existing != nil,
                insertNew: !removing)
        } catch {
            // Roll back the optimistic change on failure.
            if let snapshot { reactions[messageId] = snapshot }
            else { reactions.removeValue(forKey: messageId) }
        }
    }

    /// Topic is group-scoped — see subscribeReads for why.
    func subscribeReactions(propertyId: UUID, groupId: UUID?) async {
        let scope = groupId?.uuidString ?? "main"
        let topic = "message_reactions:\(propertyId.uuidString):\(scope)"
        // Liveness idempotency (audit 2026-07-21): a repeat call for the
        // SAME scope keeps the live channel — a second call used to append
        // duplicate handlers and re-join the topic. A scope change tears
        // down cleanly (real leave) first.
        if let ch = reactionsChannel, ch.topic.hasSuffix(topic),
           ch.status == .subscribed || ch.status == .subscribing { return }
        if reactionsChannel != nil { await unsubscribeReactions() }
        let channel = realtimeAnon.channel(topic)
        reactionsSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reactions",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadTasks["reactions"]?.cancel()
                self.reloadTasks["reactions"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
                    await self?.loadReactions(propertyId: propertyId, groupId: groupId)
                }
            }
        })
        do {
            // Timeboxed: a hung handshake must not stall the thread's
            // appear chain on a never-recovering socket.
            try await withRealtimeTimeout(seconds: 15) {
                try await channel.subscribeWithError()
            }
            reactionsChannel = channel
        } catch {
            // No trace on failure (b1173: leave from every state).
            debugLog("Reactions realtime subscribe failed:", error)
            reactionsSubs.removeAll()
            await channel.unsubscribe()
            await realtimeAnon.removeChannel(channel)
        }
    }

    func unsubscribeReactions() async {
        reactionsSubs.removeAll()
        if let ch = reactionsChannel {
            await ch.unsubscribe()   // real leave from every state (b1173)
            await realtimeAnon.removeChannel(ch)
            reactionsChannel = nil
        }
    }

    // MARK: - Poll votes

    var pollVotes: [UUID: [PollVote]] = [:]
    private var pollVotesChannel: RealtimeChannelV2?

    func loadPollVotes(propertyId: UUID, groupId: UUID?) async {
        guard let rows: [PollVote] = try? await Self.scopedReceiptQuery(
            "message_poll_votes", propertyId: propertyId, groupId: groupId)
            .execute()
            .value
        else { return }
        pollVotes = Dictionary(grouping: rows, by: { $0.messageId })
    }

    func togglePollVote(messageId: UUID, propertyId: UUID, optionIndex: Int, voterName: String, multi: Bool) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        let mine = pollVotes[messageId]?.filter { $0.userId == uid } ?? []
        let already = mine.contains { $0.optionIndex == optionIndex }

        if already {
            _ = try? await supabase.from("message_poll_votes").delete()
                .eq("message_id", value: messageId.uuidString)
                .eq("user_id", value: uid.uuidString)
                .eq("option_index", value: optionIndex)
                .execute()
        } else {
            if !multi {
                _ = try? await supabase.from("message_poll_votes").delete()
                    .eq("message_id", value: messageId.uuidString)
                    .eq("user_id", value: uid.uuidString)
                    .execute()
            }
            struct V: Encodable {
                let message_id: String; let property_id: String
                let user_id: String; let voter_name: String; let option_index: Int
            }
            _ = try? await supabase.from("message_poll_votes").insert(
                V(message_id: messageId.uuidString, property_id: propertyId.uuidString,
                  user_id: uid.uuidString, voter_name: voterName, option_index: optionIndex)
            ).execute()
        }
        await loadPollVotes(propertyId: propertyId, groupId: currentGroupId)
    }

    /// Topic is group-scoped — see subscribeReads for why.
    func subscribePollVotes(propertyId: UUID, groupId: UUID?) async {
        let scope = groupId?.uuidString ?? "main"
        let topic = "message_poll_votes:\(propertyId.uuidString):\(scope)"
        // Liveness idempotency (audit 2026-07-21): a repeat call for the
        // SAME scope keeps the live channel — a second call used to append
        // duplicate handlers and re-join the topic. A scope change tears
        // down cleanly (real leave) first.
        if let ch = pollVotesChannel, ch.topic.hasSuffix(topic),
           ch.status == .subscribed || ch.status == .subscribing { return }
        if pollVotesChannel != nil { await unsubscribePollVotes() }
        let channel = realtimeAnon.channel(topic)
        pollVotesSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_poll_votes",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadTasks["pollVotes"]?.cancel()
                self.reloadTasks["pollVotes"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
                    await self?.loadPollVotes(propertyId: propertyId, groupId: groupId)
                }
            }
        })
        do {
            // Timeboxed: a hung handshake must not stall the thread's
            // appear chain on a never-recovering socket.
            try await withRealtimeTimeout(seconds: 15) {
                try await channel.subscribeWithError()
            }
            pollVotesChannel = channel
        } catch {
            // No trace on failure (b1173: leave from every state).
            debugLog("Poll-votes realtime subscribe failed:", error)
            pollVotesSubs.removeAll()
            await channel.unsubscribe()
            await realtimeAnon.removeChannel(channel)
        }
    }

    func unsubscribePollVotes() async {
        pollVotesSubs.removeAll()
        if let ch = pollVotesChannel {
            await ch.unsubscribe()   // real leave from every state (b1173)
            await realtimeAnon.removeChannel(ch)
            pollVotesChannel = nil
        }
    }

    func unsubscribeAll() async {
        reloadTasks.values.forEach { $0.cancel() }
        reloadTasks.removeAll()
        activity.reset()
        activity.channel = nil
        await unsubscribe()
        await unsubscribeReads()
        await unsubscribeDeliveries()
        await unsubscribeReactions()
        await unsubscribePollVotes()
    }
}

// MARK: - Server-side search
//
// The conversations search used to scan only the messages already loaded in
// memory, so anything older than the current page was invisible. These run
// the match on Postgres (ILIKE, bounded) and reach the whole history.

extension MessageService {
    /// Escapes LIKE wildcards so a user typing "100%" searches for the
    /// literal text instead of matching everything.
    static func likePattern(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    /// True when any group message in this property matches the query.
    func groupHasMatch(propertyId: UUID, query: String) async -> Bool {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = (try? await supabase.from("messages")
            .select("id")
            .eq("property_id", value: propertyId.uuidString)
            .is("conversation_id", value: nil)
            .ilike("body", pattern: Self.likePattern(query))
            .limit(1)
            .execute().value) ?? []
        return !rows.isEmpty
    }
}

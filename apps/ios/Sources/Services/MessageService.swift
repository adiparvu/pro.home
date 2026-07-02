import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class MessageService {
    var messages: [Message] = []
    var isLoading = false
    var error: String?
    var unreadCount = 0
    /// Read receipts grouped by message id (excludes the receipts I created for myself).
    var reads: [UUID: [MessageRead]] = [:]
    /// Delivery receipts grouped by message id (excludes my own device's receipts).
    var deliveries: [UUID: [MessageDelivery]] = [:]
    /// Emoji reactions grouped by message id.
    var reactions: [UUID: [MessageReaction]] = [:]

    private var realtimeChannel: RealtimeChannelV2?
    private var readsChannel: RealtimeChannelV2?
    private var deliveriesChannel: RealtimeChannelV2?
    private var reactionsChannel: RealtimeChannelV2?
    /// Retained postgres-change subscription handles. `onPostgresChange`
    /// (which replaced the removed async-stream `postgresChange`) returns a
    /// handle whose deinit removes the callback, so it must be held for the
    /// callback to keep firing. Cleared in `unsubscribeAll`; per-channel
    /// removeChannel also tears the callbacks down.
    private var postgresSubs: [RealtimeSubscription] = []

    // MARK: - Typing indicator
    var typingNames: Set<String> = []
    var myName: String = ""
    private var typingSub: RealtimeSubscription?
    private var typingTasks: [String: Task<Void, Never>] = [:]
    /// Coalesces bursts of realtime events so a flurry of changes triggers a
    /// single reload per quiet window instead of one reload per event (C2). Same
    /// reload code runs — just debounced — so the displayed data stays correct.
    private var reloadTasks: [String: Task<Void, Never>] = [:]

    func sendTyping() {
        guard let ch = realtimeChannel, !myName.isEmpty else { return }
        Task { await ch.broadcast(event: "typing", message: ["name": .string(myName)]) }
    }

    private func handleTyping(_ name: String) {
        guard !name.isEmpty, name != myName else { return }
        typingNames.insert(name)
        typingTasks[name]?.cancel()
        typingTasks[name] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.typingNames.remove(name)
        }
    }

    /// Communities: the group this service instance is scoped to. nil = main group.
    /// Set on load() and reused by pagination / send so a group chat stays inside
    /// its group_id without threading it through every call site.
    private(set) var currentGroupId: UUID?

    func load(propertyId: UUID, groupId: UUID? = nil) async {
        // Unsubscribe from any previous property's channels before loading new data.
        await unsubscribeAll()
        currentGroupId = groupId
        isLoading = true
        defer { isLoading = false }
        do {
            // Load the most recent page (newest first from the DB, shown oldest→newest).
            var query = supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
            if let gid = groupId { query = query.eq("group_id", value: gid.uuidString) }
            let rows: [Message] = try await query
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value
            let hidden = hiddenIds()
            messages = rows.reversed().filter { !hidden.contains($0.id) }
            hasMoreOlder = rows.count == Self.pageSize
        } catch {
            self.error = error.localizedDescription
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
                .lt("created_at", value: oldest)
            if let gid = currentGroupId { query = query.eq("group_id", value: gid.uuidString) }
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
            self.error = error.localizedDescription
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
            if let gid = currentGroupId { query = query.eq("group_id", value: gid.uuidString) }
            if let newest = messages.last?.createdAt {
                query = query.gt("created_at", value: newest)
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
            return fresh.count
        } catch {
            return 0
        }
    }

    func subscribeRealtime(propertyId: UUID) async {
        let channel = supabase.realtimeV2.channel("messages:\(propertyId.uuidString)")
        // Callbacks must be registered before subscribing.
        postgresSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let added = await self.loadNewer(propertyId: propertyId)
                guard added > 0 else { return }
                // Count only messages from others as unread — not my own echoes, and
                // not a forced +1 when loadNewer found nothing new (the old drift bug).
                let myId = supabase.auth.currentSession?.user.id
                self.unreadCount += self.messages.suffix(added).filter { $0.senderId != myId }.count
            }
        })
        typingSub = channel.onBroadcast(event: "typing") { [weak self] json in
            if case let .string(name)? = json["name"] {
                Task { @MainActor in self?.handleTyping(name) }
            }
        }
        try? await channel.subscribeWithError()
        realtimeChannel = channel
    }

    func unsubscribe() async {
        if let ch = realtimeChannel {
            await supabase.realtimeV2.removeChannel(ch)
            realtimeChannel = nil
        }
    }

    func deleteMessage(id: UUID) async {
        do {
            try await supabase
                .from("messages")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            messages.removeAll { $0.id == id }
        } catch {
#if DEBUG
            print("[Chat] delete error: \(error)")
#endif
        }
    }

    /// Delete for everyone — keeps the row but replaces it with a tombstone.
    func deleteForEveryone(id: UUID) async {
        struct D: Encodable { let deleted_for_all: Bool }
        do {
            try await supabase.from("messages").update(D(deleted_for_all: true))
                .eq("id", value: id.uuidString).execute()
            if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].deletedForAll = true }
        } catch {
#if DEBUG
            print("[Chat] deleteForEveryone error: \(error)")
#endif
        }
    }

    /// Delete for me — hides the message locally only (persists across reloads).
    func deleteForMe(id: UUID) {
        var h = hiddenIds()
        h.insert(id)
        UserDefaults.standard.set(h.map(\.uuidString), forKey: Self.hiddenKey)
        messages.removeAll { $0.id == id }
    }

    func editMessage(id: UUID, newBody: String) async {
        struct E: Encodable { let body: String; let edited_at: String }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        do {
            try await supabase.from("messages").update(E(body: newBody, edited_at: nowISO))
                .eq("id", value: id.uuidString).execute()
            if let i = messages.firstIndex(where: { $0.id == id }) {
                messages[i].body = newBody
                messages[i].editedAt = nowISO
            }
        } catch {
#if DEBUG
            print("[Chat] editMessage error: \(error)")
#endif
        }
    }

    private static let hiddenKey = "chat.hidden.ids"
    private func hiddenIds() -> Set<UUID> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        return Set(arr.compactMap { UUID(uuidString: $0) })
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
            ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(ttl))
            : nil

        let payload = NewMessage(
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

        let sent: Message = try await supabase
            .from("messages")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        messages.append(sent)
    }

    func resetUnread() { unreadCount = 0 }

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

    /// Loads all read receipts for the property and groups them by message id.
    /// Fails silently if the table isn't available yet so chat keeps working.
    func loadReads(propertyId: UUID) async {
        let myId = supabase.auth.currentSession?.user.id
        guard let rows: [MessageRead] = try? await supabase
            .from("message_reads")
            .select()
            .eq("property_id", value: propertyId.uuidString)
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

    /// Subscribes to read receipt changes so the sender sees "seen" updates live.
    func subscribeReads(propertyId: UUID) async {
        let channel = supabase.realtimeV2.channel("message_reads:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reads",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reloadTasks["reads"]?.cancel()
                self.reloadTasks["reads"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.loadReads(propertyId: propertyId)
                }
            }
        })
        try? await channel.subscribeWithError()
        readsChannel = channel
    }

    func unsubscribeReads() async {
        if let ch = readsChannel {
            await supabase.realtimeV2.removeChannel(ch)
            readsChannel = nil
        }
    }

    // MARK: - Delivery receipts

    /// Loads delivery receipts for the property, grouped by message id
    /// (excludes my own device's receipts so they count as "delivered to others").
    func loadDeliveries(propertyId: UUID) async {
        let myId = supabase.auth.currentSession?.user.id
        guard let rows: [MessageDelivery] = try? await supabase
            .from("message_deliveries")
            .select()
            .eq("property_id", value: propertyId.uuidString)
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
    func subscribeDeliveries(propertyId: UUID) async {
        let channel = supabase.realtimeV2.channel("message_deliveries:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_deliveries",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reloadTasks["deliveries"]?.cancel()
                self.reloadTasks["deliveries"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.loadDeliveries(propertyId: propertyId)
                }
            }
        })
        try? await channel.subscribeWithError()
        deliveriesChannel = channel
    }

    func unsubscribeDeliveries() async {
        if let ch = deliveriesChannel {
            await supabase.realtimeV2.removeChannel(ch)
            deliveriesChannel = nil
        }
    }

    // MARK: - Reactions

    func loadReactions(propertyId: UUID) async {
        guard let rows: [MessageReaction] = try? await supabase
            .from("message_reactions")
            .select()
            .eq("property_id", value: propertyId.uuidString)
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
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            reactions[messageId, default: []].append(local)
        }
        if reactions[messageId]?.isEmpty == true { reactions.removeValue(forKey: messageId) }

        // --- Persist ---
        do {
            if existing != nil {
                try await supabase
                    .from("message_reactions")
                    .delete()
                    .eq("message_id", value: messageId.uuidString)
                    .eq("user_id", value: uid.uuidString)
                    .execute()
            }
            if !removing {
                struct ReactPayload: Encodable {
                    let message_id: String
                    let property_id: String
                    let user_id: String
                    let reactor_name: String
                    let emoji: String
                }
                let payload = ReactPayload(
                    message_id: messageId.uuidString,
                    property_id: propertyId.uuidString,
                    user_id: uid.uuidString,
                    reactor_name: reactorName,
                    emoji: emoji
                )
                try await supabase
                    .from("message_reactions")
                    .insert(payload)
                    .execute()
            }
        } catch {
            // Roll back the optimistic change on failure.
            if let snapshot { reactions[messageId] = snapshot }
            else { reactions.removeValue(forKey: messageId) }
        }
    }

    func subscribeReactions(propertyId: UUID) async {
        let channel = supabase.realtimeV2.channel("message_reactions:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reactions",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reloadTasks["reactions"]?.cancel()
                self.reloadTasks["reactions"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.loadReactions(propertyId: propertyId)
                }
            }
        })
        try? await channel.subscribeWithError()
        reactionsChannel = channel
    }

    func unsubscribeReactions() async {
        if let ch = reactionsChannel {
            await supabase.realtimeV2.removeChannel(ch)
            reactionsChannel = nil
        }
    }

    // MARK: - Poll votes

    var pollVotes: [UUID: [PollVote]] = [:]
    private var pollVotesChannel: RealtimeChannelV2?

    func loadPollVotes(propertyId: UUID) async {
        guard let rows: [PollVote] = try? await supabase
            .from("message_poll_votes")
            .select()
            .eq("property_id", value: propertyId.uuidString)
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
        await loadPollVotes(propertyId: propertyId)
    }

    func subscribePollVotes(propertyId: UUID) async {
        let channel = supabase.realtimeV2.channel("message_poll_votes:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_poll_votes",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reloadTasks["pollVotes"]?.cancel()
                self.reloadTasks["pollVotes"] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.loadPollVotes(propertyId: propertyId)
                }
            }
        })
        try? await channel.subscribeWithError()
        pollVotesChannel = channel
    }

    func unsubscribePollVotes() async {
        if let ch = pollVotesChannel {
            await supabase.realtimeV2.removeChannel(ch)
            pollVotesChannel = nil
        }
    }

    func unsubscribeAll() async {
        reloadTasks.values.forEach { $0.cancel() }
        reloadTasks.removeAll()
        postgresSubs.removeAll()
        await unsubscribe()
        await unsubscribeReads()
        await unsubscribeDeliveries()
        await unsubscribeReactions()
        await unsubscribePollVotes()
    }
}

import Foundation
import Supabase

@MainActor
final class MessageService: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var unreadCount = 0
    /// Read receipts grouped by message id (excludes the receipts I created for myself).
    @Published var reads: [UUID: [MessageRead]] = [:]
    /// Delivery receipts grouped by message id (excludes my own device's receipts).
    @Published var deliveries: [UUID: [MessageDelivery]] = [:]
    /// Emoji reactions grouped by message id.
    @Published var reactions: [UUID: [MessageReaction]] = [:]

    private var realtimeChannel: RealtimeChannelV2?
    private var readsChannel: RealtimeChannelV2?
    private var deliveriesChannel: RealtimeChannelV2?
    private var reactionsChannel: RealtimeChannelV2?

    // MARK: - Typing indicator
    @Published var typingNames: Set<String> = []
    var myName: String = ""
    private var typingSub: RealtimeSubscription?
    private var typingTasks: [String: Task<Void, Never>] = [:]

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

    func load(propertyId: UUID) async {
        // Unsubscribe from any previous property's channels before loading new data.
        await unsubscribeAll()
        isLoading = true
        defer { isLoading = false }
        do {
            // Load the most recent page (newest first from the DB, shown oldest→newest).
            let rows: [Message] = try await supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
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
    @Published var hasMoreOlder = false
    @Published var isLoadingOlder = false

    /// Loads the next older page and prepends it (for "load older" / scroll-to-top).
    func loadOlder(propertyId: UUID) async {
        guard hasMoreOlder, !isLoadingOlder, let oldest = messages.first?.createdAt else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let rows: [Message] = try await supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .lt("created_at", value: oldest)
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
        let channel = await supabase.realtimeV2.channel("messages:\(propertyId.uuidString)")
        let changes = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        typingSub = channel.onBroadcast(event: "typing") { [weak self] json in
            if case let .string(name)? = json["name"] {
                Task { @MainActor in self?.handleTyping(name) }
            }
        }
        await channel.subscribe()
        realtimeChannel = channel

        for await _ in changes {
            let added = await loadNewer(propertyId: propertyId)
            unreadCount += max(added, 1)
        }
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
            reply_to: replyTo
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
        struct P: Encodable { let pinned: Bool }
        try? await supabase.from("messages").update(P(pinned: newValue))
            .eq("id", value: message.id.uuidString).execute()
    }

    func toggleMark(_ message: Message) async {
        let newValue = !(message.isMarked ?? false)
        if let idx = messages.firstIndex(where: { $0.id == message.id }) { messages[idx].isMarked = newValue }
        struct M: Encodable { let is_marked: Bool }
        try? await supabase.from("messages").update(M(is_marked: newValue))
            .eq("id", value: message.id.uuidString).execute()
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
        try? await supabase
            .from("message_reads")
            .upsert(payload, onConflict: "message_id,user_id", ignoreDuplicates: true)
            .execute()
        unreadCount = 0
    }

    /// Subscribes to read receipt changes so the sender sees "seen" updates live.
    func subscribeReads(propertyId: UUID) async {
        let channel = await supabase.realtimeV2.channel("message_reads:\(propertyId.uuidString)")
        let changes = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reads",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        await channel.subscribe()
        readsChannel = channel

        for await _ in changes {
            await loadReads(propertyId: propertyId)
        }
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
        try? await supabase
            .from("message_deliveries")
            .upsert(payload, onConflict: "message_id,user_id", ignoreDuplicates: true)
            .execute()
    }

    /// Subscribes to delivery changes so the sender's ticks advance live.
    func subscribeDeliveries(propertyId: UUID) async {
        let channel = await supabase.realtimeV2.channel("message_deliveries:\(propertyId.uuidString)")
        let changes = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_deliveries",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        await channel.subscribe()
        deliveriesChannel = channel

        for await _ in changes {
            await loadDeliveries(propertyId: propertyId)
        }
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

        if existing?.emoji == emoji {
            // Remove — user tapped their own existing reaction
            try? await supabase
                .from("message_reactions")
                .delete()
                .eq("message_id", value: messageId.uuidString)
                .eq("user_id", value: uid.uuidString)
                .execute()
            reactions[messageId]?.removeAll { $0.userId == uid }
            if reactions[messageId]?.isEmpty == true { reactions.removeValue(forKey: messageId) }
        } else {
            // Remove old emoji first (if switching)
            if existing != nil {
                try? await supabase
                    .from("message_reactions")
                    .delete()
                    .eq("message_id", value: messageId.uuidString)
                    .eq("user_id", value: uid.uuidString)
                    .execute()
                reactions[messageId]?.removeAll { $0.userId == uid }
            }
            // Insert new reaction
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
            if let r: MessageReaction = try? await supabase
                .from("message_reactions")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value {
                reactions[messageId, default: []].append(r)
            }
        }
    }

    func subscribeReactions(propertyId: UUID) async {
        let channel = await supabase.realtimeV2.channel("message_reactions:\(propertyId.uuidString)")
        let changes = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reactions",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        await channel.subscribe()
        reactionsChannel = channel

        for await _ in changes {
            await loadReactions(propertyId: propertyId)
        }
    }

    func unsubscribeReactions() async {
        if let ch = reactionsChannel {
            await supabase.realtimeV2.removeChannel(ch)
            reactionsChannel = nil
        }
    }

    // MARK: - Poll votes

    @Published var pollVotes: [UUID: [PollVote]] = [:]
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
            try? await supabase.from("message_poll_votes").delete()
                .eq("message_id", value: messageId.uuidString)
                .eq("user_id", value: uid.uuidString)
                .eq("option_index", value: optionIndex)
                .execute()
        } else {
            if !multi {
                try? await supabase.from("message_poll_votes").delete()
                    .eq("message_id", value: messageId.uuidString)
                    .eq("user_id", value: uid.uuidString)
                    .execute()
            }
            struct V: Encodable {
                let message_id: String; let property_id: String
                let user_id: String; let voter_name: String; let option_index: Int
            }
            try? await supabase.from("message_poll_votes").insert(
                V(message_id: messageId.uuidString, property_id: propertyId.uuidString,
                  user_id: uid.uuidString, voter_name: voterName, option_index: optionIndex)
            ).execute()
        }
        await loadPollVotes(propertyId: propertyId)
    }

    func subscribePollVotes(propertyId: UUID) async {
        let channel = await supabase.realtimeV2.channel("message_poll_votes:\(propertyId.uuidString)")
        let changes = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_poll_votes",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        await channel.subscribe()
        pollVotesChannel = channel

        for await _ in changes {
            await loadPollVotes(propertyId: propertyId)
        }
    }

    func unsubscribePollVotes() async {
        if let ch = pollVotesChannel {
            await supabase.realtimeV2.removeChannel(ch)
            pollVotesChannel = nil
        }
    }

    func unsubscribeAll() async {
        await unsubscribe()
        await unsubscribeReads()
        await unsubscribeReactions()
        await unsubscribePollVotes()
    }
}

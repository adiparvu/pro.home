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
    /// Emoji reactions grouped by message id.
    @Published var reactions: [UUID: [MessageReaction]] = [:]

    private var realtimeChannel: RealtimeChannelV2?
    private var readsChannel: RealtimeChannelV2?
    private var reactionsChannel: RealtimeChannelV2?

    func load(propertyId: UUID) async {
        // Unsubscribe from any previous property's channels before loading new data.
        await unsubscribeAll()
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [Message] = try await supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .limit(200)
                .execute()
                .value
            let hidden = hiddenIds()
            messages = rows.filter { !hidden.contains($0.id) }
        } catch {
            self.error = error.localizedDescription
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
        await channel.subscribe()
        realtimeChannel = channel

        for await _ in changes {
            await load(propertyId: propertyId)
            unreadCount += 1
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

    func unsubscribeAll() async {
        await unsubscribe()
        await unsubscribeReads()
        await unsubscribeReactions()
    }
}

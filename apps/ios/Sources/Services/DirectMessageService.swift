import Foundation
import Observation
import Supabase

// MARK: - DirectMessage model

struct DirectMessage: Identifiable, Codable {
    let id: UUID
    let senderName: String
    let recipientName: String
    var body: String
    let createdAt: String
    var replyTo: UUID?
    var deletedForAll: Bool?
    var editedAt: String?
    var pinned: Bool?
    var isMarked: Bool?
    var reactions: [String: String]?
    var readAt: String?
    var deliveredAt: String?
    // S8: stable identity (migration 081). sender_id is the authenticated sender's
    // auth.users id; the member ids are the parties' family_members ids.
    var senderId: UUID?
    var senderMemberId: UUID?
    var recipientMemberId: UUID?
    var expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body, pinned, reactions
        case senderName        = "sender_name"
        case recipientName      = "recipient_name"
        case senderId           = "sender_id"
        case senderMemberId     = "sender_member_id"
        case recipientMemberId  = "recipient_member_id"
        case expiresAt          = "expires_at"
        case createdAt     = "created_at"
        case replyTo       = "reply_to"
        case deletedForAll = "deleted_for_all"
        case editedAt      = "edited_at"
        case isMarked      = "is_marked"
        case readAt        = "read_at"
        case deliveredAt   = "delivered_at"
    }

    var timeDisplay: String {
        let d = ISODate.date(from: createdAt) ?? Date()
        return ISODate.timeOnly.string(from: d)
    }

    var date: Date? { ISODate.date(from: createdAt) }
}

// MARK: - DirectMessageService

@MainActor
@Observable
final class DirectMessageService {
    var dms: [DirectMessage] = []
    var isLoading = false

    /// Bumped whenever UserDefaults-backed local state (last-seen timestamps,
    /// hidden message ids) changes. Those aren't observable stored properties,
    /// so the derived reads (`messages`, `unreadCount`) touch this value to
    /// register an observation dependency and refresh when it changes.
    private var localRevision = 0

    @ObservationIgnored private var channel: RealtimeChannelV2?

    // MARK: - Typing indicator
    var typingNames: Set<String> = []
    var myName: String = ""
    @ObservationIgnored private var typingSub: RealtimeSubscription?
    @ObservationIgnored private var typingTasks: [String: Task<Void, Never>] = [:]

    func sendTyping() {
        guard let ch = channel, !myName.isEmpty else { return }
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

    // MARK: - Queries

    func messages(with partner: String, myName: String) -> [DirectMessage] {
        _ = localRevision  // observe local-state changes (hidden ids)
        let hidden = hiddenIds()
        return dms.filter {
            (($0.senderName == partner && $0.recipientName == myName) ||
             ($0.senderName == myName   && $0.recipientName == partner))
            && !hidden.contains($0.id)
        }
    }

    func lastMessage(with partner: String, myName: String) -> DirectMessage? {
        messages(with: partner, myName: myName).max { $0.createdAt < $1.createdAt }
    }

    func unreadCount(from partner: String, myName: String) -> Int {
        _ = localRevision  // observe local-state changes (last-seen timestamps)
        let lastSeen = lastSeenDate(for: partner)
        return dms.filter {
            $0.senderName == partner &&
            $0.recipientName == myName &&
            ($0.date ?? .distantPast) > lastSeen
        }.count
    }

    func markRead(partner: String) {
        UserDefaults.standard.set(Date(), forKey: "dm.lastseen.\(partner)")
        localRevision &+= 1
    }

    // MARK: - Persistence

    func load(propertyId: UUID, myName: String) async {
        isLoading = true
        defer { isLoading = false }
        guard !myName.isEmpty else { return }
        do {
            // Fetch the most recent 1000 (newest first), then show oldest→newest.
            // Previously this ordered ascending, which returned the *oldest* 1000
            // and could hide recent messages once a property had many DMs.
            let rows: [DirectMessage] = try await supabase
                .from("direct_messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .or("sender_name.eq.\(myName),recipient_name.eq.\(myName)")
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value
            dms = rows.reversed()
            // Anything addressed to us that this device just fetched counts as
            // delivered — stamp it so the sender's ticks advance to "delivered".
            await markDelivered(myName: myName)
        } catch {
            // table may not exist yet — fail silently
        }
    }

    /// Marks all messages addressed to `myName` as delivered (best-effort).
    /// Idempotent: only touches rows that have no delivered_at yet, so the
    /// realtime update it triggers settles after one extra reload.
    func markDelivered(myName: String) async {
        let undelivered = dms.filter {
            $0.recipientName == myName && $0.deliveredAt == nil
        }
        guard !undelivered.isEmpty else { return }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        for m in undelivered {
            try? await supabase
                .from("direct_messages")
                .update(["delivered_at": nowISO])
                .eq("id", value: m.id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == m.id }) { dms[i].deliveredAt = nowISO }
        }
    }

    func subscribeRealtime(propertyId: UUID, myName: String) async {
        let ch = await supabase.realtimeV2.channel("direct_messages:\(propertyId.uuidString)")
        let inserts = await ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        let updates = await ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        typingSub = ch.onBroadcast(event: "typing") { [weak self] json in
            if case let .string(name)? = json["name"] {
                Task { @MainActor in self?.handleTyping(name) }
            }
        }
        await ch.subscribe()
        channel = ch

        // Updates (reactions, read receipts, pin/mark, edit, delete-for-all) on a side task.
        Task { [weak self] in
            for await _ in updates {
                await self?.load(propertyId: propertyId, myName: myName)
            }
        }

        for await _ in inserts {
            await load(propertyId: propertyId, myName: myName)
        }
    }

    func unsubscribe() async {
        if let ch = channel {
            await supabase.realtimeV2.removeChannel(ch)
            channel = nil
        }
    }

    func deleteMessage(id: UUID) async {
        do {
            try await supabase
                .from("direct_messages")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            dms.removeAll { $0.id == id }
        } catch {
#if DEBUG
            print("[DM] delete error: \(error)")
#endif
        }
    }

    /// Delete for everyone — keeps the row but replaces it with a tombstone.
    func deleteForEveryone(id: UUID) async {
        do {
            try await supabase
                .from("direct_messages")
                .update(["deleted_for_all": true])
                .eq("id", value: id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == id }) { dms[i].deletedForAll = true }
        } catch {
#if DEBUG
            print("[DM] deleteForEveryone error: \(error)")
#endif
        }
    }

    /// Delete for me — hides the row locally only.
    func deleteForMe(id: UUID) {
        var h = hiddenIds()
        h.insert(id)
        UserDefaults.standard.set(h.map(\.uuidString), forKey: Self.hiddenKey)
        localRevision &+= 1
    }

    func togglePin(_ msg: DirectMessage) async {
        let newVal = !(msg.pinned ?? false)
        do {
            try await supabase
                .from("direct_messages")
                .update(["pinned": newVal])
                .eq("id", value: msg.id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == msg.id }) { dms[i].pinned = newVal }
        } catch {
#if DEBUG
            print("[DM] togglePin error: \(error)")
#endif
        }
    }

    func toggleMark(_ msg: DirectMessage) async {
        let newVal = !(msg.isMarked ?? false)
        do {
            try await supabase
                .from("direct_messages")
                .update(["is_marked": newVal])
                .eq("id", value: msg.id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == msg.id }) { dms[i].isMarked = newVal }
        } catch {
#if DEBUG
            print("[DM] toggleMark error: \(error)")
#endif
        }
    }

    func toggleReaction(_ msg: DirectMessage, emoji: String, myName: String) async {
        var map = msg.reactions ?? [:]
        if map[myName] == emoji { map.removeValue(forKey: myName) } else { map[myName] = emoji }
        do {
            try await supabase
                .from("direct_messages")
                .update(["reactions": map])
                .eq("id", value: msg.id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == msg.id }) { dms[i].reactions = map }
        } catch {
#if DEBUG
            print("[DM] toggleReaction error: \(error)")
#endif
        }
    }

    func editMessage(id: UUID, newBody: String) async {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        do {
            try await supabase
                .from("direct_messages")
                .update(["body": newBody, "edited_at": nowISO])
                .eq("id", value: id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == id }) {
                dms[i].body = newBody
                dms[i].editedAt = nowISO
            }
        } catch {
#if DEBUG
            print("[DM] editMessage error: \(error)")
#endif
        }
    }

    /// Marks incoming messages from `partner` as read (sets read_at) and updates local state.
    func markReadRemote(partner: String, myName: String) async {
        let unread = dms.filter {
            $0.senderName == partner && $0.recipientName == myName && $0.readAt == nil
        }
        guard !unread.isEmpty else { return }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        for m in unread {
            // Read implies delivered — backfill delivered_at if it was never set
            // so the ticks/details never show "read" without a "delivered".
            var payload = ["read_at": nowISO]
            if m.deliveredAt == nil { payload["delivered_at"] = nowISO }
            _ = try? await supabase
                .from("direct_messages")
                .update(payload)
                .eq("id", value: m.id.uuidString)
                .execute()
            if let i = dms.firstIndex(where: { $0.id == m.id }) {
                dms[i].readAt = nowISO
                if dms[i].deliveredAt == nil { dms[i].deliveredAt = nowISO }
            }
        }
    }

    // MARK: - Private helpers

    private static let hiddenKey = "dm.hidden.ids"

    private func hiddenIds() -> Set<UUID> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        return Set(arr.compactMap { UUID(uuidString: $0) })
    }

    private func lastSeenDate(for partner: String) -> Date {
        UserDefaults.standard.object(forKey: "dm.lastseen.\(partner)") as? Date ?? .distantPast
    }
}

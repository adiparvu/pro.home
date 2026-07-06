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
    /// Property the live channel is currently bound to, so repeated
    /// subscribe calls (re-entering the chat tab, opening a thread) are no-ops
    /// instead of stacking duplicate channels or tearing down a live one.
    @ObservationIgnored private var subscribedPropertyId: UUID?
    /// Retained postgres-change subscription handles (see MessageService).
    /// onPostgresChange's handle removes its callback on deinit, so it must be
    /// held for the callback to keep firing; cleared on unsubscribe.
    @ObservationIgnored private var postgresSubs: [RealtimeSubscription] = []

    // MARK: - Typing indicator
    var typingNames: Set<String> = []
    var myName: String = ""
    @ObservationIgnored private var typingSub: RealtimeSubscription?
    @ObservationIgnored private var typingTasks: [String: Task<Void, Never>] = [:]

    @ObservationIgnored private var lastTypingSentAt: Date = .distantPast
    /// Coalesces bursts of realtime events (a lively thread, a flurry of read
    /// receipts) into a single reload per quiet window, instead of refetching
    /// the whole conversation once per event.
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    private func scheduleReload(propertyId: UUID, myName: String) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.load(propertyId: propertyId, myName: myName)
        }
    }

    func sendTyping() {
        guard let ch = channel, !myName.isEmpty else { return }
        // Called on every keystroke — throttle to one broadcast per 2.5s
        // (receivers keep the indicator alive 4s per event, so it stays smooth).
        let now = Date()
        guard now.timeIntervalSince(lastTypingSentAt) > 2.5 else { return }
        lastTypingSentAt = now
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

    // MARK: - Older history (per conversation, server-paged)

    /// Conversations whose full server history is already in memory
    /// (an older-page fetch came back empty). Keyed by the partner's name.
    private(set) var exhaustedOlder: Set<String> = []
    var isLoadingOlder = false

    /// Pulls the next older page for one conversation and merges it in.
    /// Returns how many new rows arrived; 0 marks the thread exhausted so
    /// the UI can retire its load-older affordance.
    @discardableResult
    func loadOlder(propertyId: UUID, myName: String, otherName: String) async -> Int {
        guard !isLoadingOlder else { return 0 }
        let thread = messages(with: otherName, myName: myName)
        guard let oldest = thread.min(by: { $0.createdAt < $1.createdAt }) else { return 0 }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let rows = try await Self.fetchOlder(propertyId: propertyId, myName: myName,
                                                 otherName: otherName, before: oldest.createdAt)
            let known = Set(dms.map(\.id))
            let fresh = rows.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else {
                exhaustedOlder.insert(otherName)
                return 0
            }
            // The page is strictly older than everything in this thread, so
            // prepending (ascending) keeps per-thread order correct; other
            // threads are untouched by their own filters.
            dms.insert(contentsOf: fresh.reversed(), at: 0)
            return fresh.count
        } catch {
            return 0
        }
    }

    /// Network + JSON decode off the main actor.
    nonisolated private static func fetchRecent(propertyId: UUID, myName: String) async throws -> [DirectMessage] {
        try await supabase
            .from("direct_messages")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .or("sender_name.eq.\(myName),recipient_name.eq.\(myName)")
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
            .value
    }

    nonisolated private static func fetchOlder(propertyId: UUID, myName: String,
                                               otherName: String, before: String) async throws -> [DirectMessage] {
        try await supabase
            .from("direct_messages")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .or("and(sender_name.eq.\(myName),recipient_name.eq.\(otherName)),and(sender_name.eq.\(otherName),recipient_name.eq.\(myName))")
            .lt("created_at", value: before)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
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
            // The fetch + decode run off the main actor (nonisolated helper) —
            // this was the last big main-thread JSON decode in the app.
            let rows = try await Self.fetchRecent(propertyId: propertyId, myName: myName)
            dms = rows.reversed()
            exhaustedOlder.removeAll()
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
        let ids = undelivered.map { $0.id.uuidString }
        do {
            // One batched UPDATE instead of one write per message (the old N+1,
            // which also fired N realtime updates and made every other client
            // reload N times). Reflect locally only after it persists.
            try await supabase
                .from("direct_messages")
                .update(["delivered_at": nowISO])
                .in("id", values: ids)
                .execute()
            for m in undelivered {
                if let i = dms.firstIndex(where: { $0.id == m.id }) { dms[i].deliveredAt = nowISO }
            }
        } catch { return }
    }

    func subscribeRealtime(propertyId: UUID, myName: String) async {
        // Idempotent: already live for this property → keep it (don't let a
        // navigation push/pop tear down the channel while a thread is open).
        if channel != nil, subscribedPropertyId == propertyId { return }
        if channel != nil { await unsubscribe() }
        let ch = supabase.realtimeV2.channel("direct_messages:\(propertyId.uuidString)")
        // Inserts and updates (reactions, read receipts, pin/mark, edit,
        // delete-for-all) both just reload the conversation. Callbacks must be
        // registered before subscribing.
        postgresSubs.append(ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload(propertyId: propertyId, myName: myName) }
        })
        postgresSubs.append(ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload(propertyId: propertyId, myName: myName) }
        })
        typingSub = ch.onBroadcast(event: "typing") { [weak self] json in
            if case let .string(name)? = json["name"] {
                Task { @MainActor in self?.handleTyping(name) }
            }
        }
        try? await ch.subscribeWithError()
        channel = ch
        subscribedPropertyId = propertyId
    }

    func unsubscribe() async {
        postgresSubs.removeAll()
        typingSub = nil
        typingTasks.values.forEach { $0.cancel() }
        typingTasks.removeAll()
        typingNames.removeAll()
        reloadTask?.cancel()
        reloadTask = nil
        subscribedPropertyId = nil
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
            debugLog("[DM] delete error: \(error)")
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
            debugLog("[DM] deleteForEveryone error: \(error)")
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
            debugLog("[DM] togglePin error: \(error)")
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
            debugLog("[DM] toggleMark error: \(error)")
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
            debugLog("[DM] toggleReaction error: \(error)")
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
            debugLog("[DM] editMessage error: \(error)")
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
        // Read implies delivered, so rows with no delivered_at get both stamped.
        // Batch by which columns they need — at most two UPDATEs total instead
        // of one per message.
        let needBoth = unread.filter { $0.deliveredAt == nil }.map { $0.id.uuidString }
        let readOnly = unread.filter { $0.deliveredAt != nil }.map { $0.id.uuidString }
        do {
            if !needBoth.isEmpty {
                try await supabase.from("direct_messages")
                    .update(["read_at": nowISO, "delivered_at": nowISO])
                    .in("id", values: needBoth).execute()
            }
            if !readOnly.isEmpty {
                try await supabase.from("direct_messages")
                    .update(["read_at": nowISO])
                    .in("id", values: readOnly).execute()
            }
            // Reflect locally only after the writes land (see markDelivered).
            for m in unread {
                if let i = dms.firstIndex(where: { $0.id == m.id }) {
                    dms[i].readAt = nowISO
                    if dms[i].deliveredAt == nil { dms[i].deliveredAt = nowISO }
                }
            }
        } catch { return }
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

    /// This device's last-open time for a conversation — captured before
    /// `markRead` so the view can place the "unread messages" divider.
    func lastSeen(for partner: String) -> Date { lastSeenDate(for: partner) }

    /// The earliest message from `partner` newer than `since` — where the
    /// unread divider goes. `dms` is oldest→newest, so `.first` is the earliest.
    func firstUnreadId(from partner: String, myName: String, since: Date) -> UUID? {
        dms.first {
            $0.senderName == partner && $0.recipientName == myName &&
            ($0.date ?? .distantPast) > since
        }?.id
    }
}

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

// MARK: - Stable identity (Planul 2, phase B)
//
// Threads, ownership and read state key on ids — names are display snapshots
// that break on rename (the sole production DM's sender_name even carries a
// trailing space its member row doesn't have). Legacy rows without ids fall
// back to name matching until phase C retires it.

extension DirectMessage {
    /// Whether the signed-in user sent this message. sender_id is NOT NULL
    /// in practice (dm_insert requires it); the name check only covers rows
    /// from before migration 081.
    func isMine(myUserId: UUID?, myName: String) -> Bool {
        if let sid = senderId, let uid = myUserId { return sid == uid }
        return senderName == myName
    }

    /// Whether this message belongs to the 1-on-1 thread with `member`.
    func inThread(with member: FamilyMember, myUserId: UUID?, myName: String) -> Bool {
        if isMine(myUserId: myUserId, myName: myName) {
            if let rid = recipientMemberId { return rid == member.id }
            return recipientName == member.name
        }
        if let sid = senderMemberId { return sid == member.id }
        return senderName == member.name
    }
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
    /// The signed-in user's auth id — the stable half of "is this mine".
    /// Set on load; nil only before the first load (name fallback covers it).
    var myUserId: UUID?
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

    // MARK: - Unified send
    //
    // One persistent path for EVERY DM kind (text, photo, video, audio,
    // contact, forward). Media is uploaded first and its storage path is passed
    // as `body` — the bubble classifies it from the path prefix — so a single
    // insert covers them all. Optimistic append shows the bubble instantly; a
    // bounded insert means a hung network call fails fast; on any failure the
    // optimistic row rolls back and the error rethrows so the caller enqueues it
    // to the offline outbox instead of silently dropping the message.
    @discardableResult
    func send(propertyId: UUID?, senderName: String, recipient: FamilyMember,
              body: String, replyTo: UUID? = nil, expiresAt: String? = nil) async throws -> DirectMessage {
        let senderId = supabase.auth.currentSession?.user.id
        let clientId = UUID()
        let optimistic = DirectMessage(
            id: clientId, senderName: senderName, recipientName: recipient.name,
            body: body, createdAt: ISO8601DateFormatter().string(from: Date()),
            replyTo: replyTo,
            senderId: senderId,
            recipientMemberId: recipient.id,
            expiresAt: expiresAt)
        dms.append(optimistic)

        struct Payload: Encodable {
            let id: String
            let sender_name: String
            let recipient_name: String
            let body: String
            let property_id: String?
            let reply_to: String?
            let sender_id: String?
            let recipient_member_id: String?
            let expires_at: String?
        }
        let payload = Payload(
            id: clientId.uuidString, sender_name: senderName, recipient_name: recipient.name,
            body: body, property_id: propertyId?.uuidString,
            reply_to: replyTo?.uuidString, sender_id: senderId?.uuidString,
            recipient_member_id: recipient.id.uuidString, expires_at: expiresAt)
        do {
            let sent: DirectMessage = try await withChatTimeout {
                try await supabase
                    .from("direct_messages")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                    .value
            }
            if let i = dms.firstIndex(where: { $0.id == sent.id }) { dms[i] = sent }
            else { dms.append(sent) }
            return sent
        } catch {
            dms.removeAll { $0.id == clientId }
            throw error
        }
    }

    // MARK: - Queries

    func messages(with member: FamilyMember, myName: String) -> [DirectMessage] {
        _ = localRevision  // observe local-state changes (hidden ids)
        let hidden = hiddenIds()
        return dms.filter {
            $0.inThread(with: member, myUserId: myUserId, myName: myName)
            && !hidden.contains($0.id)
        }
    }

    // MARK: - Bulk conversation summaries (one pass, every partner)

    struct ConversationSummary {
        var last: DirectMessage?
        var unread: Int = 0
    }

    /// Everything the conversation list needs about every DM thread, built
    /// in ONE pass over the store and keyed by the partner's stable member
    /// id (ids survive renames; name matching only covers legacy rows).
    /// Same semantics as ever: hidden messages excluded, unread counts only
    /// inbound messages newer than the per-partner last-seen mark.
    func conversationSummaries(myName: String, members: [FamilyMember]) -> [UUID: ConversationSummary] {
        _ = localRevision  // observe hidden-ids / last-seen changes
        let hidden = hiddenIds()
        let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let byName = Dictionary(members.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [UUID: ConversationSummary] = [:]
        var seenDates: [UUID: Date] = [:]
        for m in dms where !hidden.contains(m.id) {
            let mine = m.isMine(myUserId: myUserId, myName: myName)
            let partner: FamilyMember? = mine
                ? (m.recipientMemberId.flatMap { byId[$0] } ?? byName[m.recipientName])
                : (m.senderMemberId.flatMap { byId[$0] } ?? byName[m.senderName])
            guard let partner else { continue }
            var s = out[partner.id] ?? ConversationSummary()
            if s.last.map({ m.createdAt > $0.createdAt }) ?? true { s.last = m }
            if !mine {
                let seen: Date
                if let cached = seenDates[partner.id] { seen = cached }
                else { seen = lastSeenDate(for: partner); seenDates[partner.id] = seen }
                if (m.date ?? .distantPast) > seen { s.unread += 1 }
            }
            out[partner.id] = s
        }
        return out
    }

    // MARK: - Older history (per conversation, server-paged)

    /// Conversations whose full server history is already in memory
    /// (an older-page fetch came back empty). Keyed by the partner's member id.
    private(set) var exhaustedOlder: Set<UUID> = []
    var isLoadingOlder = false

    /// Pulls the next older page for one conversation and merges it in.
    /// Returns how many new rows arrived; 0 marks the thread exhausted so
    /// the UI can retire its load-older affordance.
    @discardableResult
    func loadOlder(propertyId: UUID, myName: String, member: FamilyMember) async -> Int {
        guard !isLoadingOlder else { return 0 }
        let thread = messages(with: member, myName: myName)
        guard let oldest = thread.min(by: { $0.createdAt < $1.createdAt }) else { return 0 }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let rows = try await Self.fetchOlder(propertyId: propertyId, myName: myName,
                                                 myUserId: myUserId, member: member,
                                                 before: oldest.createdAt)
            let known = Set(dms.map(\.id))
            let fresh = rows.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else {
                exhaustedOlder.insert(member.id)
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

    /// Builds a PostgREST `or()` equality clause, quoting the value only when it
    /// contains reserved characters (`, . : ( )` or a double quote) or has edge
    /// whitespace. Quoting only when needed keeps the common path byte-identical
    /// to the previously shipped query (zero regression risk for plain names)
    /// while a name with punctuation — which used to corrupt the filter string —
    /// is now passed safely.
    nonisolated private static func orEq(_ column: String, _ value: String) -> String {
        let reserved = CharacterSet(charactersIn: ",.:()\"")
        let needsQuote = value.rangeOfCharacter(from: reserved) != nil
            || value != value.trimmingCharacters(in: .whitespaces)
        guard needsQuote else { return "\(column).eq.\(value)" }
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\(column).eq.\"\(escaped)\""
    }

    /// Network + JSON decode off the main actor. The sender_id clause makes
    /// my outbound rows rename-proof; the name clauses cover legacy rows and
    /// inbound mail (my own account may have no family_members row, so the
    /// recipient side can't be an id filter yet — phase C revisits).
    nonisolated private static func fetchRecent(propertyId: UUID, myName: String,
                                                myUserId: UUID?) async throws -> [DirectMessage] {
        var clauses = [orEq("sender_name", myName), orEq("recipient_name", myName)]
        if let uid = myUserId { clauses.insert("sender_id.eq.\(uid.uuidString)", at: 0) }
        return try await supabase
            .from("direct_messages")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .or(clauses.joined(separator: ","))
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
            .value
    }

    nonisolated private static func fetchOlder(propertyId: UUID, myName: String, myUserId: UUID?,
                                               member: FamilyMember, before: String) async throws -> [DirectMessage] {
        let mid = member.id.uuidString
        var clauses = [
            "and(\(orEq("sender_name", myName)),\(orEq("recipient_name", member.name)))",
            "and(\(orEq("sender_name", member.name)),\(orEq("recipient_name", myName)))",
            "and(sender_member_id.eq.\(mid),\(orEq("recipient_name", myName)))",
        ]
        if let uid = myUserId {
            clauses.insert("and(sender_id.eq.\(uid.uuidString),recipient_member_id.eq.\(mid))", at: 0)
        }
        return try await supabase
            .from("direct_messages")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .or(clauses.joined(separator: ","))
            .lt("created_at", value: before)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func markRead(member: FamilyMember) {
        UserDefaults.standard.set(Date(), forKey: "dm.lastseen.id.\(member.id.uuidString)")
        localRevision &+= 1
    }

    // MARK: - Persistence

    func load(propertyId: UUID, myName: String) async {
        isLoading = true
        defer { isLoading = false }
        guard !myName.isEmpty else { return }
        myUserId = supabase.auth.currentSession?.user.id
        do {
            // Fetch the most recent 1000 (newest first), then show oldest→newest.
            // Previously this ordered ascending, which returned the *oldest* 1000
            // and could hide recent messages once a property had many DMs.
            // The fetch + decode run off the main actor (nonisolated helper) —
            // this was the last big main-thread JSON decode in the app.
            let rows = try await Self.fetchRecent(propertyId: propertyId, myName: myName,
                                                  myUserId: myUserId)
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
        // "Addressed to me" = not mine: the fetch only returns my threads, so
        // every inbound row is for this account (id-first, name for legacy).
        let undelivered = dms.filter {
            !$0.isMine(myUserId: myUserId, myName: myName) && $0.deliveredAt == nil
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
        // Incremental reconciliation: append/patch/remove the single changed row
        // per event instead of refetching up to 1000 rows on every insert,
        // reaction, tick or edit (which also chained load → markDelivered → a
        // fresh event → another reload). A full reload survives only as the
        // decode-failure fallback. Callbacks must be registered before subscribing.
        postgresSubs.append(ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                if let row = try? action.decodeRecord(decoder: JSONDecoder()) as DirectMessage {
                    self.applyRealtimeInsert(row, myName: myName)
                } else {
                    self.scheduleReload(propertyId: propertyId, myName: myName)
                }
            }
        })
        postgresSubs.append(ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                if let row = try? action.decodeRecord(decoder: JSONDecoder()) as DirectMessage {
                    self.applyRealtimeUpdate(row)
                } else {
                    self.scheduleReload(propertyId: propertyId, myName: myName)
                }
            }
        })
        // DELETE: drop by id. No property filter — a delete's old-record carries
        // only the primary key under the default replica identity, so filtering
        // on property_id would discard every delete. Removing by id is naturally
        // scoped to what's already loaded.
        postgresSubs.append(ch.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "direct_messages"
        ) { [weak self] action in
            Task { @MainActor in
                guard let self,
                      let row = try? action.decodeOldRecord(decoder: JSONDecoder()) as RealtimeRowID
                else { return }
                self.dms.removeAll { $0.id == row.id }
            }
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

    /// Applies a realtime INSERT incrementally. Our own echo (or the optimistic
    /// row we appended on send) is swapped for the authoritative server row;
    /// everything else is appended (realtime inserts are the newest rows). A
    /// freshly received inbound message is stamped delivered — the resulting
    /// UPDATE echoes back and is patched in place, so no reload storm.
    private func applyRealtimeInsert(_ row: DirectMessage, myName: String) {
        if let i = dms.firstIndex(where: { $0.id == row.id }) {
            dms[i] = row
            return
        }
        dms.append(row)
        if !row.isMine(myUserId: myUserId, myName: myName) {
            Task { await markDelivered(myName: myName) }
        }
    }

    /// Applies a realtime UPDATE incrementally: reactions, read/delivered ticks,
    /// pin/mark, edits and delete-for-all tombstones all just swap the changed
    /// row in place. Rows outside the loaded set are ignored.
    private func applyRealtimeUpdate(_ row: DirectMessage) {
        guard let i = dms.firstIndex(where: { $0.id == row.id }) else { return }
        dms[i] = row
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
    func markReadRemote(member: FamilyMember, myName: String) async {
        let unread = dms.filter {
            !$0.isMine(myUserId: myUserId, myName: myName) &&
            $0.inThread(with: member, myUserId: myUserId, myName: myName) &&
            $0.readAt == nil
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

    /// Last-seen mark, keyed by the partner's member id (rename-proof). The
    /// pre-phase-B key was the display name; migrate it forward once so no
    /// conversation flashes fully-unread after updating.
    private func lastSeenDate(for member: FamilyMember) -> Date {
        let idKey = "dm.lastseen.id.\(member.id.uuidString)"
        if let d = UserDefaults.standard.object(forKey: idKey) as? Date { return d }
        if let legacy = UserDefaults.standard.object(forKey: "dm.lastseen.\(member.name)") as? Date {
            UserDefaults.standard.set(legacy, forKey: idKey)
            UserDefaults.standard.removeObject(forKey: "dm.lastseen.\(member.name)")
            return legacy
        }
        return .distantPast
    }

    /// This device's last-open time for a conversation — captured before
    /// `markRead` so the view can place the "unread messages" divider.
    func lastSeen(for member: FamilyMember) -> Date { lastSeenDate(for: member) }

    /// The earliest message from `member` newer than `since` — where the
    /// unread divider goes. `dms` is oldest→newest, so `.first` is the earliest.
    func firstUnreadId(from member: FamilyMember, myName: String, since: Date) -> UUID? {
        dms.first {
            !$0.isMine(myUserId: myUserId, myName: myName) &&
            $0.inThread(with: member, myUserId: myUserId, myName: myName) &&
            ($0.date ?? .distantPast) > since
        }?.id
    }
}

// MARK: - Server-side search

extension DirectMessageService {
    /// Names of the DM partners whose history contains the query — matched
    /// on Postgres, so results reach past the loaded page.
    func partnersMatching(propertyId: UUID, myName: String, query: String) async -> Set<String> {
        struct Row: Decodable {
            let senderName: String
            let recipientName: String
            enum CodingKeys: String, CodingKey {
                case senderName = "sender_name"
                case recipientName = "recipient_name"
            }
        }
        let rows: [Row] = (try? await supabase.from("direct_messages")
            .select("sender_name, recipient_name")
            .eq("property_id", value: propertyId.uuidString)
            .or("\(Self.orEq("sender_name", myName)),\(Self.orEq("recipient_name", myName))")
            .ilike("body", pattern: MessageService.likePattern(query))
            .limit(200)
            .execute().value) ?? []
        return Set(rows.map { $0.senderName == myName ? $0.recipientName : $0.senderName })
    }
}

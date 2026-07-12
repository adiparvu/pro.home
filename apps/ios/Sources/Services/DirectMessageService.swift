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
    /// The recipient's auth user id (migration 141) — the durable other half
    /// of the thread's identity. Nil only on legacy rows and for recipients
    /// without an account.
    var recipientId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, body, pinned, reactions
        case senderName        = "sender_name"
        case recipientName      = "recipient_name"
        case senderId           = "sender_id"
        case senderMemberId     = "sender_member_id"
        case recipientMemberId  = "recipient_member_id"
        case expiresAt          = "expires_at"
        case recipientId        = "recipient_id"
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

// MARK: - Stable identity (chat unification, phase 1)
//
// A DM thread's identity is the PEER'S AUTH USER ID (migration 141): threads,
// ownership, read state and reactions key on ids — names are display
// snapshots that break on rename (the production owner's display_name even
// carries a trailing space). Member ids and name matching survive ONLY for
// legacy rows whose id columns are null.

/// Everything needed to address ONE 1:1 thread: the durable peer auth user id
/// plus the legacy member/name keys that still cover pre-identity rows.
struct DMThread: Hashable {
    /// The peer's auth user id — the thread's identity. Nil only for
    /// contacts that hold no account.
    var peerUserId: UUID?
    /// The peer's family_members row, when they're on the roster.
    var memberId: UUID?
    /// Roster display-name snapshot — legacy row matching only.
    var memberName: String
    /// Trimmed name for UI and the legacy name columns.
    var displayName: String
    /// Device-local store key (last-seen, exhausted-older, theme/clear/block
    /// scopes): the member id for roster-backed threads — preserving every
    /// existing UserDefaults key — else the peer's user id.
    var storeKey: UUID

    init(member: FamilyMember) {
        peerUserId = member.userId
        memberId = member.id
        memberName = member.name
        displayName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        storeKey = member.id
    }

    init(peer: ChatPeer, member: FamilyMember? = nil) {
        peerUserId = peer.id
        memberId = member?.id
        memberName = member?.name ?? ""
        displayName = peer.displayName
        storeKey = member?.id ?? peer.id
    }

    /// The name to stamp into the legacy recipient_name column.
    var legacyName: String {
        memberName.isEmpty ? displayName : memberName
    }
}

extension DirectMessage {
    /// Display names may carry stray whitespace ("Adi " in production) —
    /// legacy name matching must never fail on an invisible character.
    static func nameMatches(_ a: String, _ b: String) -> Bool {
        let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tb.isEmpty else { return false }
        return a.trimmingCharacters(in: .whitespacesAndNewlines) == tb
    }

    /// Whether the signed-in user sent this message. sender_id is NOT NULL
    /// in practice (dm_insert requires it); the name check only covers rows
    /// from before migration 081.
    func isMine(myUserId: UUID?, myName: String) -> Bool {
        if let sid = senderId, let uid = myUserId { return sid == uid }
        return Self.nameMatches(senderName, myName)
    }

    /// The caller's own reaction — reactions are keyed by the reactor's auth
    /// user id (uuid string); the display-name key covers legacy rows only.
    func myReaction(myUserId: UUID?, myName: String) -> String? {
        if let uid = myUserId, let r = reactions?[uid.uuidString] { return r }
        return reactions?[myName]
    }

    /// Whether this message belongs to the 1-on-1 thread described by
    /// `thread`. Identity first: when both endpoints carry auth ids the match
    /// is exact and rename-proof; member/name matching covers legacy rows.
    func inThread(_ thread: DMThread, myUserId: UUID?, myName: String) -> Bool {
        if let peer = thread.peerUserId, let uid = myUserId {
            if let sid = senderId, let rid = recipientId {
                return (sid == uid && rid == peer) || (sid == peer && rid == uid)
            }
            // Inbound legacy row: the sender id alone identifies the peer.
            if let sid = senderId, sid != uid, sid == peer { return true }
        }
        // Legacy fallback (rows predating the id columns).
        if isMine(myUserId: myUserId, myName: myName) {
            if let rid = recipientMemberId { return rid == thread.memberId }
            return Self.nameMatches(recipientName, thread.legacyName)
        }
        if let sid = senderMemberId { return sid == thread.memberId }
        return Self.nameMatches(senderName, thread.legacyName)
    }

}

// MARK: - DirectMessageService

@MainActor
@Observable
final class DirectMessageService {
    /// Bumped on every mutation of `dms` — views memoize their derived,
    /// filtered lists on (revision, localRevision) so a body pass that didn't
    /// change the data (every keystroke!) costs O(1) instead of re-filtering
    /// the whole conversation.
    private(set) var revision = 0
    var dms: [DirectMessage] = [] { didSet { revision &+= 1 } }
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

    // MARK: - Typing indicator (shared subsystem — chat unification P3a)
    /// The shared typing/recording indicator; the engine syncs channel/name
    /// into it before each use (see `syncActivity`).
    private let activity = ChatActivityIndicator()
    var typingNames: Set<String> { activity.typingNames }
    var recordingNames: Set<String> { activity.recordingNames }
    var myName: String = ""
    /// The signed-in user's auth id — the stable half of "is this mine".
    /// Set on load; nil only before the first load (name fallback covers it).
    var myUserId: UUID?
    @ObservationIgnored private var typingSub: RealtimeSubscription?
    /// RLS-free "a new DM landed" broadcast — the reliable delivery path when
    /// postgres_changes is withheld by the SELECT policy (see send()).
    @ObservationIgnored private var newMsgSub: RealtimeSubscription?
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

    func sendTyping() { syncActivity(); activity.sendTyping() }

    /// Periodic signal while the voice recorder is live — see
    /// `ChatActivityIndicator.sendRecording`.
    func sendRecording() { syncActivity(); activity.sendRecording() }

    /// The indicator never owns realtime lifecycle: the engine hands it the
    /// current channel + name right before each use, so it is always exactly
    /// as fresh as the engine's own state was in the pre-extraction code.
    private func syncActivity() {
        activity.channel = channel
        activity.myName = myName
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
    func send(propertyId: UUID?, senderName: String, to thread: DMThread,
              body: String, replyTo: UUID? = nil, expiresAt: String? = nil) async throws -> DirectMessage {
        let senderId = supabase.auth.currentSession?.user.id
        let clientId = UUID()
        // Ids carry the identity; names are display snapshots and are stored
        // TRIMMED (the server-side stamp trims too — migration 141).
        let trimmedSender = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientName = thread.legacyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let optimistic = DirectMessage(
            id: clientId, senderName: trimmedSender, recipientName: recipientName,
            body: body, createdAt: ISO8601DateFormatter().string(from: Date()),
            replyTo: replyTo,
            senderId: senderId,
            recipientMemberId: thread.memberId,
            expiresAt: expiresAt,
            recipientId: thread.peerUserId)
        dms.append(optimistic)

        struct Payload: Encodable {
            let id: String
            let sender_name: String
            let recipient_name: String
            let body: String
            let property_id: String?
            let reply_to: String?
            let sender_id: String?
            let recipient_id: String?
            let recipient_member_id: String?
            let expires_at: String?
        }
        let payload = Payload(
            id: clientId.uuidString, sender_name: trimmedSender, recipient_name: recipientName,
            body: body, property_id: propertyId?.uuidString,
            reply_to: replyTo?.uuidString, sender_id: senderId?.uuidString,
            recipient_id: thread.peerUserId?.uuidString,
            recipient_member_id: thread.memberId?.uuidString, expires_at: expiresAt)
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
            scheduleHeadsRefresh()
            // Reliable delivery ping. postgres_changes INSERTs can be withheld
            // from the recipient by Realtime's per-subscriber RLS evaluation of
            // the direct_messages SELECT policy (its is_my_family_member()
            // clause), so the peer's client never sees the new row until it
            // reloads. A broadcast is RLS-free — the same path the typing
            // signal already uses — so it guarantees the peer learns of the new
            // message and fetches it immediately (WhatsApp-grade live delivery).
            if let ch = channel {
                let from = senderId?.uuidString ?? ""
                Task { await ch.broadcast(event: "dm_new", message: ["from": .string(from)]) }
            }
            return sent
        } catch {
            dms.removeAll { $0.id == clientId }
            throw error
        }
    }

    // MARK: - Queries

    func messages(in thread: DMThread, myName: String) -> [DirectMessage] {
        _ = localRevision  // observe local-state changes (hidden ids)
        let hidden = hiddenIds()
        return dms.filter {
            $0.inThread(thread, myUserId: myUserId, myName: myName)
            && !hidden.contains($0.id)
        }
    }

    // MARK: - Conversation heads (server-side, one row per peer)

    /// One row per DM thread for the signed-in user, computed on Postgres by
    /// dm_conversation_heads (migration 141) from the MESSAGES — never from
    /// the roster, so a peer with no family_members row (the property owner!)
    /// appears like anyone else. Unread is server truth: inbound rows
    /// addressed to me (recipient_id) with no read receipt.
    struct ConversationHead: Decodable, Identifiable {
        let peerUserId: UUID?
        let peerMemberId: UUID?
        let peerName: String
        let lastMessageId: UUID
        let lastBody: String?
        let lastSenderId: UUID?
        let lastCreatedAt: String
        let lastDeletedForAll: Bool
        let unreadCount: Int

        enum CodingKeys: String, CodingKey {
            case peerUserId         = "peer_user_id"
            case peerMemberId       = "peer_member_id"
            case peerName           = "peer_name"
            case lastMessageId      = "last_message_id"
            case lastBody           = "last_body"
            case lastSenderId       = "last_sender_id"
            case lastCreatedAt      = "last_created_at"
            case lastDeletedForAll  = "last_deleted_for_all"
            case unreadCount        = "unread_count"
        }

        var id: String {
            peerUserId?.uuidString ?? peerMemberId?.uuidString ?? peerName.lowercased()
        }
        var lastDate: Date? { ISODate.date(from: lastCreatedAt) }
    }

    private(set) var conversationHeads: [ConversationHead] = []
    @ObservationIgnored private var headsTask: Task<Void, Never>?

    /// Refetches the conversation heads (one cheap aggregate row per peer).
    func refreshHeads(propertyId: UUID) async {
        // The heads can be fetched before load() ever ran (startup mirrors
        // them to the watch) — make sure "is this mine" has its identity.
        if myUserId == nil { myUserId = supabase.auth.currentSession?.user.id }
        let rows: [ConversationHead]? = try? await supabase
            .rpc("dm_conversation_heads", params: ["p_property": propertyId.uuidString])
            .execute()
            .value
        if let rows {
            conversationHeads = rows
            syncWatchDMCatalog()
        }
    }

    /// Mirrors the conversation heads into the App-Group DM catalog the
    /// watch renders, and pushes a fresh payload so the wrist inbox stays
    /// live while the phone app is open. Only id-bearing threads ride along —
    /// a wrist reply targets "dm:<peer-user-id>", so a legacy thread without
    /// one would be a row the watch can't answer. Media/tombstone previews
    /// are flattened to a flag; a raw storage path never reaches the wrist.
    private func syncWatchDMCatalog() {
        let entries: [DMConversationEntry] = conversationHeads
            .sorted { ($0.lastDate ?? .distantPast) > ($1.lastDate ?? .distantPast) }
            .compactMap { head in
                guard let peerId = head.peerUserId else { return nil }
                var body = head.lastDeletedForAll ? nil : head.lastBody
                var isMedia = false
                if let b = body, ChatMedia.dmBodyKind(b) != .text {
                    isMedia = true
                    body = nil
                }
                return DMConversationEntry(
                    id: peerId,
                    peerName: head.peerName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastBody: body,
                    isMedia: isMedia,
                    lastIsMine: head.lastSenderId != nil && head.lastSenderId == myUserId,
                    lastAt: head.lastDate,
                    unread: head.unreadCount)
            }
        SharedDataStore.writeDMCatalog(Array(entries.prefix(8)))
        // Push only when a stamped payload exists — assembling one before the
        // account stamp is written would carry accountId == nil, which the
        // watch treats as "signed out" and wipes itself.
        if let payload = SharedDataStore.currentWatchPayload(), payload.accountId != nil {
            WatchSyncService.shared.push(payload)
        }
    }

    /// Debounced heads refresh piggybacking on sends and realtime events, so
    /// the conversation list stays live without re-deriving it client-side.
    private func scheduleHeadsRefresh() {
        guard let pid = subscribedPropertyId else { return }
        headsTask?.cancel()
        headsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refreshHeads(propertyId: pid)
        }
    }

    /// Whether a message is hidden on this device ("delete for me").
    func isHidden(_ id: UUID) -> Bool {
        _ = localRevision  // observe hidden-ids changes from view bodies
        return hiddenIds().contains(id)
    }

    /// Newest locally visible message of a thread — the preview fallback when
    /// a server head's last message is hidden on this device.
    func latestVisibleMessage(in thread: DMThread, myName: String) -> DirectMessage? {
        messages(in: thread, myName: myName).max { $0.createdAt < $1.createdAt }
    }

    // MARK: - Older history (per conversation, server-paged)

    /// Conversations whose full server history is already in memory
    /// (an older-page fetch came back empty). Keyed by the thread's store key.
    private(set) var exhaustedOlder: Set<UUID> = []
    var isLoadingOlder = false

    /// Pulls the next older page for one conversation and merges it in.
    /// Returns how many new rows arrived; 0 marks the thread exhausted so
    /// the UI can retire its load-older affordance.
    @discardableResult
    func loadOlder(propertyId: UUID, myName: String, thread: DMThread) async -> Int {
        guard !isLoadingOlder else { return 0 }
        let loaded = messages(in: thread, myName: myName)
        guard let oldest = loaded.min(by: { $0.createdAt < $1.createdAt }) else { return 0 }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let rows = try await Self.fetchOlder(propertyId: propertyId, myName: myName,
                                                 myUserId: myUserId, thread: thread,
                                                 before: oldest.createdAt)
            let known = Set(dms.map(\.id))
            let fresh = rows.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else {
                exhaustedOlder.insert(thread.storeKey)
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

    /// Network + JSON decode off the main actor. The id clauses make BOTH
    /// directions of my mail rename- and roster-proof (sender_id = me for
    /// outbound, recipient_id = me for inbound — migration 141); the name
    /// clauses survive only for legacy rows whose id columns are null.
    nonisolated private static func fetchRecent(propertyId: UUID, myName: String,
                                                myUserId: UUID?) async throws -> [DirectMessage] {
        var clauses = [orEq("sender_name", myName), orEq("recipient_name", myName)]
        if let uid = myUserId {
            clauses.insert(contentsOf: ["sender_id.eq.\(uid.uuidString)",
                                        "recipient_id.eq.\(uid.uuidString)"], at: 0)
        }
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
                                               thread: DMThread, before: String) async throws -> [DirectMessage] {
        var clauses: [String] = []
        // Identity clauses — exact and rename-proof.
        if let uid = myUserId, let peer = thread.peerUserId {
            clauses.append("and(sender_id.eq.\(uid.uuidString),recipient_id.eq.\(peer.uuidString))")
            clauses.append("and(sender_id.eq.\(peer.uuidString),recipient_id.eq.\(uid.uuidString))")
        }
        // Legacy clauses so rows predating the id columns still page in.
        let legacyName = thread.legacyName
        if !legacyName.isEmpty {
            clauses.append("and(\(orEq("sender_name", myName)),\(orEq("recipient_name", legacyName)))")
            clauses.append("and(\(orEq("sender_name", legacyName)),\(orEq("recipient_name", myName)))")
        }
        if let mid = thread.memberId?.uuidString {
            clauses.append("and(sender_member_id.eq.\(mid),\(orEq("recipient_name", myName)))")
            if let uid = myUserId {
                clauses.append("and(sender_id.eq.\(uid.uuidString),recipient_member_id.eq.\(mid))")
            }
        }
        guard !clauses.isEmpty else { return [] }
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

    func markRead(thread: DMThread) {
        lastSeenCursor(for: thread).markSeen()
        localRevision &+= 1
        revision &+= 1
    }

    func markRead(member: FamilyMember) { markRead(thread: DMThread(member: member)) }

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
            // The conversation list derives from the server-side heads, not
            // from the roster — refresh them alongside the message window.
            await refreshHeads(propertyId: propertyId)
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
        // Idempotent: already GENUINELY live for this property → keep it
        // (don't let a navigation push/pop tear down the channel while a
        // thread is open). The status check matters: a channel whose initial
        // subscribe failed at launch used to satisfy `!= nil` and silence the
        // whole session — no live messages, no typing indicator.
        if let ch = channel, subscribedPropertyId == propertyId,
           ch.status == .subscribed { return }
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
            Task { @MainActor [weak self] in
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
            Task { @MainActor [weak self] in
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
            Task { @MainActor [weak self] in
                guard let self,
                      let row = try? action.decodeOldRecord(decoder: JSONDecoder()) as RealtimeRowID
                else { return }
                self.dms.removeAll { $0.id == row.id }
                self.scheduleHeadsRefresh()
            }
        })
        typingSub = ch.onBroadcast(event: "typing") { [weak self] json in
            if case let .string(name)? = json["name"] {
                // Older clients broadcast no kind — treat them as typing.
                let kind: String = if case let .string(k)? = json["kind"] { k } else { "typing" }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.syncActivity()
                    self.activity.handleTyping(name, kind: kind)
                }
            }
        }
        // Reliable delivery: a peer's send broadcasts "dm_new"; fetch the newer
        // rows so the message appears live even when postgres_changes was
        // withheld by RLS. Skip my own echo — I already have the row.
        newMsgSub = ch.onBroadcast(event: "dm_new") { [weak self] json in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case let .string(from)? = json["from"],
                   from == supabase.auth.currentSession?.user.id.uuidString { return }
                self.scheduleReload(propertyId: propertyId, myName: myName)
            }
        }
        do {
            try await ch.subscribeWithError()
        } catch {
            // A failed subscribe must leave NO trace: keeping the dead channel
            // made the idempotent guard treat the whole session as live.
            debugLog("DM realtime subscribe failed:", error)
            postgresSubs.removeAll()
            typingSub = nil
            newMsgSub = nil
            await supabase.realtimeV2.removeChannel(ch)
            return
        }
        channel = ch
        subscribedPropertyId = propertyId
    }

    /// Delivery safety net for an OPEN thread: verifies the channel is
    /// genuinely subscribed and, when it isn't (failed initial subscribe,
    /// dropped socket), rebuilds it and refetches — so a conversation the
    /// user is looking at can never sit silent. Free when healthy.
    func ensureLiveDelivery(propertyId: UUID, myName: String) async {
        if let ch = channel, subscribedPropertyId == propertyId,
           ch.status == .subscribed { return }
        await subscribeRealtime(propertyId: propertyId, myName: myName)
        await load(propertyId: propertyId, myName: myName)
    }

    /// Applies a realtime INSERT incrementally. Our own echo (or the optimistic
    /// row we appended on send) is swapped for the authoritative server row;
    /// everything else is appended (realtime inserts are the newest rows). A
    /// freshly received inbound message is stamped delivered — the resulting
    /// UPDATE echoes back and is patched in place, so no reload storm.
    private func applyRealtimeInsert(_ row: DirectMessage, myName: String) {
        defer { scheduleHeadsRefresh() }
        if let i = dms.firstIndex(where: { $0.id == row.id }) {
            dms[i] = row
            return
        }
        dms.append(row)
        if !row.isMine(myUserId: myUserId, myName: myName) {
            Task { [weak self] in await self?.markDelivered(myName: myName) }
        }
    }

    /// Applies a realtime UPDATE incrementally: reactions, read/delivered ticks,
    /// pin/mark, edits and delete-for-all tombstones all just swap the changed
    /// row in place. Rows outside the loaded set are ignored.
    private func applyRealtimeUpdate(_ row: DirectMessage) {
        guard let i = dms.firstIndex(where: { $0.id == row.id }) else { return }
        dms[i] = row
        scheduleHeadsRefresh()
    }

    func unsubscribe() async {
        postgresSubs.removeAll()
        typingSub = nil
        newMsgSub = nil
        activity.reset()
        activity.channel = nil
        reloadTask?.cancel()
        reloadTask = nil
        headsTask?.cancel()
        headsTask = nil
        subscribedPropertyId = nil
        if let ch = channel {
            await supabase.realtimeV2.removeChannel(ch)
            channel = nil
        }
    }

    func deleteMessage(id: UUID) async {
        if await ChatMessageStore.deleteRow(table: "direct_messages", id: id, tag: "DM") {
            dms.removeAll { $0.id == id }
        }
    }

    /// Delete for everyone — keeps the row but replaces it with a tombstone.
    func deleteForEveryone(id: UUID) async {
        if await ChatMessageStore.tombstoneRow(table: "direct_messages", id: id, tag: "DM"),
           let i = dms.firstIndex(where: { $0.id == id }) {
            dms[i].deletedForAll = true
        }
    }

    /// Delete for me — hides the row locally only.
    func deleteForMe(id: UUID) {
        ChatMessageStore.hide(id, key: Self.hiddenKey)
        localRevision &+= 1
        revision &+= 1
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

    /// Reactions are keyed by the REACTOR'S AUTH USER ID (uuid string) —
    /// display names collide and drift. Only the caller's own key is ever
    /// written; a legacy name key of the caller is read once and migrated to
    /// the id key on the next toggle.
    func toggleReaction(_ msg: DirectMessage, emoji: String, myName: String) async {
        var map = msg.reactions ?? [:]
        let key = myUserId?.uuidString ?? myName
        let current = map[key] ?? map[myName]
        if myUserId != nil { map.removeValue(forKey: myName) }
        if current == emoji { map.removeValue(forKey: key) } else { map[key] = emoji }
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

    /// Marks incoming messages in `thread` as read (sets read_at) and updates local state.
    func markReadRemote(thread: DMThread, myName: String) async {
        let unread = dms.filter {
            !$0.isMine(myUserId: myUserId, myName: myName) &&
            $0.inThread(thread, myUserId: myUserId, myName: myName) &&
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
            // Unread badges in the list are server truth — pull them down.
            scheduleHeadsRefresh()
        } catch { return }
    }

    /// "Mark all read": stamps read_at on every loaded inbound message that
    /// lacks one (one batched UPDATE), then refreshes the server-derived
    /// unread counts. Messages beyond the loaded window keep their state.
    func markAllReadRemote(propertyId: UUID, myName: String) async {
        let unread = dms.filter {
            !$0.isMine(myUserId: myUserId, myName: myName) && $0.readAt == nil
        }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        if !unread.isEmpty {
            let needBoth = unread.filter { $0.deliveredAt == nil }.map { $0.id.uuidString }
            let readOnly = unread.filter { $0.deliveredAt != nil }.map { $0.id.uuidString }
            do {
                if !needBoth.isEmpty {
                    try await supabase.from("direct_messages")
                        .update(["read_at": nowISO, "delivered_at": nowISO])
                        .in("id", values: needBoth)
                        .execute()
                }
                if !readOnly.isEmpty {
                    try await supabase.from("direct_messages")
                        .update(["read_at": nowISO])
                        .in("id", values: readOnly)
                        .execute()
                }
                for m in unread {
                    if let i = dms.firstIndex(where: { $0.id == m.id }) {
                        dms[i].readAt = nowISO
                        if dms[i].deliveredAt == nil { dms[i].deliveredAt = nowISO }
                    }
                }
            } catch { /* best effort — heads refresh below reflects reality */ }
        }
        await refreshHeads(propertyId: propertyId)
    }

    // MARK: - Private helpers

    private static let hiddenKey = "dm.hidden.ids"

    private func hiddenIds() -> Set<UUID> {
        ChatMessageStore.hiddenIds(key: Self.hiddenKey)
    }

    /// Last-seen mark, keyed by the thread's store key (rename-proof; the
    /// member id for roster-backed threads so existing marks survive). The
    /// pre-phase-B key was the display name; migrate it forward once so no
    /// conversation flashes fully-unread after updating.
    /// The shared cursor for one thread — same key (and pre-identity legacy
    /// key migration) the hand-rolled code used, so no stored data moves.
    private func lastSeenCursor(for thread: DMThread) -> LastSeenCursor {
        LastSeenCursor(
            key: "dm.lastseen.id.\(thread.storeKey.uuidString)",
            legacyKey: thread.memberName.isEmpty ? nil : "dm.lastseen.\(thread.memberName)")
    }

    /// This device's last-open time for a conversation — captured before
    /// `markRead` so the view can place the "unread messages" divider.
    func lastSeen(for thread: DMThread) -> Date { lastSeenCursor(for: thread).date }

    /// The earliest inbound message in `thread` newer than `since` — where the
    /// unread divider goes. `dms` is oldest→newest, so `.first` is the earliest.
    func firstUnreadId(in thread: DMThread, myName: String, since: Date) -> UUID? {
        dms.first {
            !$0.isMine(myUserId: myUserId, myName: myName) &&
            $0.inThread(thread, myUserId: myUserId, myName: myName) &&
            ($0.date ?? .distantPast) > since
        }?.id
    }
}

// MARK: - Forwarding

extension DirectMessageService {
    /// Forwards a group-chat message into a 1:1 thread. A plain insert, not
    /// `send`: forwarding happens from the group chat, where the DM window
    /// isn't loaded, so there is no optimistic bubble to place and no outbox
    /// hand-off — the caller surfaces the error directly. Columns are the
    /// ones direct_messages RLS requires: sender_id must equal the caller
    /// and recipient_member_id lets the recipient read it.
    static func forward(body: String, senderName: String,
                        to member: FamilyMember, propertyId: UUID) async throws {
        struct DMForward: Encodable {
            let sender_name: String; let recipient_name: String
            let body: String; let property_id: String?
            let sender_id: String?; let recipient_member_id: String
        }
        try await supabase.from("direct_messages").insert(
            DMForward(sender_name: senderName, recipient_name: member.name,
                      body: body, property_id: propertyId.uuidString,
                      sender_id: supabase.auth.currentSession?.user.id.uuidString,
                      recipient_member_id: member.id.uuidString)
        ).execute()
    }
}

// MARK: - Server-side search

extension DirectMessageService {
    /// The DM partners whose history contains the query — matched on
    /// Postgres, so results reach past the loaded page. Peers come back as
    /// auth user ids (identity rows) plus raw names (legacy rows).
    struct SearchHits {
        var userIds: Set<UUID> = []
        var names: Set<String> = []
    }

    func partnersMatching(propertyId: UUID, myName: String, query: String) async -> SearchHits {
        struct Row: Decodable {
            let senderId: UUID?
            let recipientId: UUID?
            let senderName: String
            let recipientName: String
            enum CodingKeys: String, CodingKey {
                case senderId      = "sender_id"
                case recipientId   = "recipient_id"
                case senderName    = "sender_name"
                case recipientName = "recipient_name"
            }
        }
        var clauses = [Self.orEq("sender_name", myName), Self.orEq("recipient_name", myName)]
        if let uid = myUserId {
            clauses.insert(contentsOf: ["sender_id.eq.\(uid.uuidString)",
                                        "recipient_id.eq.\(uid.uuidString)"], at: 0)
        }
        let rows: [Row] = (try? await supabase.from("direct_messages")
            .select("sender_id, recipient_id, sender_name, recipient_name")
            .eq("property_id", value: propertyId.uuidString)
            .or(clauses.joined(separator: ","))
            .ilike("body", pattern: MessageService.likePattern(query))
            .limit(200)
            .execute().value) ?? []
        var hits = SearchHits()
        for r in rows {
            let mine = (r.senderId != nil && r.senderId == myUserId)
                || DirectMessage.nameMatches(r.senderName, myName)
            if let peer = mine ? r.recipientId : r.senderId, peer != myUserId {
                hits.userIds.insert(peer)
            }
            hits.names.insert(mine ? r.recipientName : r.senderName)
        }
        return hits
    }
}

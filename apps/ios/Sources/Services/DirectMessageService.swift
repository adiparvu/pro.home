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
    /// The row's property scope: the receipt/reaction side tables demand a
    /// NOT NULL property_id, so every row carries its own. Optional only
    /// because rows predating property scoping exist; they simply carry no
    /// receipts.
    var propertyId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, body, pinned, reactions
        case senderName        = "sender_name"
        case recipientName      = "recipient_name"
        case senderId           = "sender_id"
        case senderMemberId     = "sender_member_id"
        case recipientMemberId  = "recipient_member_id"
        case expiresAt          = "expires_at"
        case recipientId        = "recipient_id"
        case propertyId         = "property_id"
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
        // Trimmed: legacyName feeds the older-page fetch clauses, and the
        // rows themselves are trimmed since migration 172 — an untrimmed
        // snapshot made legacy pages come back empty and permanently
        // retired "Load older" for the session.
        memberName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = memberName
        storeKey = member.id
    }

    init(peer: ChatPeer, member: FamilyMember? = nil) {
        peerUserId = peer.id
        memberId = member?.id
        memberName = member?.name ?? ""
        displayName = peer.displayName
        storeKey = member?.id ?? peer.id
    }

    /// Rebuilds a thread from a queued outbox row, so the flush path routes
    /// through the SAME engine send as a live message (optimistic swap,
    /// heads refresh, dm_new ping) instead of hand-rolling an insert.
    init(peerUserId: UUID?, memberId: UUID?, name: String) {
        self.peerUserId = peerUserId
        self.memberId = memberId
        memberName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = memberName
        // send() never touches storeKey; the zero UUID keeps the fallback
        // deterministic for the id-less legacy-contact case.
        storeKey = memberId ?? peerUserId
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
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

    /// The shared realtime channel lifecycle (chat unification P3d): owns the
    /// channel, subscribe/rebuild, the stale-close kill watch, the storm
    /// breaker/rejoin grace and the broadcast round-trip self-test. This
    /// engine contributes only its topic, handlers and refetch — see
    /// `realtimeConfiguration`.
    @ObservationIgnored private let realtime = ChatRealtimeChannel()

    /// Live realtime diagnostic, surfaced by the chat view's warning banner —
    /// see `ChatRealtimeChannel.realtimeStatus` ("live" only once the
    /// broadcast round-trip is proven).
    var realtimeStatus: String { realtime.realtimeStatus }

    /// The live channel — `send()` broadcasts its "dm_new" delivery ping on
    /// it, and the activity indicator is synced from it before each use.
    private var channel: RealtimeChannelV2? { realtime.channel }

    /// Property the live channel is currently bound to, parsed back out of
    /// the subscribed topic so it can never drift from the shared lifecycle.
    private var subscribedPropertyId: UUID? {
        guard let topic = realtime.subscribedTopic,
              topic.hasPrefix(Self.topicPrefix) else { return nil }
        return UUID(uuidString: String(topic.dropFirst(Self.topicPrefix.count)))
    }

    /// Bumped whenever UserDefaults-backed local state (last-seen timestamps,
    /// hidden message ids) changes. Those aren't observable stored properties,
    /// so the derived reads (`messages`, `unreadCount`) touch this value to
    /// register an observation dependency and refresh when it changes.
    private var localRevision = 0

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
    /// Coalesces bursts of realtime events (a lively thread, a flurry of read
    /// receipts) into a single reload per quiet window, instead of refetching
    /// the whole conversation once per event.
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    private func scheduleReload(propertyId: UUID, myName: String) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
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
            recipientId: thread.peerUserId,
            propertyId: propertyId)

        // The append → bounded-insert → swap → rollback-and-rethrow skeleton
        // is the shared engine core (P5); only the insert and the
        // post-success bookkeeping below are this engine's.
        return try await ChatEngineCore.runOptimisticSend(
            on: self, rows: \DirectMessageService.dms, optimistic: optimistic,
            insert: {
                // P6 — ONE store. Resolve the thread's conversation (read
                // cache first, `dm_open_conversation` RPC for a fresh
                // thread), insert into `messages` (RLS: sender AND
                // conversation member) and fold the returned row back into
                // DirectMessage. Everything around the insert — optimistic
                // append, timeout, rollback-and-rethrow (the caller's outbox
                // hand-off), heads refresh, the dm_new broadcast — is
                // untouched by the store change.
                let conv = try await self.resolveUnifiedConversation(
                    for: thread, myName: trimmedSender, propertyId: propertyId)
                let payload = UnifiedInsert(
                    id: clientId.uuidString,
                    conversation_id: conv.id.uuidString,
                    property_id: propertyId?.uuidString,
                    sender_id: senderId?.uuidString,
                    sender_name: trimmedSender,
                    body: body,
                    reply_to: replyTo?.uuidString,
                    expires_at: expiresAt)
                let row: UnifiedRow = try await withChatTimeout {
                    try await supabase
                        .from("messages")
                        .insert(payload)
                        .select(Self.unifiedColumns)
                        .single()
                        .execute()
                        .value
                }
                return Self.mapUnified(row, members: conv.members,
                                       reads: [], deliveries: [], reactions: [])
            },
            onSent: { _ in
                self.scheduleHeadsRefresh()
                // Reliable delivery ping: postgres_changes can be withheld
                // from the recipient by per-subscriber RLS — see
                // ChatEngineCore.broadcastDeliveryPing.
                ChatEngineCore.broadcastDeliveryPing(
                    on: self.channel, event: "dm_new",
                    from: senderId?.uuidString ?? "")
            })
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
            // The name fallback trims to match the server's lower(btrim())
            // grouping (migration 141) — untrimmed, one edge space forked
            // the same conversation into two list rows.
            peerUserId?.uuidString ?? peerMemberId?.uuidString
                ?? peerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
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
        // P6: history pages per CONVERSATION — the thread's identity, resolved
        // once by the read path, replaces the five-clause identity/legacy `or`
        // the two-store world needed. A thread whose conversation this device
        // has never seen has no server history to page: exhausted by
        // definition (the next `load()` brings it in if one appears).
        guard let conv = cachedUnifiedConversation(for: thread, myName: myName) else {
            exhaustedOlder.insert(thread.storeKey)
            return 0
        }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let rows = try await Self.fetchOlder(propertyId: propertyId, conversation: conv,
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

    /// One older page for a single conversation, network + decode off the
    /// main actor. The property filter is redundant with the conversation
    /// scope and deliberately kept: it is index-friendly and it makes a
    /// cross-property cache entry impossible to page through. Side tables
    /// are not fetched for history — receipts and reactions on rows this old
    /// arrive with the next full `load()`, exactly as the legacy page did
    /// for rows outside its window.
    nonisolated private static func fetchOlder(propertyId: UUID,
                                               conversation: UnifiedConversation,
                                               before: String) async throws -> [DirectMessage] {
        let rows: [UnifiedRow] = try await supabase
            .from("messages")
            .select(unifiedColumns)
            .eq("conversation_id", value: conversation.id.uuidString)
            .eq("property_id", value: propertyId.uuidString)
            .lt("created_at", value: before)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map {
            mapUnified($0, members: conversation.members,
                       reads: [], deliveries: [], reactions: [])
        }
    }

    // MARK: - The unified store (P4c → P6)
    //
    // DMs live in ONE place: `conversations` / `conversation_members` /
    // `messages` plus the receipt and reaction side tables — the same store
    // and the same engine the group chat uses, which is how every real chat
    // product models a 1:1 thread. Every row is folded back into the legacy
    // `DirectMessage` shape right here, so threads, bubbles, heads, search
    // and the whole UI layer stayed untouched across the migration.
    //
    // P4c/P4d shipped this behind `chat_rollout.dm_unified_read` and mirrored
    // both ways while the fleet caught up; P6 removed the flag and the second
    // store. What remains is the invariant that made the switch safe: ids are
    // preserved, so a row's identity never depended on which table it sat in.

    /// Offline snapshot entity. Deliberately NOT the pre-migration "dms"
    /// entity: a device that once cached legacy-shaped rows must hydrate from
    /// nothing rather than from rows the retired store shaped.
    private static let unifiedCacheEntity = "dms.unified"

    /// The property the in-memory conversation roster belongs to.
    @ObservationIgnored private var loadedProperty: UUID?

    /// Property switch: the send path's conversation cache is scoped to the
    /// outgoing property — the same peer usually exists in both, so a stale
    /// entry could route a send into the wrong property's conversation. An
    /// empty cache simply means the next send resolves through the RPC.
    private func resetScopeIfNeeded(propertyId: UUID) {
        guard loadedProperty != propertyId else { return }
        unifiedConversations = []
        loadedProperty = propertyId
    }

    /// One `conversation_members` row — a participant's identity triple
    /// (auth user id when known, roster member id, display-name snapshot).
    private struct UnifiedMember: Decodable {
        let conversationId: UUID
        let userId: UUID?
        let memberId: UUID?
        let displayName: String
        enum CodingKeys: String, CodingKey {
            case conversationId = "conversation_id"
            case userId         = "user_id"
            case memberId       = "member_id"
            case displayName    = "display_name"
        }
    }

    /// The unified `messages` columns a DM needs. `Message` (the group model)
    /// is deliberately not reused: it lacks `conversation_id`, and this row
    /// exists only to be folded into `DirectMessage` right here.
    private struct UnifiedRow: Decodable {
        let id: UUID
        let conversationId: UUID
        let propertyId: UUID?
        let senderId: UUID?
        let senderName: String
        let body: String?
        let replyTo: UUID?
        let pinned: Bool?
        let isMarked: Bool?
        let editedAt: String?
        let deletedForAll: Bool?
        let expiresAt: String?
        let createdAt: String
        enum CodingKeys: String, CodingKey {
            case id, body, pinned
            case conversationId = "conversation_id"
            case propertyId     = "property_id"
            case senderId       = "sender_id"
            case senderName     = "sender_name"
            case replyTo        = "reply_to"
            case isMarked       = "is_marked"
            case editedAt       = "edited_at"
            case deletedForAll  = "deleted_for_all"
            case expiresAt      = "expires_at"
            case createdAt      = "created_at"
        }
    }

    /// The unified `messages` columns a DM needs — one list shared by the
    /// recent fetch and send's returning select, so the two can never drift.
    nonisolated private static let unifiedColumns =
        "id, conversation_id, property_id, sender_id, sender_name, body, reply_to, pinned, is_marked, edited_at, deleted_for_all, expires_at, created_at"

    /// One unified DM conversation the read path saw (id + member triples).
    /// `send()` resolves a thread's conversation from this cache before
    /// falling back to the `dm_open_conversation` RPC (P4d-2).
    private struct UnifiedConversation {
        let id: UUID
        let members: [UnifiedMember]

        /// The OTHER party — id-first, trimmed-name fallback for members
        /// without an account (the same matching law as `inThread`). A
        /// single-member conversation is a self-thread whose lone member is
        /// both sides.
        func peer(myUserId: UUID?, myName: String) -> UnifiedMember? {
            guard members.count > 1 else { return members.first }
            return members.first { m in
                if let uid = myUserId, let mu = m.userId { return mu != uid }
                return !DirectMessage.nameMatches(m.displayName, myName)
            }
        }
    }

    /// What one unified read round-trip yields: the conversation roster
    /// (kept for send's resolution) plus the folded message window.
    private struct UnifiedFetch {
        let conversations: [UnifiedConversation]
        let messages: [DirectMessage]
    }

    /// A PostgREST `in()` filter rides the URL — hundreds of uuids would blow
    /// past sane request lengths, so the id filters go out in bounded chunks.
    nonisolated private static func chunks(_ values: [String],
                                           of size: Int = 200) -> [[String]] {
        stride(from: 0, to: values.count, by: size).map {
            Array(values[$0 ..< min($0 + size, values.count)])
        }
    }

    /// Network + decode off the main actor: my DM
    /// conversations for this property (RLS: members-only), their members,
    /// the newest window of unified rows, then the receipt/reaction side
    /// tables — all folded back into `DirectMessage`. The explicit `.in` on
    /// MY conversation ids (rather than a bare `conversation_id not is null`)
    /// keeps the query index-friendly and self-documenting; RLS enforces
    /// membership either way. Same limit discipline as the legacy fetch:
    /// newest 1000, shown oldest→newest by the caller's sort.
    /// My DM conversations for one property with their member triples (RLS:
    /// members-only). Shared by the message window and server-side search, so
    /// the two can never disagree about who a thread belongs to.
    nonisolated private static func fetchUnifiedConversations(
        propertyId: UUID) async throws -> [UnifiedConversation] {
        struct ConvRow: Decodable { let id: UUID }
        let convs: [ConvRow] = try await supabase
            .from("conversations")
            .select("id")
            .eq("kind", value: "dm")
            .eq("property_id", value: propertyId.uuidString)
            .execute()
            .value
        guard !convs.isEmpty else { return [] }
        let members: [UnifiedMember] = try await supabase
            .from("conversation_members")
            .select("conversation_id, user_id, member_id, display_name")
            .in("conversation_id", values: convs.map(\.id.uuidString))
            .execute()
            .value
        let membersByConv = Dictionary(grouping: members, by: \.conversationId)
        return convs.map {
            UnifiedConversation(id: $0.id, members: membersByConv[$0.id] ?? [])
        }
    }

    nonisolated private static func fetchUnifiedRecent(propertyId: UUID) async throws -> UnifiedFetch {
        let conversations = try await fetchUnifiedConversations(propertyId: propertyId)
        guard !conversations.isEmpty else { return UnifiedFetch(conversations: [], messages: []) }
        let convIds = conversations.map(\.id.uuidString)
        let membersByConv = Dictionary(uniqueKeysWithValues:
            conversations.map { ($0.id, $0.members) })
        let rows: [UnifiedRow] = try await supabase
            .from("messages")
            .select(unifiedColumns)
            .in("conversation_id", values: convIds)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
            .value
        guard !rows.isEmpty else { return UnifiedFetch(conversations: conversations, messages: []) }
        let ids = rows.map(\.id.uuidString)
        var reads: [MessageRead] = []
        var deliveries: [MessageDelivery] = []
        var reactions: [MessageReaction] = []
        for chunk in chunks(ids) {
            let r: [MessageRead] = try await supabase.from("message_reads")
                .select().in("message_id", values: chunk).execute().value
            reads += r
            let d: [MessageDelivery] = try await supabase.from("message_deliveries")
                .select().in("message_id", values: chunk).execute().value
            deliveries += d
            let x: [MessageReaction] = try await supabase.from("message_reactions")
                .select().in("message_id", values: chunk).execute().value
            reactions += x
        }
        let readsByMessage = Dictionary(grouping: reads, by: \.messageId)
        let deliveriesByMessage = Dictionary(grouping: deliveries, by: \.messageId)
        let reactionsByMessage = Dictionary(grouping: reactions, by: \.messageId)
        let messages = rows.map { row in
            mapUnified(row,
                       members: membersByConv[row.conversationId] ?? [],
                       reads: readsByMessage[row.id] ?? [],
                       deliveries: deliveriesByMessage[row.id] ?? [],
                       reactions: reactionsByMessage[row.id] ?? [])
        }
        return UnifiedFetch(conversations: conversations, messages: messages)
    }

    /// Folds one unified row (+ its side-table rows) into the legacy
    /// `DirectMessage` shape.
    ///
    /// Recipient derivation: a DM conversation has exactly two members, so
    /// the recipient is the member that is NOT the sender — matched id-first
    /// (`sender_id` vs `user_id`), trimmed-name fallback for accountless
    /// legacy contacts (same law as `inThread`). A self-conversation carries
    /// ONE member, who is both sides. If the sender matches neither member
    /// (a row the mirror should never produce), the message keeps its
    /// sender-only identity rather than misattribute the thread.
    ///
    /// Receipts: the legacy `read_at`/`delivered_at` columns modeled exactly
    /// one reader — the other party — so they come back as the RECIPIENT's
    /// `message_reads`/`message_deliveries` rows for this message. Reactions
    /// collapse to the legacy `[reactor-user-uuid: emoji]` map.
    nonisolated private static func mapUnified(
        _ row: UnifiedRow, members: [UnifiedMember],
        reads: [MessageRead], deliveries: [MessageDelivery],
        reactions: [MessageReaction]) -> DirectMessage {
        func isSender(_ m: UnifiedMember) -> Bool {
            if let sid = row.senderId, let uid = m.userId { return uid == sid }
            return DirectMessage.nameMatches(m.displayName, row.senderName)
        }
        let senderIndex = members.firstIndex(where: isSender)
        let sender = senderIndex.map { members[$0] }
        let recipient: UnifiedMember?
        if members.count == 1 {
            recipient = members.first
        } else if let si = senderIndex {
            recipient = members.indices.first { $0 != si }.map { members[$0] }
        } else {
            recipient = nil
        }
        let recipientUserId = recipient?.userId
        let readAt = recipientUserId.flatMap { rid in
            reads.first { $0.userId == rid }?.readAt
        }
        let deliveredAt = recipientUserId.flatMap { rid in
            deliveries.first { $0.userId == rid }?.deliveredAt
        }
        // nil (not [:]) when empty, matching the legacy column's null.
        let reactionMap: [String: String]? = reactions.isEmpty ? nil
            : Dictionary(reactions.map { ($0.userId.uuidString, $0.emoji) },
                         uniquingKeysWith: { _, new in new })
        return DirectMessage(
            id: row.id,
            senderName: row.senderName,
            recipientName: recipient?.displayName ?? "",
            body: row.body ?? "",
            createdAt: row.createdAt,
            replyTo: row.replyTo,
            deletedForAll: row.deletedForAll,
            editedAt: row.editedAt,
            pinned: row.pinned,
            isMarked: row.isMarked,
            reactions: reactionMap,
            readAt: readAt,
            deliveredAt: deliveredAt,
            senderId: row.senderId,
            senderMemberId: sender?.memberId,
            recipientMemberId: recipient?.memberId,
            expiresAt: row.expiresAt,
            recipientId: recipient?.userId,
            propertyId: row.propertyId)
    }

    // MARK: - Unified writes (P4d-2 → P6)
    //
    // Every DM mutation lands on the unified store: the message row itself in
    // `messages`, receipts in `message_reads`/`message_deliveries`, reactions
    // in `message_reactions`, pin/mark through the membership-gated RPCs. A
    // write that throws is handled exactly as before — outbox hand-off for
    // send, best-effort elsewhere — and there is no second store to retry on.

    /// Conversation roster from the last unified read; `send()` resolves its
    /// target here before spending a round-trip on the RPC.
    @ObservationIgnored private var unifiedConversations: [UnifiedConversation] = []

    /// The cached conversation whose PEER matches `thread` — id-first
    /// (auth user id), then roster member id, then the trimmed legacy name,
    /// the same matching law as `inThread`. A single-member conversation is
    /// a self-thread, so its lone member is the peer.
    private func cachedUnifiedConversation(for thread: DMThread,
                                           myName: String) -> UnifiedConversation? {
        unifiedConversations.first { conv in
            guard let p = conv.peer(myUserId: myUserId, myName: myName) else { return false }
            if let want = thread.peerUserId, let have = p.userId { return want == have }
            if let want = thread.memberId, let have = p.memberId { return want == have }
            return DirectMessage.nameMatches(p.displayName, thread.legacyName)
        }
    }

    /// The unified conversation for `thread`: cache first; a brand-new
    /// thread goes through the `dm_open_conversation` RPC (definer,
    /// caller-inclusive — P4d-1), bounded like every other send-path call.
    /// The fresh conversation's members are synthesized from the thread's
    /// identity so the sent row folds back into `DirectMessage` without a
    /// second fetch, and cached so the next send skips the RPC.
    private func resolveUnifiedConversation(
        for thread: DMThread, myName: String,
        propertyId: UUID?) async throws -> UnifiedConversation {
        if let cached = cachedUnifiedConversation(for: thread, myName: myName) {
            return cached
        }
        let peerUser = thread.peerUserId
        let peerMember = thread.memberId
        let peerName = thread.legacyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let params: [String: AnyJSON] = [
            "p_my_name": .string(myName),
            "p_my_member": .null,
            "p_peer_user": peerUser.map { .string($0.uuidString) } ?? .null,
            "p_peer_member": peerMember.map { .string($0.uuidString) } ?? .null,
            "p_peer_name": .string(peerName),
            "p_property": propertyId.map { .string($0.uuidString) } ?? .null,
        ]
        let convId: UUID = try await withChatTimeout {
            try await supabase
                .rpc("dm_open_conversation", params: params)
                .execute()
                .value
        }
        let myUid = supabase.auth.currentSession?.user.id
        var members = [UnifiedMember(conversationId: convId, userId: myUid,
                                     memberId: nil, displayName: myName)]
        // A self-thread carries ONE member who is both parties.
        if !(peerUser != nil && peerUser == myUid) {
            members.append(UnifiedMember(conversationId: convId, userId: peerUser,
                                         memberId: peerMember, displayName: peerName))
        }
        let conv = UnifiedConversation(id: convId, members: members)
        unifiedConversations.append(conv)
        return conv
    }

    /// The unified `messages` insert `send()` posts when the flag is up.
    private struct UnifiedInsert: Encodable {
        let id: String
        let conversation_id: String
        let property_id: String?
        let sender_id: String?
        let sender_name: String
        let body: String
        let reply_to: String?
        let expires_at: String?
    }

    /// Batched side-table receipt payloads. The side tables demand a
    /// NOT NULL property_id, so a row without one carries no receipt — such
    /// a row predates property scoping and no live thread produces one.
    private struct UnifiedReadInsert: Encodable {
        let message_id: String
        let property_id: String
        let user_id: String
        let reader_name: String
        let read_at: String
    }

    private struct UnifiedDeliveryInsert: Encodable {
        let message_id: String
        let property_id: String
        let user_id: String
        let deliverer_name: String
        let delivered_at: String
    }

    /// Persists delivered receipts for inbound `rows`: ONE array upsert into
    /// `message_deliveries` (INSERT RLS: user_id = auth.uid(); the
    /// (message_id, user_id) conflict is ignored so a re-stamp is a no-op —
    /// the group engine's proven shape). Errors rethrow to the caller's
    /// existing handling.
    private func persistDeliveredReceipts(_ rows: [DirectMessage], nowISO: String,
                                          myName: String) async throws {
        // The session is the authority, `myUserId` only its cache: the retired
        // legacy path stamped by row id and needed no identity at all, so a
        // transiently-nil cache must not silently swallow every tick.
        guard let uid = supabase.auth.currentSession?.user.id ?? myUserId else { return }
        let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [UnifiedDeliveryInsert] = rows.compactMap { m in
            guard let pid = m.propertyId else { return nil }
            return UnifiedDeliveryInsert(
                message_id: m.id.uuidString, property_id: pid.uuidString,
                user_id: uid.uuidString, deliverer_name: name,
                delivered_at: nowISO)
        }
        guard !payload.isEmpty else { return }
        try await supabase
            .from("message_deliveries")
            .upsert(payload, onConflict: "message_id,user_id",
                    ignoreDuplicates: true)
            .execute()
    }

    /// Persists read receipts for inbound `unread`: one array upsert into
    /// `message_reads`, plus `message_deliveries` rows for messages never
    /// stamped delivered — read implies delivered, exactly what the retired
    /// two-column UPDATE meant.
    private func persistReadReceipts(_ unread: [DirectMessage], nowISO: String,
                                     myName: String) async throws {
        guard let uid = supabase.auth.currentSession?.user.id ?? myUserId else { return }
        let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let reads: [UnifiedReadInsert] = unread.compactMap { m in
            guard let pid = m.propertyId else { return nil }
            return UnifiedReadInsert(
                message_id: m.id.uuidString, property_id: pid.uuidString,
                user_id: uid.uuidString, reader_name: name, read_at: nowISO)
        }
        if !reads.isEmpty {
            try await supabase
                .from("message_reads")
                .upsert(reads, onConflict: "message_id,user_id",
                        ignoreDuplicates: true)
                .execute()
        }
        let deliveries: [UnifiedDeliveryInsert] = unread.compactMap { m in
            guard m.deliveredAt == nil, let pid = m.propertyId else { return nil }
            return UnifiedDeliveryInsert(
                message_id: m.id.uuidString, property_id: pid.uuidString,
                user_id: uid.uuidString, deliverer_name: name,
                delivered_at: nowISO)
        }
        if !deliveries.isEmpty {
            try await supabase
                .from("message_deliveries")
                .upsert(deliveries, onConflict: "message_id,user_id",
                        ignoreDuplicates: true)
                .execute()
        }
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
        // Never NULL a known identity: `load()` reruns on every dm_new
        // broadcast and every foreground, and a transiently-nil session
        // (mid token refresh) used to wipe `myUserId` — which silently
        // emptied every identity-matched thread until the next clean load
        // (IMG_8539: "messages jump, disappear"). A stale id for a few
        // seconds is harmless; a nil one blanks the UI.
        if let uid = supabase.auth.currentSession?.user.id { myUserId = uid }
        // A property switch drops the conversation roster before anything
        // reads it (send resolves its target from that cache).
        resetScopeIfNeeded(propertyId: propertyId)
        // Offline hydration (audit): paint the last cached window instantly
        // on a cold open. Guarded on empty — load() reruns on every dm_new
        // and foreground, and its MERGE below builds on richer in-memory
        // state that a stale snapshot must never overwrite.
        if dms.isEmpty,
           let cached = ServiceCache.load([DirectMessage].self,
                                          entity: Self.unifiedCacheEntity,
                                          propertyId: propertyId) {
            dms = cached
        }
        do {
            // Fetch the most recent 1000 (newest first), then show oldest→newest.
            // Previously this ordered ascending, which returned the *oldest* 1000
            // and could hide recent messages once a property had many DMs.
            // The fetch + decode run off the main actor (nonisolated helper) —
            // this was the last big main-thread JSON decode in the app.
            // The window comes from the unified store and is mapped back into
            // DirectMessage, so everything below this line is store-agnostic.
            let fetched = try await Self.fetchUnifiedRecent(propertyId: propertyId)
            // Roster for send's conversation resolution and older-page paging.
            unifiedConversations = fetched.conversations
            let rows = fetched.messages
            // MERGE, never replace: a wholesale `dms = rows` threw away the
            // older pages "Load older" had prepended, so history vanished and
            // the scroll anchor died (the viewport jumped to the bottom) every
            // time a reload landed mid-conversation. Fresh rows win on
            // conflict — they carry newer edits/reactions/receipts.
            var byId = Dictionary(dms.map { ($0.id, $0) },
                                  uniquingKeysWith: { _, new in new })
            for row in rows { byId[row.id] = row }
            // ISO-8601 timestamps sort lexicographically; id breaks the
            // (rare) same-instant tie so the order is fully deterministic.
            dms = byId.values.sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.createdAt < $1.createdAt
            }
            // Snapshot the recent window for the next cold/offline open
            // (bounded: cache only the newest fetch-window's worth).
            ServiceCache.save(Array(dms.suffix(1000)), entity: Self.unifiedCacheEntity,
                              propertyId: propertyId)
            // exhaustedOlder stays: reaching the beginning of a thread is a
            // fact about the SERVER's history — a refresh of the recent
            // window doesn't un-reach it. Entries are keyed per-thread
            // (storeKey), so flags from another property/account are simply
            // never consulted; history only grows forward, so a kept flag
            // can't hide anything.
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
        do {
            // One batched write instead of one per message (the old N+1,
            // which also fired N realtime updates and made every other client
            // reload N times). Reflect locally only after it persists. The
            // store (side table vs legacy column) is the helper's flag call.
            try await persistDeliveredReceipts(undelivered, nowISO: nowISO,
                                               myName: myName)
            for m in undelivered {
                if let i = dms.firstIndex(where: { $0.id == m.id }) { dms[i].deliveredAt = nowISO }
            }
        } catch { return }
    }

    // MARK: - Realtime (shared lifecycle — chat unification P3d)

    /// The DM channel's topic prefix; the property id completes the scope.
    /// A topic string is client-side scoping only — it names the CONVERSATION
    /// surface, not the table the handlers watch.
    private static let topicPrefix = "dm:"

    func subscribeRealtime(propertyId: UUID, myName: String) async {
        await realtime.subscribe(
            realtimeConfiguration(propertyId: propertyId, myName: myName))
    }

    /// Delivery safety net for an OPEN thread — see
    /// `ChatRealtimeChannel.ensureLiveDelivery`. On rebuild the refetch is a
    /// full merge-load, so nothing that arrived during the outage is missed.
    func ensureLiveDelivery(propertyId: UUID, myName: String) async {
        await realtime.ensureLiveDelivery(
            realtimeConfiguration(propertyId: propertyId, myName: myName))
    }

    /// This engine's seam into the shared lifecycle: the scoped topic, the
    /// handler registrations and the post-rebuild refetch. Built fresh per
    /// call — the closures capture the scope exactly like the pre-extraction
    /// code captured its parameters.
    private func realtimeConfiguration(propertyId: UUID,
                                       myName: String) -> ChatRealtimeChannel.Configuration {
        ChatRealtimeChannel.Configuration(
            topic: Self.topicPrefix + propertyId.uuidString,
            tag: "dm",
            register: { [weak self] ch in
                self?.registerRealtimeHandlers(on: ch, propertyId: propertyId,
                                               myName: myName) ?? []
            },
            refetch: { [weak self] in
                await self?.load(propertyId: propertyId, myName: myName)
            },
            onDetach: { [weak self] in
                guard let self else { return }
                // Engine state bound to the departing channel: the activity
                // indicator re-syncs before each use, and a pending debounced
                // refetch must not fire against a scope we just left.
                self.activity.channel = nil
                self.reloadTask?.cancel()
                self.headsTask?.cancel()
            })
    }

    /// Registers this engine's handlers on a fresh channel — callbacks must
    /// be registered before subscribing — and returns the retained handles
    /// (the shared lifecycle stores and clears them).
    private func registerRealtimeHandlers(on ch: RealtimeChannelV2, propertyId: UUID,
                                          myName: String) -> [RealtimeSubscription] {
        var subs: [RealtimeSubscription] = []
        let scope = "property_id=eq.\(propertyId.uuidString)"
        // WHERE WE READ AND WHAT WAKES US UP ARE TWO DIFFERENT DECISIONS.
        //
        // Reads, writes and history are unified (P6). The WAKE-UP stays on the
        // mirrored `direct_messages` stream — the path that delivered reliably
        // through b1177–b1199 — because b1200 shipped the unified listener and
        // the field evidence turned against it: a recipient's device stopped
        // stamping delivered/read for inbound rows (server-side chain verified
        // intact: notification row written, webhook 200, APNs accepted). Rather
        // than defend an unproven listener on the family's only chat, the
        // engine listens where delivery is PROVEN and keeps reading the unified
        // store. The forward+reverse mirrors make the two views of a row
        // identical, and ids are preserved, so a legacy-shaped event addresses
        // exactly the unified row the UI shows.
        //
        // This is also why `direct_messages` cannot be dropped yet: the drop is
        // gated on the unified listener being proven on-device, not on the
        // reads (which are already unified fleet-wide).
        //
        // Incremental reconciliation: append/patch/remove the single changed
        // row per event instead of refetching up to 1000 rows on every insert,
        // reaction, tick or edit. The legacy row carries receipts and reactions
        // in its own columns (kept current by the receipt/reaction mirrors), so
        // one swap brings ticks and reactions with it — no side-table channels
        // to get right. A full reload survives as the decode-failure fallback.
        subs.append(ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "direct_messages",
            filter: scope
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
        subs.append(ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "direct_messages",
            filter: scope
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
        // DELETE handler (shared shape — P5): drop by id, then refresh the
        // heads so the conversation list's preview follows the removal.
        subs.append(ChatEngineCore.registerDeleteHandler(
            on: ch, table: "direct_messages"
        ) { [weak self] id in
            guard let self else { return }
            self.dms.removeAll { $0.id == id }
            self.scheduleHeadsRefresh()
        })
        // Typing handler (shared shape — P5): the hook re-syncs channel/name
        // into the indicator right before each event, exactly as before.
        subs.append(ChatEngineCore.registerTypingHandler(on: ch) { [weak self] in
            guard let self else { return nil }
            self.syncActivity()
            return self.activity
        })
        // Reliable delivery: a peer's send broadcasts "dm_new"; fetch the newer
        // rows so the message appears live even when postgres_changes was
        // withheld by RLS. Skip my own echo — I already have the row.
        subs.append(ch.onBroadcast(event: "dm_new") { [weak self] json in
            Task { @MainActor [weak self] in
                guard let self, !ChatEngineCore.isOwnDeliveryPing(json) else { return }
                self.scheduleReload(propertyId: propertyId, myName: myName)
            }
        })
        return subs
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
            // The iMessage-style receive tone for a DM that lands while the
            // thread is open — the group chat already plays it on its own
            // inbound path; DMs had no sound at all. Keyed by the sender (the
            // peer) so the per-conversation tone/mute preference is honored;
            // playIncoming itself only sounds in the foreground.
            ChatToneStore.playIncoming(row.senderName)
        }
    }

    /// Applies a realtime UPDATE incrementally: reactions, read/delivered ticks,
    /// pin/mark, edits and delete-for-all tombstones all just swap the changed
    /// row in place. The mirrored row is COMPLETE — the receipt and reaction
    /// mirrors keep its legacy columns current — so the swap brings ticks and
    /// reactions with it. Rows outside the loaded set are ignored.
    private func applyRealtimeUpdate(_ row: DirectMessage) {
        guard let i = dms.firstIndex(where: { $0.id == row.id }) else { return }
        dms[i] = row
        scheduleHeadsRefresh()
    }

    func unsubscribe() async {
        // Engine-side teardown; the channel handles, the self-test and the
        // real leave-from-every-state (b1173) live in the shared lifecycle.
        activity.reset()
        reloadTask?.cancel()
        reloadTask = nil
        headsTask?.cancel()
        headsTask = nil
        await realtime.unsubscribe()
    }

    func deleteMessage(id: UUID) async {
        if await ChatMessageStore.deleteRow(table: "messages", id: id, tag: "DM") {
            dms.removeAll { $0.id == id }
        }
    }

    /// Delete for everyone — keeps the row but replaces it with a tombstone.
    /// A sender-own update (`messages` UPDATE RLS: sender only).
    func deleteForEveryone(id: UUID) async {
        if await ChatMessageStore.tombstoneRow(table: "messages", id: id, tag: "DM"),
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

    // Pin and mark belong to EITHER party — I may pin a message you sent me.
    // The `messages` UPDATE policy is sender-only (with_check: sender_id =
    // auth.uid()), which is exactly right for an edit and exactly wrong for
    // a pin, and RLS cannot scope a policy to two columns. So both go
    // through definer RPCs that gate on conversation membership and touch
    // only that one column — the narrow door instead of a wider policy.
    func togglePin(_ msg: DirectMessage) async {
        await toggleFlag("dm_set_pin", on: msg, at: \.pinned)
    }

    func toggleMark(_ msg: DirectMessage) async {
        await toggleFlag("dm_set_mark", on: msg, at: \.isMarked)
    }

    /// The shared pin/mark toggle: flip the flag through its RPC, then patch
    /// the loaded row — only after the server accepted, so a rejected toggle
    /// never leaves a lie on screen. The key path keeps one implementation
    /// honest about which column it just changed.
    private func toggleFlag(_ rpc: String, on msg: DirectMessage,
                            at flag: WritableKeyPath<DirectMessage, Bool?>) async {
        let newVal = !(msg[keyPath: flag] ?? false)
        do {
            try await supabase
                .rpc(rpc, params: ["p_message": AnyJSON.string(msg.id.uuidString),
                                   "p_value": AnyJSON.bool(newVal)])
                .execute()
            if let i = dms.firstIndex(where: { $0.id == msg.id }) {
                dms[i][keyPath: flag] = newVal
            }
        } catch {
#if DEBUG
            debugLog("[DM] \(rpc) error: \(error)")
#endif
            // P0b: the intent survives the failure — journaled with its
            // ABSOLUTE value and replayed on the next foreground beat.
            ChatMutationJournal.recordFlag(rpc: rpc, messageId: msg.id, value: newVal)
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
        // A reaction is a ROW now (shared sequence — P5): drop my existing
        // one, insert the new emoji. The local map is the legacy jsonb shape
        // the bubbles still read, rebuilt from those rows on every load.
        guard let uid = myUserId, let pid = msg.propertyId else { return }
        do {
            try await ChatEngineCore.persistReactionToggle(
                messageId: msg.id, propertyId: pid, userId: uid,
                reactorName: myName.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: emoji,
                removeExisting: current != nil,
                insertNew: current != emoji)
            if let i = dms.firstIndex(where: { $0.id == msg.id }) { dms[i].reactions = map }
        } catch {
#if DEBUG
            debugLog("[DM] toggleReaction error: \(error)")
#endif
            // P0b: journal the FINAL intent (react with `emoji` / un-react),
            // replayed idempotently on the next foreground beat.
            ChatMutationJournal.recordReaction(
                messageId: msg.id, propertyId: pid, userId: uid,
                reactorName: myName.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: emoji, insertNew: current != emoji)
        }
    }

    func editMessage(id: UUID, newBody: String) async {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        // An edit is sender-own — exactly what the `messages` UPDATE policy
        // (with_check: sender_id = auth.uid()) allows.
        if await ChatMessageStore.editRow(table: "messages", id: id, newBody: newBody,
                                          editedAtISO: nowISO, tag: "DM"),
           let i = dms.firstIndex(where: { $0.id == id }) {
            dms[i].body = newBody
            dms[i].editedAt = nowISO
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
        do {
            // Batched read (+implied delivered) stamps; the store is the
            // helper's flag call (side tables vs legacy columns, P4d-2).
            try await persistReadReceipts(unread, nowISO: nowISO, myName: myName)
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
            do {
                try await persistReadReceipts(unread, nowISO: nowISO, myName: myName)
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
    /// hand-off — the caller surfaces the error directly. The conversation is
    /// opened through the same RPC the send path uses, so forwarding into a
    /// thread that doesn't exist yet creates exactly the thread a first
    /// message would have.
    static func forward(body: String, senderName: String,
                        to member: FamilyMember, propertyId: UUID) async throws {
        let sender = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let peerName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let params: [String: AnyJSON] = [
            "p_my_name": .string(sender),
            "p_my_member": .null,
            "p_peer_user": member.userId.map { .string($0.uuidString) } ?? .null,
            "p_peer_member": .string(member.id.uuidString),
            "p_peer_name": .string(peerName),
            "p_property": .string(propertyId.uuidString),
        ]
        let convId: UUID = try await supabase
            .rpc("dm_open_conversation", params: params)
            .execute()
            .value
        struct DMForward: Encodable {
            let conversation_id: String
            let property_id: String
            let sender_id: String?
            let sender_name: String
            let body: String
        }
        try await supabase.from("messages").insert(
            DMForward(conversation_id: convId.uuidString,
                      property_id: propertyId.uuidString,
                      sender_id: supabase.auth.currentSession?.user.id.uuidString,
                      sender_name: sender, body: body)
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
        // The peer is a property of the CONVERSATION now, not of each row, so
        // the query only has to name the matching threads — a much smaller
        // result than the four identity columns the two-store world scanned.
        // RLS scopes `conversations` to my own, so a match can never surface
        // a thread I'm not in.
        let conversations = unifiedConversations.isEmpty
            ? ((try? await Self.fetchUnifiedConversations(propertyId: propertyId)) ?? [])
            : unifiedConversations
        guard !conversations.isEmpty else { return SearchHits() }
        struct Row: Decodable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey { case conversationId = "conversation_id" }
        }
        let rows: [Row] = (try? await supabase.from("messages")
            .select("conversation_id")
            .in("conversation_id", values: conversations.map(\.id.uuidString))
            .ilike("body", pattern: MessageService.likePattern(query))
            .limit(200)
            .execute().value) ?? []
        let matched = Set(rows.map(\.conversationId))
        var hits = SearchHits()
        for conv in conversations where matched.contains(conv.id) {
            guard let peer = conv.peer(myUserId: myUserId, myName: myName) else { continue }
            if let uid = peer.userId, uid != myUserId { hits.userIds.insert(uid) }
            hits.names.insert(peer.displayName)
        }
        return hits
    }
}

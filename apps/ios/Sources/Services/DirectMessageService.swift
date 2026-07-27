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
    /// The row's property scope (P4d-2): the unified receipt/reaction side
    /// tables demand a NOT NULL property_id, so every row carries its own —
    /// a row without one falls back to the legacy write path.
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
            // Unified write (P4d-2): with the server flag up the row goes to
            // the unified store — resolve the thread's conversation (read
            // cache first, `dm_open_conversation` RPC for a fresh thread),
            // insert into `messages` (RLS: sender + conversation member) and
            // fold the returned row back into DirectMessage. The reverse
            // mirror projects it into `direct_messages`, so legacy clients
            // and the existing realtime topic keep seeing it. Everything
            // around the insert — optimistic append, timeout, rollback-and-
            // rethrow (the caller's outbox hand-off), heads refresh, the
            // dm_new broadcast — is identical on both paths, and an attempt
            // never retries on the other store (double-send risk).
            let sent: DirectMessage
            if unifiedReadEnabled {
                let conv = try await resolveUnifiedConversation(
                    for: thread, myName: trimmedSender, propertyId: propertyId)
                let unifiedPayload = UnifiedInsert(
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
                        .insert(unifiedPayload)
                        .select(Self.unifiedColumns)
                        .single()
                        .execute()
                        .value
                }
                sent = Self.mapUnified(row, members: conv.members,
                                       reads: [], deliveries: [], reactions: [])
            } else {
                sent = try await withChatTimeout {
                    try await supabase
                        .from("direct_messages")
                        .insert(payload)
                        .select()
                        .single()
                        .execute()
                        .value
                }
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

    // MARK: - Unified read (P4c)
    //
    // Dual-read behind the SERVER flag (`chat_rollout.dm_unified_read`, a
    // service-role-only kill-switch): when it flips, load() reads the unified
    // store — `conversations` / `conversation_members` / `messages` plus the
    // receipt and reaction side tables — and folds every row back into the
    // legacy `DirectMessage` shape, so threads, bubbles, heads and search
    // downstream never notice the store change. P4d-2 flips the WRITES the
    // caller may make on the unified store behind the SAME flag — send,
    // read/delivered receipts, reactions, edit and delete-for-all (see
    // "Unified writes (P4d-2)"); pin/mark, realtime and older-page fetches
    // stay on `direct_messages`. The symmetric server mirror keeps both
    // stores identical either way, and ids are preserved, so every mutation
    // keeps landing on exactly the rows the other path displays.

    /// Server rollout flag. FAIL CLOSED: false until the server proves
    /// otherwise — any fetch error (offline cold start, an RLS surprise, the
    /// table missing on a stale environment) keeps the shipped legacy path,
    /// never a half-configured new one.
    private(set) var unifiedReadEnabled = false
    /// The property the flag was last resolved for — one flag round-trip per
    /// property switch, not one per reload (load() reruns on every dm_new
    /// broadcast and every foreground).
    @ObservationIgnored private var unifiedFlagProperty: UUID?

    /// Snapshot entity for the unified path — deliberately DIFFERENT from the
    /// legacy "dms" entity, so a flag flip can never poison the other path's
    /// offline cache with rows shaped by the wrong store.
    private static let unifiedCacheEntity = "dms.unified"

    /// Resolves `chat_rollout.dm_unified_read` once per property switch.
    /// The error branch is the design, not an afterthought: the legacy path
    /// is the shipped truth, so anything short of a decoded `true` reads as
    /// "stay legacy" — and the property still counts as checked, matching
    /// the once-per-switch contract instead of retrying on every reload.
    private func refreshUnifiedReadFlag(propertyId: UUID) async {
        guard unifiedFlagProperty != propertyId else { return }
        // Property switch: the send-path conversation cache (P4d-2) is scoped
        // to the outgoing property — the same peer usually exists in both, so
        // a stale entry could route a send into the wrong property's
        // conversation. Empty cache just means the RPC resolves the thread.
        unifiedConversations = []
        struct Row: Decodable {
            let dmUnifiedRead: Bool
            enum CodingKeys: String, CodingKey { case dmUnifiedRead = "dm_unified_read" }
        }
        do {
            let row: Row = try await supabase
                .from("chat_rollout")
                .select("dm_unified_read")
                .single()
                .execute()
                .value
            unifiedReadEnabled = row.dmUnifiedRead
        } catch {
            unifiedReadEnabled = false
        }
        unifiedFlagProperty = propertyId
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

    /// Network + decode off the main actor, mirroring `fetchRecent`: my DM
    /// conversations for this property (RLS: members-only), their members,
    /// the newest window of unified rows, then the receipt/reaction side
    /// tables — all folded back into `DirectMessage`. The explicit `.in` on
    /// MY conversation ids (rather than a bare `conversation_id not is null`)
    /// keeps the query index-friendly and self-documenting; RLS enforces
    /// membership either way. Same limit discipline as the legacy fetch:
    /// newest 1000, shown oldest→newest by the caller's sort.
    nonisolated private static func fetchUnifiedRecent(propertyId: UUID) async throws -> UnifiedFetch {
        struct ConvRow: Decodable { let id: UUID }
        let convs: [ConvRow] = try await supabase
            .from("conversations")
            .select("id")
            .eq("kind", value: "dm")
            .eq("property_id", value: propertyId.uuidString)
            .execute()
            .value
        guard !convs.isEmpty else { return UnifiedFetch(conversations: [], messages: []) }
        let convIds = convs.map(\.id.uuidString)
        let members: [UnifiedMember] = try await supabase
            .from("conversation_members")
            .select("conversation_id, user_id, member_id, display_name")
            .in("conversation_id", values: convIds)
            .execute()
            .value
        let membersByConv = Dictionary(grouping: members, by: \.conversationId)
        let conversations = convs.map {
            UnifiedConversation(id: $0.id, members: membersByConv[$0.id] ?? [])
        }
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

    // MARK: - Unified writes (P4d-2)
    //
    // Behind the SAME `dm_unified_read` flag as the read path — flag down,
    // every write below is byte-identical to the shipped legacy path. The
    // symmetric server mirror (P4d-1) projects unified writes back into
    // `direct_messages`, so old clients and the existing realtime topic stay
    // complete no matter which store a fleet member writes. Fail-closed: a
    // unified write that throws is handled exactly like the legacy path's
    // failure (outbox hand-off for send, best-effort elsewhere) and is NEVER
    // retried on the other store within the same attempt.

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
            let peer: UnifiedMember?
            if conv.members.count == 1 {
                peer = conv.members.first
            } else {
                peer = conv.members.first { m in
                    if let uid = myUserId, let mu = m.userId { return mu != uid }
                    return !DirectMessage.nameMatches(m.displayName, myName)
                }
            }
            guard let p = peer else { return false }
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
    /// NOT NULL property_id — rows without one stay on the legacy UPDATE.
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

    /// Persists delivered receipts for inbound `rows`. Flag up: one array
    /// upsert into `message_deliveries` (INSERT RLS: user_id = auth.uid();
    /// (message_id, user_id) conflict ignored so a re-stamp stays idempotent
    /// exactly like the legacy no-op UPDATE — the group engine's proven
    /// shape); the reverse mirror projects the rows into the legacy
    /// delivered_at column. Nil-property rows and the flag-off world take
    /// the legacy batched UPDATE. Errors rethrow to the caller's existing
    /// handling — one store per attempt, never a cross-store retry.
    private func persistDeliveredReceipts(_ rows: [DirectMessage], nowISO: String,
                                          myName: String) async throws {
        var legacyRows = rows
        if unifiedReadEnabled, let uid = myUserId {
            legacyRows = rows.filter { $0.propertyId == nil }
            let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [UnifiedDeliveryInsert] = rows.compactMap { m in
                guard let pid = m.propertyId else { return nil }
                return UnifiedDeliveryInsert(
                    message_id: m.id.uuidString, property_id: pid.uuidString,
                    user_id: uid.uuidString, deliverer_name: name,
                    delivered_at: nowISO)
            }
            if !payload.isEmpty {
                try await supabase
                    .from("message_deliveries")
                    .upsert(payload, onConflict: "message_id,user_id",
                            ignoreDuplicates: true)
                    .execute()
            }
        }
        guard !legacyRows.isEmpty else { return }
        try await supabase
            .from("direct_messages")
            .update(["delivered_at": nowISO])
            .in("id", values: legacyRows.map { $0.id.uuidString })
            .execute()
    }

    /// Persists read receipts for inbound `unread`. Flag up: one array
    /// upsert into `message_reads`, plus `message_deliveries` rows for
    /// messages never stamped delivered — read implies delivered, exactly
    /// the legacy two-column UPDATE's semantics. Nil-property rows and the
    /// flag-off world take the legacy batched UPDATEs, byte-identically.
    private func persistReadReceipts(_ unread: [DirectMessage], nowISO: String,
                                     myName: String) async throws {
        var legacyRows = unread
        if unifiedReadEnabled, let uid = myUserId {
            legacyRows = unread.filter { $0.propertyId == nil }
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
        guard !legacyRows.isEmpty else { return }
        // Read implies delivered, so rows with no delivered_at get both
        // stamped. Batch by which columns they need — at most two UPDATEs
        // total instead of one per message.
        let needBoth = legacyRows.filter { $0.deliveredAt == nil }.map { $0.id.uuidString }
        let readOnly = legacyRows.filter { $0.deliveredAt != nil }.map { $0.id.uuidString }
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
        // Unified-read rollout (P4c): resolve the server flag BEFORE touching
        // the cache — the two read paths hydrate from different entities, so
        // the flag must be known first. One round-trip per property switch.
        await refreshUnifiedReadFlag(propertyId: propertyId)
        // Each read path owns its own snapshot entity: a server flag flip must
        // never hydrate one store's rows from the other store's cache.
        let cacheEntity = unifiedReadEnabled ? Self.unifiedCacheEntity : "dms"
        // Offline hydration (audit): paint the last cached window instantly
        // on a cold open. Guarded on empty — load() reruns on every dm_new
        // and foreground, and its MERGE below builds on richer in-memory
        // state that a stale snapshot must never overwrite.
        if dms.isEmpty,
           let cached = ServiceCache.load([DirectMessage].self, entity: cacheEntity,
                                          propertyId: propertyId) {
            dms = cached
        }
        do {
            // Fetch the most recent 1000 (newest first), then show oldest→newest.
            // Previously this ordered ascending, which returned the *oldest* 1000
            // and could hide recent messages once a property had many DMs.
            // The fetch + decode run off the main actor (nonisolated helper) —
            // this was the last big main-thread JSON decode in the app.
            // Dual-read (P4c): with the server flag up, the same window comes
            // from the unified store instead — mapped back into DirectMessage,
            // so everything below this line is store-agnostic.
            let rows: [DirectMessage]
            if unifiedReadEnabled {
                let fetched = try await Self.fetchUnifiedRecent(propertyId: propertyId)
                // Roster for send's conversation resolution (P4d-2).
                unifiedConversations = fetched.conversations
                rows = fetched.messages
            } else {
                rows = try await Self.fetchRecent(propertyId: propertyId, myName: myName,
                                                  myUserId: myUserId)
            }
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
            // (bounded: cache only the newest fetch-window's worth). Saved
            // under the ACTIVE path's entity — see cacheEntity above.
            ServiceCache.save(Array(dms.suffix(1000)), entity: cacheEntity,
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
    private static let topicPrefix = "direct_messages:"

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
        // Incremental reconciliation: append/patch/remove the single changed row
        // per event instead of refetching up to 1000 rows on every insert,
        // reaction, tick or edit (which also chained load → markDelivered → a
        // fresh event → another reload). A full reload survives only as the
        // decode-failure fallback.
        subs.append(ch.onPostgresChange(
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
        subs.append(ch.onPostgresChange(
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
        subs.append(ch.onPostgresChange(
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
        subs.append(ch.onBroadcast(event: "typing") { [weak self] json in
            // The broadcast fields live inside the envelope's payload (see
            // RealtimeBroadcast) — reading them off the top level is what left
            // typing/recording dead while the channel was "subscribed".
            if let name = broadcastString(json, "name") {
                // Older clients broadcast no kind — treat them as typing.
                let kind = broadcastString(json, "kind") ?? "typing"
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.syncActivity()
                    self.activity.handleTyping(name, kind: kind)
                }
            }
        })
        // Reliable delivery: a peer's send broadcasts "dm_new"; fetch the newer
        // rows so the message appears live even when postgres_changes was
        // withheld by RLS. Skip my own echo — I already have the row.
        subs.append(ch.onBroadcast(event: "dm_new") { [weak self] json in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let from = broadcastString(json, "from"),
                   from == supabase.auth.currentSession?.user.id.uuidString { return }
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
    /// row in place. Rows outside the loaded set are ignored.
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
        if await ChatMessageStore.deleteRow(table: "direct_messages", id: id, tag: "DM") {
            dms.removeAll { $0.id == id }
        }
    }

    /// Delete for everyone — keeps the row but replaces it with a tombstone.
    /// P4d-2: a sender-own update, so with the flag up it flips on the
    /// unified row (`messages` UPDATE RLS: sender only) and the mirror
    /// projects it back into `direct_messages`.
    func deleteForEveryone(id: UUID) async {
        let table = unifiedReadEnabled ? "messages" : "direct_messages"
        if await ChatMessageStore.tombstoneRow(table: table, id: id, tag: "DM"),
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

    // P4d-2: pin/mark deliberately STAY on `direct_messages` even with the
    // unified flag up — the unified `messages` UPDATE RLS is sender-only
    // (with_check: sender_id = auth.uid()), so the PEER could never toggle a
    // message they received; the legacy policy allows both parties and the
    // forward mirror syncs the unified row.
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

    // P4d-2: stays legacy for the same peer-RLS reason as togglePin.
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
            if unifiedReadEnabled, let uid = myUserId, let pid = msg.propertyId {
                // P4d-2: side-table write — drop my existing row (DELETE RLS:
                // own rows) and insert the new emoji (INSERT RLS: conversation
                // member). The mirror folds the rows back into the legacy
                // jsonb map, so old clients keep seeing the reaction. The
                // local map update below is identical to the legacy path's.
                if current != nil {
                    try await supabase
                        .from("message_reactions")
                        .delete()
                        .eq("message_id", value: msg.id.uuidString)
                        .eq("user_id", value: uid.uuidString)
                        .execute()
                }
                if current != emoji {
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
                            message_id: msg.id.uuidString,
                            property_id: pid.uuidString,
                            user_id: uid.uuidString,
                            reactor_name: myName.trimmingCharacters(in: .whitespacesAndNewlines),
                            emoji: emoji))
                        .execute()
                }
            } else {
                try await supabase
                    .from("direct_messages")
                    .update(["reactions": map])
                    .eq("id", value: msg.id.uuidString)
                    .execute()
            }
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
            // P4d-2: an edit is sender-own, so with the flag up it lands on
            // the unified row (`messages` UPDATE RLS: sender only) and the
            // mirror projects it back into `direct_messages`.
            let table = unifiedReadEnabled ? "messages" : "direct_messages"
            try await supabase
                .from(table)
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

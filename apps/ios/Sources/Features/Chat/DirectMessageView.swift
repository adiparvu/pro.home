import SwiftUI
import PhotosUI
import UIKit
import Supabase
import UniformTypeIdentifiers

// MARK: - Direct Message View (1-on-1 private chat)

struct DirectMessageView: View {
    /// Roster row when the peer is on the family_members roster; nil for a
    /// peer known only by identity (e.g. the property owner on a non-owner
    /// device — the production case this phase fixes).
    let member: FamilyMember?
    /// Peer identity handed in by the conversation list; nil when this view
    /// was opened through the legacy member-based initializer (the identity
    /// then resolves from member.user_id + the profiles directory).
    private let initialPeer: ChatPeer?

    /// Legacy adapter — existing call sites keep compiling.
    init(member: FamilyMember) {
        self.member = member
        self.initialPeer = nil
    }

    init(peer: ChatPeer, member: FamilyMember? = nil) {
        self.member = member
        self.initialPeer = peer
    }

    @Environment(DirectMessageService.self) var directMessageService
    @Environment(ProfileService.self) var profileService
    @Environment(PropertyService.self) var propertyService
    @Environment(FamilyService.self) var familyService
    @Environment(MessageService.self) var messageService
    @Environment(PresenceService.self) private var presenceService
    @Environment(NotificationService.self) private var notificationService
    @Environment(\.scenePhase) private var scenePhase

    @State var replyingTo: DirectMessage? = nil
    @State var forwarding: DirectMessage? = nil
    @State private var showSearch = false
    @State var searchText = ""
    @State private var showStarred = false
    @State var scrollTarget: UUID? = nil
    // Global defaults from Chat Settings.
    @AppStorage("prvio.chatTheme") private var chatThemeID: String = "appDefault"
    @AppStorage("prvio.chatBubbleHex") private var chatBubbleHex = ""
    @AppStorage("prvio.chatBgID") private var chatBgID = ""
    // A background can be a gradient (chatBgID), a PHOTO (chatBgImage) or an
    // ANIMATED preset (chatBgAnim). All three must be observed, or picking a
    // photo/animated wallpaper in Chat Settings left every open chat on its
    // stale background — the keys changed but nothing re-rendered.
    @AppStorage("prvio.chatBgImage") private var chatBgImage = ""
    @AppStorage("prvio.chatBgAnim") private var chatBgAnim = ""
    @State private var themeRefresh = 0
    /// False until entry settles. The parent loads the conversation
    /// asynchronously and a server refresh can replace it moments later —
    /// BOTH batches must land unanimated, so this flips only after a short
    /// grace window, not on the first count change.
    @State var chatDidLoad = false
    /// Grace timer that flips `chatDidLoad`; started once the list is non-empty.
    @State private var chatLoadGraceTask: Task<Void, Never>? = nil
    /// Per-change animation gate, decided in `onChange` (which runs ahead of
    /// the body pass that renders the change): spring only for small deltas
    /// (send/receive), never for bulk merges (refresh, older-page loads).
    @State var animateMessageDelta = false
    /// Newest message id — distinguishes appends (auto-scroll) from prepends
    /// like "load older" (keep the reading position).
    @State var newestMessageId: UUID? = nil
    /// Guards the jump-to-latest button against rapid re-taps mid-flight.
    @State var isJumpingToLatest = false
    /// Shared jump-to-latest coordinator (visibility + debounced toggle).
    @State var scroll = ConversationScrollModel()
    @State var editingMessage: DirectMessage? = nil
    @State var editText = ""
    @State var menuMessage: DirectMessage? = nil
    @State var deleteCandidate: DirectMessage? = nil
    /// Whether the reader is at (or within a bubble of) the bottom — the gate
    /// for auto-following incoming messages and for honest read receipts.
    /// Driven by live scroll geometry on iOS 18+ (see ChatAtBottomModifier);
    /// the bottom sentinel keeps it updated on older systems.
    @State var isAtBottom = true
    /// How many of the most-recent messages to render. The service holds the
    /// full conversation in memory; the list only builds this trailing window
    /// so opening a long chat stays cheap, growing a page at a time as the user
    /// scrolls back. Searching bypasses the window (it scans everything).
    @State var visibleCount = DirectMessageView.pageSize
    static let pageSize = 50
    /// Where the reader left off, frozen on open before markRead runs, and the
    /// resulting first-unread message id that anchors the "unread" divider.
    @State private var unreadSince: Date? = nil
    @State var unreadDividerId: UUID? = nil
    @State private var unreadResolved = false
    @State var highlightedId: UUID? = nil
    @State var input = ""
    /// One-slot memo behind `conversationMessages` (see DerivedCache).
    @State private var conversationCache = DerivedCache<[DirectMessage]>()
    /// The composer's optional subject line (iMessage's "Show Subject Field").
    /// Encoded into the body at send time (see MessageSubject), so the DM
    /// send path, outbox and realtime stay untouched.
    @State var subject = ""
    /// Chat Settings → "Show Subject Field". OFF by default.
    @AppStorage(MessageSubject.showFieldDefaultsKey) var showSubjectField = false
    @State var photoPickerItems: [PhotosPickerItem] = []
    @State var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State var showAttachmentSheet = false
    @State private var showContactPicker = false
    @State private var showSendLater = false
    @State private var showLocationSheet = false
    @State private var showFileImporter = false
    @State private var showEventComposer = false
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    /// Resolved FaceTime handle for the peer — account e-mail, then roster
    /// e-mail, then roster phone (see FaceTimeBridge). Nil means the header
    /// renders NO call buttons at all (never a dead control).
    @State private var faceTimeHandle: String? = nil
    @State private var showProfile = false
    @State var sendError: String? = nil
    @FocusState var focused: Bool
    @State var isSending = false
    @State var outbox = OfflineOutbox(filename: "chat_outbox_dm.json")
    @State var blockRefresh = false

    var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    // MARK: - Peer identity
    //
    // The thread is addressed by the peer's AUTH USER ID; display data
    // re-hydrates from the profiles directory on every render so a rename or
    // a new avatar lands immediately. Device-local stores keep their historic
    // member-id keys for roster-backed threads.

    private var peer: ChatPeer? {
        if let initialPeer {
            return ChatPeer(userId: initialPeer.id,
                            fallbackName: initialPeer.displayName,
                            fallbackAvatar: initialPeer.avatarUrl)
        }
        return member.flatMap { ChatPeer(member: $0) }
    }

    var thread: DMThread {
        if let member { return DMThread(member: member) }
        if let peer { return DMThread(peer: peer) }
        // Unreachable: both initializers guarantee a member or a peer.
        return DMThread(peer: ChatPeer(id: UUID(), displayName: "?"))
    }

    /// Trimmed display name for the header/title/empty state.
    var peerName: String { thread.displayName }
    var peerInitials: String { peer?.initials ?? member?.initials ?? "?" }
    var peerColor: Color { member?.swiftColor ?? peer?.swiftColor ?? .blue }
    var peerAvatarURL: URL? {
        (peer?.avatarUrl ?? member?.avatarUrl).flatMap(URL.init)
    }
    /// Device-local conversation scope (theme, clear, block, draft stores) —
    /// the member id for roster threads (preserving existing keys), else the
    /// peer's user id.
    var convId: String { thread.storeKey.uuidString }
    /// Key the disappearing-message TTL store uses (historically the roster
    /// name; the trimmed profile name for identity-only peers).
    var disappearKey: String { member?.name ?? peerName }
    /// Name-keyed live signals (typing, presence) may carry either the roster
    /// snapshot or the (possibly untrimmed) profile name — match both.
    /// Internal: the message list extension derives the activity bubble from it.
    func matchesPeer(_ name: String) -> Bool {
        DirectMessage.nameMatches(name, peerName)
            || (member.map { DirectMessage.nameMatches(name, $0.name) } ?? false)
    }

    /// Disappearing-message expiry for this conversation (nil = off). Stamped on
    /// outgoing DMs so the server sweep deletes them; keyed by the partner name.
    var dmExpiresAt: String? {
        let ttl = ChatDisappearStore.ttl(disappearKey)
        return ttl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(ttl)) : nil
    }

    var conversationMessages: [DirectMessage] {
        // Memoized on the data revision + the two cutoff settings: a body
        // pass accesses this ~19 times, and the body re-runs on every
        // keystroke — re-filtering the whole conversation each time was the
        // typing lag. The 30s time bucket bounds staleness of the
        // time-relative disappearing cutoff between data changes.
        var hasher = Hasher()
        hasher.combine(directMessageService.revision)
        hasher.combine(ConversationClearStore.clearedAt(convId))
        hasher.combine(ChatDisappearStore.ttl(disappearKey))
        hasher.combine(Int(Date().timeIntervalSince1970 / 30))
        return conversationCache.value(for: hasher.finalize()) {
            let all = directMessageService.messages(in: thread, myName: myName)
            let kept = ConversationClearStore.filter(all, convId: convId) { $0.date }
            // Keyed by peer NAME — the same key the send path stamps with and the
            // server sync writes to (it used to be member.id, so the setting and
            // the stamp never met).
            return ChatDisappearStore.filter(kept, convId: disappearKey) { $0.date }
        }
    }

    // This DM's theme scope; a per-conversation override wins over the global default.
    private var themeScope: String { convId }
    var chatTheme: ChatTheme {
        _ = themeRefresh
        // The @AppStorage globals establish observation so a live global
        // change re-renders; resolution itself is centralized in effective().
        _ = (chatThemeID, chatBubbleHex, chatBgID, chatBgImage, chatBgAnim)
        return .effective(scope: themeScope)
    }
    private var draftKey: String { "draft.dm.\(convId)" }
    private var subjectDraftKey: String { draftKey + ".subject" }
    var pendingOutbox: [PendingMessage] {
        outbox.pending
            .filter { ($0.recipientName.map(matchesPeer) ?? false) && $0.propertyId == propertyService.primary?.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Live presence only: a green dot on the avatar while the partner is
    /// online (and sharing presence). A stale "last seen 10 hours ago" line
    /// is history, not status — it pushed the name off-center all day
    /// (IMG_8287); the full last-seen detail keeps living on the contact
    /// details page. Presence is looked up by the peer's AUTH USER ID —
    /// display names drift and carry stray whitespace ("Adi " in
    /// production), so a name-keyed lookup silently missed. The ticker
    /// re-evaluates every 30s so a stopped heartbeat decays from online
    /// without needing a new event.
    @ViewBuilder private func headerAvatar(at now: Date) -> some View {
        let status = presenceService.status(userId: thread.peerUserId,
                                            name: member?.name ?? peerName, at: now)
        PeerCircleAvatar(name: peerName, color: peerColor,
                         avatarUrl: peer?.avatarUrl ?? member?.avatarUrl,
                         size: 30)
            .overlay(alignment: .bottomTrailing) {
                if case .online = status {
                    Circle()
                        .fill(Color.brandSuccess)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("online")
                }
            }
    }

    var body: some View {
        // The wallpaper is applied as a BACKGROUND of the message list rather
        // than as a ZStack sibling: `.background` is sized to the list and can
        // never enlarge it, whereas a `scaledToFill` wallpaper inside a ZStack
        // reports a layout size wider than the screen for landscape photos,
        // which stretched the list and pushed sent bubbles off the right edge.
        // This matches the group chat (`ChatView`), which frames correctly.
        messageList
        // The compose bar lives in the safe-area inset — the canonical
        // iMessage structure. It can never be pushed off-screen by the
        // list's internal geometry (the empty-state GeometryReader used to
        // swallow it), and the scroll view gains the matching bottom inset
        // automatically.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ChatBlockStore.isBlocked(convId) {
                blockedBanner
            } else {
                inputBar
            }
        }
        // Full-bleed behind both the list and the compose inset. The theme
        // view pins itself to the whole screen via ignoresSafeArea(.all) —
        // container AND keyboard — so the wallpaper never re-scales when the
        // keyboard presents or the composer grows (the reported zoom/pan).
        .background(chatTheme.background)
        // iMessage-style header: no bar, the conversation slides under a
        // progressive blur and only glass controls float on top.
        .overlay(alignment: .top) { ChatTopBlur() }
        .overlay {
            if directMessageService.isLoading && conversationMessages.isEmpty {
                MessageSkeleton()
            }
        }
        .overlay {
            if let m = menuMessage { dmActionOverlay(m) }
        }
        .navigationTitle(peerName)
        .navigationBarTitleDisplayMode(.inline)
        // Search is summoned on demand (contact details / the magnifier for
        // identity-only peers) — never a bar pinned under the header.
        .chatOnDemandSearch(text: $searchText, isPresented: $showSearch,
                            prompt: Text("Search in conversation"))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Contact details need a roster row — identity-only peers get
                // a static header instead of a dead push.
                Button { if member != nil { showProfile = true } } label: {
                    ChatHeaderPill {
                        HStack(spacing: 8) {
                            PresenceTicker { now in headerAvatar(at: now) }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(peerName)
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(.primary)
                                // The only text under the name is the
                                // transient typing signal — everything else
                                // leaves the name vertically centered.
                                if directMessageService.recordingNames.contains(where: matchesPeer) {
                                    Text("recording…")
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(Color.accentColor)
                                } else if directMessageService.typingNames.contains(where: matchesPeer) {
                                    Text("typing…")
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    // Stage-1 in-chat calling: audio/video buttons that bridge
                    // straight to FaceTime, rendered only once a handle has
                    // resolved for this peer (see FaceTimeBridge — no dead
                    // controls; FaceTime owns reachability from there).
                    if let handle = faceTimeHandle {
                        DMFaceTimeHeaderButtons(handle: handle)
                    }
                    if member == nil {
                        // Identity-only peers have no contact-details page (the
                        // usual search entry), so the magnifier keeps in-thread
                        // search reachable now that the bar is no longer pinned.
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // iOS 26 wraps toolbar items in system Liquid Glass —
                        // only pre-26 draws its own capsule.
                        .chatToolbarCapsule()
                        .accessibilityLabel(Text("Search in conversation"))
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            if let member {
                ContactDetailsView(
                    member: member,
                    onAudio: { showCallSheet = true },
                    onVideo: { showVideoSheet = true },
                    onSearch: { showSearch = true },
                    onStarred: { showStarred = true },
                    mediaURLs: sharedMediaURLs,
                    exportText: exportTranscript,
                    propertyId: propertyService.primary?.id
                )
            }
        }
        .sheet(isPresented: $showCallSheet) {
            if let member {
                CallPickerSheet(members: [member], isVideo: false)
            }
        }
        .sheet(isPresented: $showVideoSheet) {
            if let member {
                CallPickerSheet(members: [member], isVideo: true)
            }
        }
        .sheet(item: $forwarding) { msg in
            ForwardPicker(members: familyService.members) { dest in
                Task { await forward(msg, to: dest) }
                forwarding = nil
            }
        }
        .sheet(isPresented: $showStarred) {
            DMStarredView(messages: markedMessages) { id in
                showStarred = false
                scrollTarget = id
            }
        }
        .overlay {
            // The menu owns its own blur-in + spring-from-corner motion, so
            // it mounts without a transition (a wrapping scale would zoom the
            // full-screen backdrop from the corner too — see ChatAttachmentSheet).
            if showAttachmentSheet {
                ChatAttachmentSheet(
                    isPresented: $showAttachmentSheet,
                    onPhotos: { showPhotoPicker = true },
                    onCamera: { showCameraPicker = true },
                    onLocation: { showLocationSheet = true },
                    onDocument: { showFileImporter = true },
                    onContact: { showContactPicker = true },
                    onEvent: { showEventComposer = true },
                    onSendLater: { showSendLater = true }
                )
            }
        }
        .sheet(isPresented: $showSendLater) {
            if let uid = supabase.auth.currentSession?.user.id {
                SendLaterSheet(context: .dm(
                    propertyId: propertyService.primary?.id,
                    authorId: uid,
                    authorName: myName,
                    recipientName: member?.name ?? peerName
                ))
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactMultiPicker(members: familyService.members) { payloads in
                Task { await sendDMContacts(payloads) }
            }
        }
        .sheet(isPresented: $showLocationSheet) {
            LocationShareSheet(propertyId: propertyService.primary?.id, myName: myName) { lat, lon in
                Task { await sendDMLocation(lat: lat, lon: lon) }
            }
        }
        .sheet(isPresented: $showEventComposer) {
            EventComposerView { draft in
                Task { await sendDMEvent(draft) }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await sendDMFile(url: url) }
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            DMCameraPickerView(isPresented: $showCameraPicker) { img in
                Task { @MainActor in await sendCameraImage(img) }
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        // Ensure the DM realtime channel is live while the thread is open — the
        // conversation list's teardown must never leave an open thread silent.
        // subscribeRealtime is idempotent, so this is a no-op when already live.
        .task { await MemberDirectory.shared.loadIfNeeded() }
        // Resolve the peer's FaceTime handle (account e-mail → roster e-mail
        // → roster phone). Keyed on the roster so the buttons appear as soon
        // as a late-loading roster row supplies a handle — and disappear if
        // the last handle-bearing source goes away.
        .task(id: familyService.members) {
            faceTimeHandle = await FaceTimeBridge.handle(
                for: peer, member: member, roster: familyService.members)
        }
        .task {
            // Keep any live-location bubble in this thread following the sharer
            // while it's open — mirrors the group chat's refresh loop. The same
            // tick doubles as the delivery safety net: if the realtime channel
            // isn't genuinely subscribed, rebuild it and refetch, so an open
            // thread can never sit silent (free when the channel is healthy).
            guard let pid = propertyService.primary?.id else { return }
            while !Task.isCancelled {
                await LiveLocationService.shared.load(propertyId: pid)
                await directMessageService.ensureLiveDelivery(propertyId: pid, myName: myName)
                try? await Task.sleep(nanoseconds: 7_000_000_000)
            }
        }
        .task {
            guard let pid = propertyService.primary?.id else { return }
            directMessageService.myName = myName
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
            // Event-RSVP storage rides the same lifecycle as the DM channel:
            // property-scoped, subscribed while a thread is open and never
            // torn down on disappear (no view calls the DM unsubscribe either
            // — the conversation list depends on the live channel). Both
            // calls are idempotent.
            await DMVoteStore.shared.load(propertyId: pid)
            await DMVoteStore.shared.subscribeRealtime(propertyId: pid)
        }
        // Foreground catch-up: iOS freezes the realtime socket in the
        // background and missed events are never replayed on reconnect, so a
        // message that arrived while suspended (its push already shown) would
        // sit invisible until some other reload. Refetch the window the moment
        // the scene is active again; subscribeRealtime is idempotent.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let pid = propertyService.primary?.id else { return }
            Task {
                await directMessageService.load(propertyId: pid, myName: myName)
                await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
                // RSVPs cast while the app was suspended were never replayed
                // either — refetch and re-assert the votes channel too.
                await DMVoteStore.shared.load(propertyId: pid)
                await DMVoteStore.shared.subscribeRealtime(propertyId: pid)
            }
        }
        .onAppear {
            // Mark this DM as the active chat so a foreground push for it is
            // suppressed (the message arrives live instead) — WhatsApp behavior.
            if let peer = thread.peerUserId { ActiveChat.set(ActiveChat.dmKey(peer)) }
            themeRefresh &+= 1
            newestMessageId = conversationMessages.last?.id
            if !conversationMessages.isEmpty { startLoadGraceIfNeeded() }
            // Freeze the prior last-seen BEFORE markRead overwrites it, so the
            // divider marks where this session started — not messages that
            // arrive while we're reading.
            unreadSince = directMessageService.lastSeen(for: thread)
            resolveUnreadDivider()
            directMessageService.markRead(thread: thread)
            Task { await directMessageService.markReadRemote(thread: thread, myName: myName) }
            // Opening the thread clears the chat notification rows + the icon
            // badge so the bell can't keep claiming messages now read.
            if let uid = supabase.auth.currentSession?.user.id {
                Task { await notificationService.markModuleRead("chat", userId: uid) }
            }
            Task { await flushOutbox() }
            if let pid = propertyService.primary?.id {
                Task { await presenceService.load(propertyId: pid) }
            }
            if input.isEmpty, let d = UserDefaults.standard.string(forKey: draftKey), !d.isEmpty { input = d }
            if subject.isEmpty, let s = UserDefaults.standard.string(forKey: subjectDraftKey), !s.isEmpty { subject = s }
        }
        .onDisappear {
            if let peer = thread.peerUserId { ActiveChat.clear(ifCurrent: ActiveChat.dmKey(peer)) }
            chatLoadGraceTask?.cancel()
            chatLoadGraceTask = nil
            scroll.cancel()
            // Persist the unsent composer draft once, on the way out.
            if input.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
            else { UserDefaults.standard.set(input, forKey: draftKey) }
            if subject.isEmpty { UserDefaults.standard.removeObject(forKey: subjectDraftKey) }
            else { UserDefaults.standard.set(subject, forKey: subjectDraftKey) }
        }
        .onChange(of: conversationMessages.count) { _, _ in
            // The parent loads messages asynchronously, so they may arrive after
            // onAppear; resolve the divider on the first non-empty state, once.
            resolveUnreadDivider()
            // The scroll view (and its own onChange) mounts only once messages
            // exist, so it never sees the 0→N transition — arm the entry grace
            // window from here as well.
            if !conversationMessages.isEmpty { startLoadGraceIfNeeded() }
        }
        .onChange(of: outbox.isOnline) { _, online in
            if online { Task { await flushOutbox() } }
        }
        .onChange(of: isAtBottom) { _, atBottom in
            // Scrolling back down to the bottom is the honest "I've now seen
            // these" moment for messages that arrived while reading up-thread
            // (the count handler deliberately skips them). The remote stamp
            // flips the sender's ticks to read in realtime.
            guard atBottom, chatDidLoad else { return }
            directMessageService.markRead(thread: thread)
            Task { await directMessageService.markReadRemote(thread: thread, myName: myName) }
        }
        .onChange(of: propertyService.primary?.id) { _, id in
            // The property can load after onAppear; retry any queued messages
            // once we finally have an id to attach them to.
            if id != nil { Task { await flushOutbox() } }
        }
        .alert("Message Not Sent", isPresented: .init(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .confirmationDialog("Delete message?", isPresented: .init(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            if let m = deleteCandidate {
                if m.isMine(myUserId: directMessageService.myUserId, myName: myName) {
                    Button("Delete for everyone", role: .destructive) {
                        HapticFeedback.warning()
                        Task { await directMessageService.deleteForEveryone(id: m.id) }
                        deleteCandidate = nil
                    }
                }
                Button("Delete for me", role: .destructive) {
                    HapticFeedback.warning()
                    directMessageService.deleteForMe(id: m.id)
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            }
        }
        .alert("Edit message", isPresented: .init(
            get: { editingMessage != nil },
            set: { if !$0 { editingMessage = nil } }
        )) {
            TextField("Message", text: $editText)
            Button("Cancel", role: .cancel) { editingMessage = nil }
            Button("Save") {
                if let m = editingMessage {
                    let newText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newText.isEmpty {
                        // Editing rewrites the TEXT; a subject on the original
                        // message is preserved verbatim through re-encoding.
                        let newBody = MessageSubject.encode(
                            subject: MessageSubject.parse(m.body).subject ?? "", text: newText)
                        Task { await directMessageService.editMessage(id: m.id, newBody: newBody) }
                    }
                }
                editingMessage = nil
            }
        }
    }

    /// Resolve the unread-divider anchor exactly once, from the frozen
    /// last-seen date, as soon as the conversation has loaded.
    private func resolveUnreadDivider() {
        guard !unreadResolved, let since = unreadSince, !conversationMessages.isEmpty else { return }
        unreadDividerId = directMessageService.firstUnreadId(
            in: thread, myName: myName, since: since)
        unreadResolved = true
    }

    /// Arms the entry grace window once. `chatDidLoad` may only flip after the
    /// server refresh has had time to land; flipping it on the first count
    /// change let the refresh batch animate — the visible settle on entry.
    func startLoadGraceIfNeeded() {
        guard chatLoadGraceTask == nil else { return }
        chatLoadGraceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            chatDidLoad = true
        }
    }

    private var markedMessages: [DirectMessage] {
        conversationMessages.filter { $0.isMarked == true && $0.deletedForAll != true }
    }
}

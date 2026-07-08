import SwiftUI
import PhotosUI
import UIKit
import Supabase

// MARK: - Direct Message View (1-on-1 private chat)

struct DirectMessageView: View {
    let member: FamilyMember

    @Environment(DirectMessageService.self) private var directMessageService
    @Environment(ProfileService.self) private var profileService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(MessageService.self) private var messageService
    @Environment(PresenceService.self) private var presenceService

    @State private var replyingTo: DirectMessage? = nil
    @State private var forwarding: DirectMessage? = nil
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showStarred = false
    @State private var showThemePicker = false
    @State private var scrollTarget: UUID? = nil
    // Global defaults from Chat Settings.
    @AppStorage("prvio.chatTheme") private var chatThemeID: String = "appDefault"
    @AppStorage("prvio.chatBubbleHex") private var chatBubbleHex = ""
    @AppStorage("prvio.chatBgID") private var chatBgID = ""
    @State private var themeRefresh = 0
    /// False until entry settles. The parent loads the conversation
    /// asynchronously and a server refresh can replace it moments later —
    /// BOTH batches must land unanimated, so this flips only after a short
    /// grace window, not on the first count change.
    @State private var chatDidLoad = false
    /// Grace timer that flips `chatDidLoad`; started once the list is non-empty.
    @State private var chatLoadGraceTask: Task<Void, Never>? = nil
    /// Per-change animation gate, decided in `onChange` (which runs ahead of
    /// the body pass that renders the change): spring only for small deltas
    /// (send/receive), never for bulk merges (refresh, older-page loads).
    @State private var animateMessageDelta = false
    /// Newest message id — distinguishes appends (auto-scroll) from prepends
    /// like "load older" (keep the reading position).
    @State private var newestMessageId: UUID? = nil
    /// Guards the jump-to-latest button against rapid re-taps mid-flight.
    @State private var isJumpingToLatest = false
    /// Debounce for the bottom-sentinel toggle (see `setJumpToLatest`).
    @State private var jumpToggleTask: Task<Void, Never>? = nil
    @State private var editingMessage: DirectMessage? = nil
    @State private var editText = ""
    @State private var menuMessage: DirectMessage? = nil
    @State private var deleteCandidate: DirectMessage? = nil
    @State private var showJumpToLatest = false
    /// How many of the most-recent messages to render. The service holds the
    /// full conversation in memory; the list only builds this trailing window
    /// so opening a long chat stays cheap, growing a page at a time as the user
    /// scrolls back. Searching bypasses the window (it scans everything).
    @State private var visibleCount = DirectMessageView.pageSize
    private static let pageSize = 50
    /// Where the reader left off, frozen on open before markRead runs, and the
    /// resulting first-unread message id that anchors the "unread" divider.
    @State private var unreadSince: Date? = nil
    @State private var unreadDividerId: UUID? = nil
    @State private var unreadResolved = false
    @State private var highlightedId: UUID? = nil
    @State private var input = ""
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State private var showAttachmentTray = false
    @State private var showAttachmentSheet = false
    @State private var showContactPicker = false
    @State private var showSendLater = false
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    @State private var showProfile = false
    @State private var sendError: String? = nil
    @FocusState private var focused: Bool
    @State private var isSending = false
    @State private var lastTypingSent = Date.distantPast
    @State private var audioRecorder = ChatAudioRecorder()
    @State private var outbox = OfflineOutbox(filename: "chat_outbox_dm.json")
    @State private var blockRefresh = false

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    /// Disappearing-message expiry for this conversation (nil = off). Stamped on
    /// outgoing DMs so the server sweep deletes them; keyed by the partner name.
    private var dmExpiresAt: String? {
        let ttl = ChatDisappearStore.ttl(member.name)
        return ttl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(ttl)) : nil
    }

    private var conversationMessages: [DirectMessage] {
        let all = directMessageService.messages(with: member.name, myName: myName)
        let kept = ConversationClearStore.filter(all, convId: member.id.uuidString) { $0.date }
        // Keyed by peer NAME — the same key the send path stamps with and the
        // server sync writes to (it used to be member.id, so the setting and
        // the stamp never met).
        return ChatDisappearStore.filter(kept, convId: member.name) { $0.date }
    }

    private var isTextEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // This DM's theme scope; a per-conversation override wins over the global default.
    private var themeScope: String { member.id.uuidString }
    private var chatTheme: ChatTheme {
        _ = themeRefresh
        // The @AppStorage globals establish observation so a live global
        // change re-renders; resolution itself is centralized in effective().
        _ = (chatThemeID, chatBubbleHex, chatBgID)
        return .effective(scope: themeScope)
    }
    private var draftKey: String { "draft.dm.\(member.id.uuidString)" }
    private var pendingOutbox: [PendingMessage] {
        outbox.pending
            .filter { $0.recipientName == member.name && $0.propertyId == propertyService.primary?.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// "online" / "last seen {relative}" under the partner's name, shown only
    /// when they're sharing presence.
    @ViewBuilder private var presenceSubtitle: some View {
        switch presenceService.status(for: member.name) {
        case .online:
            Text("online")
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.brandSuccess)
        case .lastSeen(let date):
            Text("last seen \(date, format: .relative(presentation: .named))")
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
        case .hidden:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            chatTheme.background
            messageList
        }
        // The compose bar lives in the safe-area inset — the canonical
        // iMessage structure. It can never be pushed off-screen by the
        // list's internal geometry (the empty-state GeometryReader used to
        // swallow it), and the scroll view gains the matching bottom inset
        // automatically.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ChatBlockStore.isBlocked(member.id.uuidString) {
                blockedBanner
            } else {
                inputBar
            }
        }
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
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        // The system search field replaces the old hand-built bar — instant,
        // with the native cancel flow.
        .searchable(text: $searchText, isPresented: $showSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search in conversation"))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showProfile = true } label: {
                    ChatHeaderPill {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(member.swiftColor.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Text(member.initials)
                                    .font(AppFont.scaled(12, weight: .bold))
                                    .foregroundStyle(member.swiftColor)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(member.name)
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(.primary)
                                // Transient typing status wins; otherwise show presence
                                // (online / last seen) when the partner shares it.
                                if directMessageService.typingNames.contains(member.name) {
                                    Text("typing…")
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    presenceSubtitle
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                ChatHeaderActions(
                    onVideo: { showVideoSheet = true },
                    onCall: { showCallSheet = true }
                )
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            ContactDetailsView(
                member: member,
                onAudio: { showCallSheet = true },
                onVideo: { showVideoSheet = true },
                onSearch: { showSearch = true },
                onStarred: { showStarred = true },
                onTheme: { showThemePicker = true },
                mediaURLs: sharedMediaURLs,
                exportText: exportTranscript,
                propertyId: propertyService.primary?.id
            )
        }
        .sheet(isPresented: $showCallSheet) {
            CallPickerSheet(members: [member], isVideo: false)
        }
        .sheet(isPresented: $showVideoSheet) {
            CallPickerSheet(members: [member], isVideo: true)
        }
        .sheet(item: $forwarding) { msg in
            ForwardPicker(members: familyService.members) { dest in
                Task { await forward(msg, to: dest) }
                forwarding = nil
            }
        }
        .sheet(isPresented: $showStarred) {
            DMStarredView(messages: markedMessages, partner: member) { id in
                showStarred = false
                scrollTarget = id
            }
        }
        .sheet(isPresented: $showThemePicker, onDismiss: { themeRefresh += 1 }) {
            ChatThemePicker(scope: themeScope)
        }
        .overlay(alignment: .bottomLeading) {
            if showAttachmentSheet {
                ChatAttachmentSheet(
                    isPresented: $showAttachmentSheet,
                onPhotos: { showPhotoPicker = true },
                onCamera: { showCameraPicker = true },
                onContact: { showContactPicker = true },
                onSendLater: { showSendLater = true }
            )
                .transition(.scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: showAttachmentSheet)
        .sheet(isPresented: $showSendLater) {
            if let uid = supabase.auth.currentSession?.user.id {
                SendLaterSheet(context: .dm(
                    propertyId: propertyService.primary?.id,
                    authorId: uid,
                    authorName: myName,
                    recipientName: member.name
                ))
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactMultiPicker(members: familyService.members) { payloads in
                Task { await sendDMContacts(payloads) }
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
        .task {
            guard let pid = propertyService.primary?.id else { return }
            directMessageService.myName = myName
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
        }
        .onAppear {
            themeRefresh &+= 1
            newestMessageId = conversationMessages.last?.id
            if !conversationMessages.isEmpty { startLoadGraceIfNeeded() }
            // Freeze the prior last-seen BEFORE markRead overwrites it, so the
            // divider marks where this session started — not messages that
            // arrive while we're reading.
            unreadSince = directMessageService.lastSeen(for: member.name)
            resolveUnreadDivider()
            directMessageService.markRead(partner: member.name)
            Task { await directMessageService.markReadRemote(partner: member.name, myName: myName) }
            Task { await flushOutbox() }
            if let pid = propertyService.primary?.id {
                Task { await presenceService.load(propertyId: pid) }
            }
            if input.isEmpty, let d = UserDefaults.standard.string(forKey: draftKey), !d.isEmpty { input = d }
        }
        .onDisappear {
            chatLoadGraceTask?.cancel()
            chatLoadGraceTask = nil
            jumpToggleTask?.cancel()
            jumpToggleTask = nil
            // Persist the unsent composer draft once, on the way out.
            if input.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
            else { UserDefaults.standard.set(input, forKey: draftKey) }
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
                if m.senderName == myName {
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
                        Task { await directMessageService.editMessage(id: m.id, newBody: newText) }
                    }
                }
                editingMessage = nil
            }
        }
    }

    private var displayedMessages: [DirectMessage] {
        let all = conversationMessages
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Searching scans the whole conversation; browsing renders only the
        // most-recent window so a long history doesn't build thousands of rows.
        guard !q.isEmpty else { return Array(all.suffix(visibleCount)) }
        return all.filter { $0.body.localizedCaseInsensitiveContains(q) }
    }

    /// Flash a message briefly after jumping to it from a reply.
    private func flashHighlight(_ id: UUID) {
        HapticFeedback.impact(.light)
        withAnimation(.easeInOut(duration: 0.25)) { highlightedId = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.4)) {
                if highlightedId == id { highlightedId = nil }
            }
        }
    }

    /// Resolve the unread-divider anchor exactly once, from the frozen
    /// last-seen date, as soon as the conversation has loaded.
    private func resolveUnreadDivider() {
        guard !unreadResolved, let since = unreadSince, !conversationMessages.isEmpty else { return }
        unreadDividerId = directMessageService.firstUnreadId(
            from: member.name, myName: myName, since: since)
        unreadResolved = true
    }

    /// Arms the entry grace window once. `chatDidLoad` may only flip after the
    /// server refresh has had time to land; flipping it on the first count
    /// change let the refresh batch animate — the visible settle on entry.
    private func startLoadGraceIfNeeded() {
        guard chatLoadGraceTask == nil else { return }
        chatLoadGraceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            chatDidLoad = true
        }
    }

    /// Debounced sentinel toggle: at the bottom rest the 1pt marker can flip
    /// in/out on sub-point settles, flickering the jump button and stealing
    /// its first tap. Only a state that survives 150ms is committed.
    private func setJumpToLatest(_ show: Bool) {
        jumpToggleTask?.cancel()
        guard show != showJumpToLatest else { return }
        jumpToggleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = show }
        }
    }

    /// True when older messages exist beyond the current render window —
    /// either already in memory or still on the server.
    private var hasMoreOlder: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (conversationMessages.count > visibleCount
                || (!conversationMessages.isEmpty
                    && !directMessageService.exhaustedOlder.contains(member.name)))
    }

    private var pinnedMessages: [DirectMessage] {
        conversationMessages.filter { $0.pinned == true && $0.deletedForAll != true }
    }
    private var markedMessages: [DirectMessage] {
        conversationMessages.filter { $0.isMarked == true && $0.deletedForAll != true }
    }

    private func dmSnippet(_ m: DirectMessage) -> String {
        if m.isContactShare { return "👤 Contact" }
        let lower = m.body.lowercased()
        if lower.contains("/dm-audio/") || lower.hasSuffix(".m4a") { return "🎤 Voice message" }
        if lower.contains("/dm-images/") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "📷 Photo" }
        return m.body
    }

    @ViewBuilder
    private func dmActionOverlay(_ m: DirectMessage) -> some View {
        let own = m.senderName == myName
        let lower = m.body.lowercased()
        let isImage = m.deletedForAll != true &&
            (lower.contains("/dm-images/") || lower.hasSuffix(".jpg") ||
             lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".webp"))
        ChatActionOverlay(
            previewText: m.deletedForAll == true ? "This message was deleted" : dmSnippet(m),
            isOwn: own,
            bubbleColor: chatTheme.id == "appDefault" ? Color.accentColor : chatTheme.outgoingBubble,
            myReaction: m.reactions?[myName],
            onReact: { e in Task { await directMessageService.toggleReaction(m, emoji: e, myName: myName) } },
            actions: dmMessageActions(m, own: own),
            onDismiss: { withAnimation(.easeOut(duration: 0.2)) { menuMessage = nil } },
            imageStored: isImage ? m.body : nil,
            reactionsDisabled: m.deletedForAll == true
        )
        .transition(.opacity)
    }

    private func dmMessageActions(_ m: DirectMessage, own: Bool) -> [ChatActionItem] {
        // Deleted messages keep only "Delete" (remove the tombstone for me).
        if m.deletedForAll == true {
            return [ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m }]
        }
        let lower = m.body.lowercased()
        let isMedia = lower.contains("/dm-images/") || lower.contains("/dm-audio/")
            || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".m4a")
        var items: [ChatActionItem] = [
            ChatActionItem("Reply", "arrowshape.turn.up.left") { withAnimation { replyingTo = m } },
            ChatActionItem("Forward", "arrowshape.turn.up.right") { forwarding = m },
            ChatActionItem("Copy", "doc.on.doc") { UIPasteboard.general.string = m.body },
            ChatActionItem(m.isMarked == true ? "Unmark" : "Mark", "flag") { Task { await directMessageService.toggleMark(m) } },
            ChatActionItem(m.pinned == true ? "Unpin" : "Pin", "pin") { Task { await directMessageService.togglePin(m) } }
        ]
        if own, m.deletedForAll != true, !isMedia {
            items.append(ChatActionItem("Edit", "pencil") { editingMessage = m; editText = m.body })
        }
        items.append(ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m })
        return items
    }

    // MARK: - Message List

    private var messageList: some View {
        VStack(spacing: 0) {
        if let pinned = pinnedMessages.last {
            Button {
                scrollTarget = pinned.id
                HapticFeedback.impact(.light)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pinnedMessages.count > 1
                             ? String(format: String(localized: "%d pinned messages"), pinnedMessages.count)
                             : String(localized: "Pinned message"))
                            .font(AppFont.label)
                            .foregroundStyle(Color.accentColor)
                        Text(dmSnippet(pinned))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { await directMessageService.togglePin(pinned) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Unpin message"))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, AppSpacing.md).padding(.top, AppSpacing.sm)
            }
            .buttonStyle(.plain)
        }
        ScrollViewReader { proxy in
            Group {
                if conversationMessages.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let shown = displayedMessages
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            if hasMoreOlder {
                                Button {
                                    // Anchor the current top message so inserting
                                    // an older page above it doesn't jump the view.
                                    let anchor = shown.first?.id
                                    let target = visibleCount + Self.pageSize
                                    if target > conversationMessages.count,
                                       let pid = propertyService.primary?.id {
                                        // The window outgrew memory — pull the
                                        // next older page from the server first.
                                        Task {
                                            await directMessageService.loadOlder(
                                                propertyId: pid, myName: myName, otherName: member.name)
                                            visibleCount = target
                                            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                        }
                                    } else {
                                        visibleCount = target
                                        if let anchor {
                                            DispatchQueue.main.async {
                                                proxy.scrollTo(anchor, anchor: .top)
                                            }
                                        }
                                    }
                                } label: {
                                    if directMessageService.isLoadingOlder {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text("Load older messages")
                                            .font(AppFont.scaled(13, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                } 
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.sm)
                                .disabled(directMessageService.isLoadingOlder)
                            }
                            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               shown.isEmpty {
                                EmptyStateView(icon: "magnifyingglass", title: "No results")
                                    .padding(.top, AppSpacing.xxl)
                            }
                            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, msg in
                                let isOwn = msg.senderName == myName
                                // While searching, `shown` is a sparse subset, so adjacency-based
                                // grouping is meaningless — show each result as a standalone bubble.
                                let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                // Tail on the last bubble of a same-sender run (or when the
                                // next message starts a new day) — matches the group chat.
                                let nextSameSender = !isSearching && idx < shown.count - 1
                                    && shown[idx + 1].senderName == msg.senderName
                                    && sameDay(msg, shown[idx + 1])
                                let showDate = idx == 0 || !sameDay(shown[idx - 1], msg)

                                if showDate {
                                    ChatDateSeparator(dateStr: msg.createdAt)
                                        .padding(.top, idx == 0 ? 8 : 16)
                                }
                                if !isSearching, msg.id == unreadDividerId {
                                    UnreadDivider().id("UNREAD_DIVIDER")
                                }

                                DMBubble(
                                    message: msg,
                                    isOwn: isOwn,
                                    hasTail: !nextSameSender,
                                    myName: myName,
                                    partner: member,
                                    members: familyService.members,
                                    myAvatarURL: profileService.profile?.avatarUrl.flatMap { URL(string: $0) },
                                    outgoingColor: chatTheme.id == "appDefault" ? nil : chatTheme.outgoingBubble,
                                    repliedMessage: msg.replyTo.flatMap { rid in
                                        conversationMessages.first { $0.id == rid }
                                    },
                                    onReact: { emoji in
                                        Task { await directMessageService.toggleReaction(msg, emoji: emoji, myName: myName) }
                                    },
                                    onReply: { withAnimation { replyingTo = msg } },
                                    onForward: { forwarding = msg },
                                    onEdit: isOwn ? { editingMessage = msg; editText = msg.body } : nil,
                                    onPin: { Task { await directMessageService.togglePin(msg) } },
                                    onMark: { Task { await directMessageService.toggleMark(msg) } },
                                    onDeleteForEveryone: { Task { await directMessageService.deleteForEveryone(id: msg.id) } },
                                    onDeleteForMe: { directMessageService.deleteForMe(id: msg.id) },
                                    onLongPress: { menuMessage = msg },
                                    onQuotedTap: {
                                        guard let rid = msg.replyTo,
                                              displayedMessages.contains(where: { $0.id == rid }) else { return }
                                        withAnimation { proxy.scrollTo(rid, anchor: .center) }
                                        flashHighlight(rid)
                                    },
                                    isHighlighted: highlightedId == msg.id
                                )
                                .id(msg.id)
                            }
                            ForEach(pendingOutbox) { pm in
                                let pendingFill = chatTheme.id == "appDefault" ? Color.accentColor : chatTheme.outgoingBubble
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack {
                                        Spacer(minLength: 72)
                                        HStack(spacing: 6) {
                                            Text(pm.body ?? "")
                                                .font(AppFont.scaled(15))
                                                .foregroundStyle(pendingFill.readableText)
                                            Image(systemName: outbox.isOnline ? "clock" : "exclamationmark.circle")
                                                .font(AppFont.scaled(10))
                                                .foregroundStyle(pendingFill.readableText.opacity(0.75))
                                        }
                                        .padding(.horizontal, 13).padding(.vertical, 9)
                                        .background(pendingFill,
                                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .opacity(0.85)
                                        .onTapGesture { Task { await flushOutbox() } }
                                        .contextMenu {
                                            Button { Task { await flushOutbox() } } label: {
                                                Label("Retry", systemImage: "arrow.clockwise")
                                            }
                                            Button(role: .destructive) { outbox.remove(pm.id) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                    if !outbox.isOnline {
                                        Text("Not delivered · tap to retry")
                                            .font(AppFont.scaled(10))
                                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                            .padding(.trailing, AppSpacing.xxs)
                                    }
                                }
                            }
                            // Jump-button sentinel. Visibility is driven by the
                            // marker entering/leaving the lazy render window —
                            // the old GeometryReader preference reset to 0 once
                            // the LazyVStack culled the off-screen marker, which
                            // hid the button exactly when it was needed. Toggles
                            // are debounced (setJumpToLatest): a 1pt zone flips
                            // on sub-point settles at rest otherwise.
                            Color.clear.frame(height: 1).id("DM_BOTTOM")
                                .onAppear { setJumpToLatest(false) }
                                .onDisappear { setJumpToLatest(true) }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.bottom, AppSpacing.md)
                        .animation(animateMessageDelta ? .spring(response: 0.35, dampingFraction: 0.86) : nil, value: conversationMessages.count)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: conversationMessages.count) { old, new in
                        guard new > 0 else { return }
                        // Decide the animation for THIS change — onChange runs
                        // ahead of the body pass that renders it. Spring only
                        // small deltas once entry has settled; bulk merges
                        // (server refresh, older pages) must land unanimated
                        // (a springing merge reads as the whole chat settling).
                        animateMessageDelta = chatDidLoad && abs(new - old) <= 3
                        startLoadGraceIfNeeded()
                        let newest = conversationMessages.last?.id
                        let appended = newest != newestMessageId
                        newestMessageId = newest
                        // Prepends (older pages) keep the reading position;
                        // only appends may move the viewport.
                        guard appended else { return }
                        let isOwnLatest = conversationMessages.last?.senderName == myName
                        if !chatDidLoad {
                            // Entry batches: snap straight to the bottom rest.
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                        } else if !showJumpToLatest || isOwnLatest {
                            // Follow new messages only when already at the
                            // bottom or when we sent it ourselves — never yank
                            // a reader up-thread.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                            }
                        } else {
                            // Reading up-thread: leave the viewport alone and
                            // don't mark the (unseen) message read.
                            return
                        }
                        directMessageService.markRead(partner: member.name)
                        Task { await directMessageService.markReadRemote(partner: member.name, myName: myName) }
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let t = target else { return }
                        withAnimation { proxy.scrollTo(t, anchor: .center) }
                        scrollTarget = nil
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showJumpToLatest {
                    Button {
                        // Idempotent: re-taps mid-flight are ignored instead of
                        // restarting the spring (each restart read as a nudge).
                        guard !isJumpingToLatest else { return }
                        isJumpingToLatest = true
                        HapticFeedback.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                        }
                        // LazyVStack estimates offsets for distant targets, so
                        // one animated pass can land short of the true bottom —
                        // which used to demand a second or third press. Once
                        // the spring settles, re-assert the anchor; a no-op if
                        // the first pass already landed.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.45))
                            if showJumpToLatest {
                                proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                            }
                            isJumpingToLatest = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Jump to latest message"))
                    .glassCircle()
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                    .padding(.trailing, AppSpacing.lg).padding(.bottom, 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(member.swiftColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Text(member.initials)
                    .font(AppFont.scaled(28, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
            Text(member.name)
                .font(AppFont.scaled(18, weight: .bold))
            Text("Start the private conversation")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var sharedMediaURLs: [URL] {
        conversationMessages.compactMap { m in
            let b = m.body.lowercased()
            guard b.contains("/dm-images/") || b.hasSuffix(".jpg") || b.hasSuffix(".jpeg") || b.hasSuffix(".png")
            else { return nil }
            return URL(string: m.body)
        }
    }

    private var exportTranscript: String {
        ChatExport.transcript(title: member.name, lines: conversationMessages.map {
            (sender: $0.senderName, time: $0.timeDisplay, body: $0.body)
        })
    }

    private var blockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").font(AppFont.scaled(13))
            Text("You blocked this contact.")
                .font(AppFont.scaled(14))
            Button("Unblock") {
                ChatBlockStore.setBlocked(member.id.uuidString, false)
                blockRefresh.toggle()
            }
            .font(AppFont.footnoteEmphasis)
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.base)
        .background(.regularMaterial)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if let replyingTo {
                replyPreviewBar(replyingTo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showAttachmentTray {
                dmAttachmentTray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // iMessage-style compose row: round + on the left, one slim pill
            // holding the field and the trailing control INSIDE it (mic when
            // empty, filled send arrow while typing). Camera lives in the +
            // tray, like iMessage. While recording, the whole row becomes the
            // iMessage recording pill; stop parks the clip for review.
            if audioRecorder.isRecording {
                VoiceRecordingPill(recorder: audioRecorder) {
                    audioRecorder.finishRecording()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 8)
            } else if let voicePreview = audioRecorder.preview {
                VoiceReviewRow(preview: voicePreview, isSending: isSending) {
                    audioRecorder.discardPreview()
                } onSend: {
                    if let clip = audioRecorder.takePreview() {
                        Task { await sendAudio(clip.url) }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 8)
            } else {
                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    plusButton

                    HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                        TextField("Message…", text: $input, axis: .vertical)
                            .font(AppFont.scaled(16))
                            .foregroundStyle(.primary)
                            .tint(.accentColor)
                            .lineLimit(1...6)
                            .focused($focused)
                            .padding(.vertical, 7)
                            .onChange(of: input) { _, val in
                                if !val.isEmpty, showAttachmentTray {
                                    withAnimation { showAttachmentTray = false }
                                }
                                let now = Date()
                                if !val.isEmpty, now.timeIntervalSince(lastTypingSent) > 2 {
                                    lastTypingSent = now
                                    directMessageService.sendTyping()
                                }
                                // Draft persistence happens on disappear — a
                                // per-keystroke UserDefaults write is typing lag.
                            }

                        if isTextEmpty {
                            micButton
                                .padding(.bottom, 3)
                        } else {
                            sendButton
                                .padding(.bottom, 3)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.7).combined(with: .opacity),
                                    removal: .scale(scale: 0.7).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.spring(duration: 0.2), value: isTextEmpty)
                    .padding(.leading, 14)
                    .padding(.trailing, 5)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 8)
                // iMessage has no separate band behind the compose row — the bar
                // sits directly on the conversation background, which the root
                // ZStack already draws full-screen. Re-rendering the theme here
                // painted photo wallpapers a second time (scaledToFill on a bar-
                // sized area spills the whole image across the screen).
            }
        }
        .animation(.spring(duration: 0.3), value: showAttachmentTray)
        .animation(.spring(duration: 0.3), value: replyingTo?.id)
        .animation(.snappy(duration: 0.25), value: audioRecorder.isRecording)
        .animation(.snappy(duration: 0.25), value: audioRecorder.preview)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems,
                      maxSelectionCount: 10, matching: .images)
        .onChange(of: photoPickerItems) { _, items in Task { await sendPhoto(items) } }
    }

    @ViewBuilder
    private func replyPreviewBar(_ msg: DirectMessage) -> some View {
        ChatReplyBanner(sender: msg.senderName, snippet: replyPreviewText(msg)) {
            withAnimation { replyingTo = nil }
        }
    }

    private func replyPreviewText(_ msg: DirectMessage) -> String {
        if msg.isContactShare { return "👤 Contact" }
        let lower = msg.body.lowercased()
        if lower.contains("/dm-audio/") || lower.hasSuffix(".m4a") { return "🎤 Voice message" }
        if lower.contains("/dm-images/") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "📷 Photo" }
        return msg.body
    }

    private var plusButton: some View {
        Button {
            focused = false
            showAttachmentSheet = true
        } label: {
            Image(systemName: "plus")
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                // Clear Liquid Glass on iOS 26; legible material fallback
                // earlier (a flat fill vanished against same-brightness
                // wallpapers).
                .mediaGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add attachment")
    }

    private var sendButton: some View {
        Button {
            Task { await sendMessage() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(AppFont.scaled(28))
                .foregroundStyle(.white, Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel(Text("Send"))
    }

    // iMessage-style: a plain dictation glyph inside the field, no chrome —
    // tap to start recording; the pill becomes the recording surface.
    private var micButton: some View {
        Button {
            focused = false
            audioRecorder.start()
            HapticFeedback.impact(.medium)
        } label: {
            Image(systemName: "mic.fill")
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Record voice message"))
    }

    private var dmAttachmentTray: some View {
        HStack(spacing: 28) {
            DMAttachmentOption(icon: "photo.on.rectangle.angled", label: "Gallery", color: .purple) {
                withAnimation { showAttachmentTray = false }
                showPhotoPicker = true
            }
            DMAttachmentOption(icon: "camera.fill", label: "Camera", color: .blue) {
                withAnimation { showAttachmentTray = false }
                showCameraPicker = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.vertical, AppSpacing.lg)
        .background(.regularMaterial)
    }

    // MARK: - Send

    @MainActor
    private func sendMessage() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        isSending = true
        defer { isSending = false }

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

        let replyUUID = replyingTo?.id
        let replyId = replyUUID?.uuidString
        // Optimistic append: the bubble shows the instant you hit send; the
        // client-generated id lets the server row replace it cleanly on ack
        // (the realtime reload dedups on the same id).
        let clientId = UUID()
        let optimistic = DirectMessage(
            id: clientId, senderName: myName, recipientName: member.name,
            body: text, createdAt: ISO8601DateFormatter().string(from: Date()),
            replyTo: replyUUID,
            senderId: supabase.auth.currentSession?.user.id,
            recipientMemberId: member.id,
            expiresAt: dmExpiresAt
        )
        directMessageService.dms.append(optimistic)
        withAnimation { replyingTo = nil }
        HapticFeedback.impact(.light)
        MessageSounds.sent()
        do {
            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(Payload(id: clientId.uuidString,
                                sender_name: myName, recipient_name: member.name,
                                body: text, property_id: propertyService.primary?.id.uuidString,
                                reply_to: replyId,
                                sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                recipient_member_id: member.id.uuidString,
                                expires_at: dmExpiresAt))
                .select()
                .single()
                .execute()
                .value
            if let i = directMessageService.dms.firstIndex(where: { $0.id == sent.id }) {
                directMessageService.dms[i] = sent
            } else {
                directMessageService.dms.append(sent)
            }
        } catch {
            directMessageService.dms.removeAll { $0.id == clientId }
            // Offline / send failed → queue it; sends automatically when back online.
            if let pid = propertyService.primary?.id {
                outbox.enqueue(PendingMessage(
                    propertyId: pid, senderName: myName, recipientName: member.name,
                    recipientMemberId: member.id,
                    body: text, replyTo: replyUUID
                ))
            }
            HapticFeedback.warning()
        }
    }

    private func flushOutbox() async {
        guard let pid = propertyService.primary?.id else { return }
        await outbox.flush { pm in
            guard pm.propertyId == pid, let recipient = pm.recipientName else { return false }
            struct P: Encodable {
                let sender_name, recipient_name, body, property_id: String
                let reply_to: String?
                let sender_id, recipient_member_id, expires_at: String?
            }
            let obTtl = ChatDisappearStore.ttl(recipient)
            let obExpires = obTtl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(obTtl)) : nil
            do {
                let sent: DirectMessage = try await supabase
                    .from("direct_messages")
                    .insert(P(sender_name: pm.senderName, recipient_name: recipient,
                              body: pm.body ?? "", property_id: pid.uuidString,
                              reply_to: pm.replyTo?.uuidString,
                              sender_id: supabase.auth.currentSession?.user.id.uuidString,
                              recipient_member_id: pm.recipientMemberId?.uuidString,
                              expires_at: obExpires))
                    .select().single().execute().value
                directMessageService.dms.append(sent)
                return true
            } catch {
                return false
            }
        }
    }

    @MainActor
    private func forward(_ message: DirectMessage, to dest: ForwardDestination) async {
        guard let propId = propertyService.primary?.id else { return }
        let lower = message.body.lowercased()
        let isImage = lower.contains("/dm-images/") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
        let isAudio = lower.contains("/dm-audio/") || lower.hasSuffix(".m4a")

        do {
            switch dest {
            case .group:
                if isImage {
                    try await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                                  attachmentUrl: message.body, attachmentType: "image")
                } else if isAudio {
                    try await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                                  attachmentUrl: message.body, attachmentType: "audio")
                } else {
                    try await messageService.send(propertyId: propId, senderName: myName, body: message.body)
                }
            case .member(let m):
                struct Payload: Encodable {
                    let sender_name, recipient_name, body, property_id: String
                    let sender_id, recipient_member_id, expires_at: String?
                }
                let fwdTtl = ChatDisappearStore.ttl(m.name)
                let fwdExpires = fwdTtl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(fwdTtl)) : nil
                let sent: DirectMessage = try await supabase
                    .from("direct_messages")
                    .insert(Payload(sender_name: myName, recipient_name: m.name,
                                    body: message.body, property_id: propId.uuidString,
                                    sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                    recipient_member_id: m.id.uuidString,
                                    expires_at: fwdExpires))
                    .select().single().execute().value
                directMessageService.dms.append(sent)
            }
            HapticFeedback.success()
        } catch {
            sendError = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    @MainActor
    private func sendDMContacts(_ payloads: [SharedContactPayload]) async {
        guard !payloads.isEmpty,
              let body = SharedContactPayload.encodeDM(payloads) else { return }
        await sendDMContact(body)
    }

    private func sendDMContact(_ formatted: String) async {
        guard let pid = propertyService.primary?.id else { return }
        MessageSounds.sent()
        struct Payload: Encodable {
            let sender_name, recipient_name, body, property_id: String
            let sender_id, recipient_member_id, expires_at: String?
        }
        do {
            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(Payload(sender_name: myName, recipient_name: member.name,
                                body: formatted.hasPrefix(SharedContactPayload.dmMarker)
                                    ? formatted : "👤 \(formatted)",
                                property_id: pid.uuidString,
                                sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                recipient_member_id: member.id.uuidString,
                                expires_at: dmExpiresAt))
                .select().single().execute().value
            directMessageService.dms.append(sent)
            HapticFeedback.success()
        } catch {
            sendError = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    @MainActor
    private func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        photoPickerItems = []
        // Send each selected image as its own message (preserves order).
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            await uploadAndSendImage(data: data)
        }
    }

    @MainActor
    private func sendCameraImage(_ image: UIImage) async {
        guard let data = image.uploadJPEG(quality: 0.85, maxDimension: 2048) else { return }
        await uploadAndSendImage(data: data)
    }

    @MainActor
    private func uploadAndSendImage(data: Data) async {
        guard let propId = propertyService.primary?.id else { return }
        MessageSounds.sent()

        do {
            // Private bucket + signed URL at display (via ChatMedia / DMImageBubble).
            guard let path = await ChatMedia.upload(data, propertyId: propId, subdir: "dm",
                                                    ext: "jpg", contentType: "image/jpeg") else { return }

            struct PhotoPayload: Encodable {
                let sender_name, recipient_name, body, property_id: String
                let sender_id, recipient_member_id, expires_at: String?
            }

            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(PhotoPayload(sender_name: myName, recipient_name: member.name,
                                     body: path, property_id: propId.uuidString,
                                     sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                     recipient_member_id: member.id.uuidString,
                                     expires_at: dmExpiresAt))
                .select()
                .single()
                .execute()
                .value
            directMessageService.dms.append(sent)
            HapticFeedback.impact(.light)
        } catch {
#if DEBUG
            debugLog("[DM] image error: \(error)")
#endif
        }
    }

    @MainActor
    private func sendAudio(_ fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL),
              let propId = propertyService.primary?.id else { return }
        MessageSounds.sent()

        do {
            // Private bucket + signed URL at playback (via ChatMedia / AudioBubble).
            guard let path = await ChatMedia.upload(data, propertyId: propId, subdir: "dm-audio",
                                                    ext: "m4a", contentType: "audio/mp4") else { return }

            struct AudioPayload: Encodable {
                let sender_name, recipient_name, body, property_id: String
                let sender_id, recipient_member_id, expires_at: String?
            }

            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(AudioPayload(sender_name: myName, recipient_name: member.name,
                                     body: path, property_id: propId.uuidString,
                                     sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                     recipient_member_id: member.id.uuidString,
                                     expires_at: dmExpiresAt))
                .select()
                .single()
                .execute()
                .value
            directMessageService.dms.append(sent)
            HapticFeedback.impact(.light)
        } catch {
#if DEBUG
            debugLog("[DM] audio error: \(error)")
#endif
        }
    }

    // MARK: - Helpers

    private func sameDay(_ a: DirectMessage, _ b: DirectMessage) -> Bool {
        guard let da = a.date, let db = b.date else { return false }
        return Calendar.current.isDate(da, inSameDayAs: db)
    }
}

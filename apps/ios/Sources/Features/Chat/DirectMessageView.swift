import SwiftUI
import PhotosUI
import UIKit
import Supabase

private struct DMBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

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
    @AppStorage("prvio.chatTheme") private var chatThemeID: String = "appDefault"
    @AppStorage("prvio.chatBubbleHex") private var chatBubbleHex = ""
    @AppStorage("prvio.chatBgID") private var chatBgID = ""
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
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    @State private var showProfile = false
    @State private var sendError: String? = nil
    @FocusState private var focused: Bool
    @State private var isSending = false
    @State private var lastTypingSent = Date.distantPast
    @State private var audioRecorder = ChatAudioRecorder()
    @State private var outbox = OfflineOutbox(filename: "chat_outbox_dm.json")
    @State private var recordingCancelled = false
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
        return ChatDisappearStore.filter(kept, convId: member.id.uuidString) { $0.date }
    }

    private var isTextEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var chatTheme: ChatTheme { .resolved(themeID: chatThemeID, bubbleHex: chatBubbleHex, bgID: chatBgID) }
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
                .font(.system(size: 11))
                .foregroundStyle(Color.brandSuccess)
        case .lastSeen(let date):
            Text("last seen \(date, format: .relative(presentation: .named))")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
        case .hidden:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            chatTheme.background
            VStack(spacing: 0) {
                messageList
                if ChatBlockStore.isBlocked(member.id.uuidString) {
                    blockedBanner
                } else {
                    inputBar
                }
            }
        }
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
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showProfile = true } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(member.swiftColor.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Text(member.initials)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(member.swiftColor)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.name)
                                .font(AppFont.headline)
                                .foregroundStyle(.primary)
                            // Transient typing status wins; otherwise show presence
                            // (online / last seen) when the partner shares it.
                            if directMessageService.typingNames.contains(member.name) {
                                Text("typing…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                presenceSubtitle
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showVideoSheet = true } label: {
                    Image(systemName: "video.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Video call")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCallSheet = true } label: {
                    Image(systemName: "phone.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call")
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            ContactDetailsView(
                member: member,
                onAudio: { showCallSheet = true },
                onVideo: { showVideoSheet = true },
                onSearch: { withAnimation { showSearch = true } },
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
        .sheet(isPresented: $showThemePicker) {
            ChatThemePicker()
        }
        .sheet(isPresented: $showAttachmentSheet) {
            ChatAttachmentSheet(
                onPhotos: { showPhotoPicker = true },
                onCamera: { showCameraPicker = true },
                onContact: { showContactPicker = true }
            )
        }
        .sheet(isPresented: $showContactPicker) {
            ChatContactPicker { formatted in Task { await sendDMContact(formatted) } }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            DMCameraPickerView(isPresented: $showCameraPicker) { img in
                Task { @MainActor in await sendCameraImage(img) }
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .onAppear {
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
        .onChange(of: conversationMessages.count) { _, _ in
            // The parent loads messages asynchronously, so they may arrive after
            // onAppear; resolve the divider on the first non-empty state, once.
            resolveUnreadDivider()
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

    /// True when older messages exist beyond the current render window.
    private var hasMoreOlder: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && conversationMessages.count > visibleCount
    }

    private var pinnedMessages: [DirectMessage] {
        conversationMessages.filter { $0.pinned == true && $0.deletedForAll != true }
    }
    private var markedMessages: [DirectMessage] {
        conversationMessages.filter { $0.isMarked == true && $0.deletedForAll != true }
    }

    private func dmSnippet(_ m: DirectMessage) -> String {
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
            imageStored: isImage ? m.body : nil
        )
        .transition(.opacity)
    }

    private func dmMessageActions(_ m: DirectMessage, own: Bool) -> [ChatActionItem] {
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Search in conversation", text: $searchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, 9)
        .liquidGlass(cornerRadius: 18)
        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Message List

    private var messageList: some View {
        VStack(spacing: 0) {
        if showSearch { searchBar }
        if let pinned = pinnedMessages.last {
            Button {
                scrollTarget = pinned.id
                HapticFeedback.impact(.light)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pinnedMessages.count > 1
                             ? String(format: String(localized: "%d pinned messages"), pinnedMessages.count)
                             : String(localized: "Pinned message"))
                            .font(AppFont.label)
                            .foregroundStyle(Color.accentColor)
                        Text(dmSnippet(pinned))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { await directMessageService.togglePin(pinned) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, AppSpacing.md).padding(.top, AppSpacing.sm)
            }
            .buttonStyle(.plain)
        }
        GeometryReader { outer in
        ScrollViewReader { proxy in
            Group {
                if conversationMessages.isEmpty {
                    emptyState
                } else {
                    let shown = displayedMessages
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            if hasMoreOlder {
                                Button {
                                    // Anchor the current top message so inserting
                                    // an older page above it doesn't jump the view.
                                    let anchor = shown.first?.id
                                    visibleCount += Self.pageSize
                                    if let anchor {
                                        DispatchQueue.main.async {
                                            proxy.scrollTo(anchor, anchor: .top)
                                        }
                                    }
                                } label: {
                                    Text("Load older messages")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.sm)
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
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack {
                                        Spacer(minLength: 72)
                                        HStack(spacing: 6) {
                                            Text(pm.body ?? "")
                                                .font(.system(size: 15))
                                                .foregroundStyle(.white)
                                            Image(systemName: outbox.isOnline ? "clock" : "exclamationmark.circle")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.75))
                                        }
                                        .padding(.horizontal, 13).padding(.vertical, 9)
                                        .background(chatTheme.id == "appDefault" ? Color.accentColor : chatTheme.outgoingBubble,
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
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                            .padding(.trailing, AppSpacing.xxs)
                                    }
                                }
                            }
                            Color.clear.frame(height: 1).id("DM_BOTTOM")
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: DMBottomKey.self,
                                                           value: g.frame(in: .named("DMOUTER")).maxY)
                                })
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.bottom, AppSpacing.md)
                        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: conversationMessages.count)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onPreferenceChange(DMBottomKey.self) { maxY in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showJumpToLatest = maxY > outer.size.height + 60
                        }
                    }
                    .onChange(of: conversationMessages.count) { _, _ in
                        let isOwnLatest = conversationMessages.last?.senderName == myName
                        // Only auto-scroll & mark read when the user is already at the
                        // bottom, or when the new message is one we just sent ourselves.
                        guard !showJumpToLatest || isOwnLatest else { return }
                        if let last = conversationMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        directMessageService.markRead(partner: member.name)
                        Task { await directMessageService.markReadRemote(partner: member.name, myName: myName) }
                    }
                    .onAppear {
                        if let last = conversationMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                        }
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                    .padding(.trailing, AppSpacing.lg).padding(.bottom, 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        }
        .coordinateSpace(name: "DMOUTER")
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
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
            Text(member.name)
                .font(.system(size: 18, weight: .bold))
            Text("Începe conversația privată")
                .font(.system(size: 14))
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
            Image(systemName: "hand.raised.fill").font(.system(size: 13))
            Text("You blocked this contact.")
                .font(.system(size: 14))
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

            HStack(alignment: .bottom, spacing: 10) {
                plusButton

                // Text field and recording indicator share the same slot.
                // The text field stays in the hierarchy (preserves keyboard/focus)
                // and is hidden behind the recording bar when active.
                ZStack(alignment: .leading) {
                    TextField("Message…", text: $input, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(1...6)
                        .focused($focused)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 9)
                        .liquidGlass(cornerRadius: AppRadius.xl)
                        .opacity(audioRecorder.isRecording ? 0 : 1)
                        .allowsHitTesting(!audioRecorder.isRecording)
                        .onChange(of: input) { _, val in
                            if !val.isEmpty, showAttachmentTray {
                                withAnimation { showAttachmentTray = false }
                            }
                            let now = Date()
                            if !val.isEmpty, now.timeIntervalSince(lastTypingSent) > 2 {
                                lastTypingSent = now
                                directMessageService.sendTyping()
                            }
                            if val.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
                            else { UserDefaults.standard.set(val, forKey: draftKey) }
                        }

                    if audioRecorder.isRecording {
                        recordingIndicator
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }

                // Right side — mic is ALWAYS present last to keep view identity
                // stable so the drag gesture is never interrupted mid-recording.
                HStack(spacing: 6) {
                    if !audioRecorder.isRecording {
                        if isTextEmpty {
                            cameraButton
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.7).combined(with: .opacity),
                                    removal: .scale(scale: 0.7).combined(with: .opacity)
                                ))
                        } else {
                            sendButton
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.7).combined(with: .opacity),
                                    removal: .scale(scale: 0.7).combined(with: .opacity)
                                ))
                        }
                    }
                    micButton
                }
                .animation(.spring(duration: 0.2), value: isTextEmpty)
                .animation(.spring(duration: 0.2), value: audioRecorder.isRecording)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .animation(.spring(duration: 0.3), value: showAttachmentTray)
        .animation(.spring(duration: 0.3), value: replyingTo?.id)
        .animation(.spring(duration: 0.2), value: audioRecorder.isRecording)
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
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(AppOpacity.subtleFill))
                    .frame(width: 34, height: 34)
                Image(systemName: "plus")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
        }
        .buttonStyle(.plain)
    }

    private var recordingIndicator: some View {
        ChatRecordingIndicator(durationText: audioRecorder.durationText)
    }

    private var cameraButton: some View {
        Button {
            withAnimation { showAttachmentTray = false }
            showCameraPicker = true
        } label: {
            Image(systemName: "camera.fill")
                .font(AppFont.subheadline)
                .foregroundStyle(Color.primary.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var sendButton: some View {
        Button {
            Task { await sendMessage() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 34, height: 34)
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }

    // Mic button is always the rightmost element — never removed from hierarchy
    // so the LongPress+Drag gesture chain is never interrupted by re-renders.
    private var micButton: some View {
        ZStack {
            Circle()
                .fill(audioRecorder.isRecording ? Color.red.opacity(0.12) : Color.primary.opacity(AppOpacity.subtleFill))
                .frame(width: 34, height: 34)
            Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                .font(AppFont.subheadline)
                .foregroundStyle(audioRecorder.isRecording ? .red : Color.primary.opacity(0.55))
                .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    guard !audioRecorder.isRecording else { return }
                    recordingCancelled = false
                    focused = false
                    audioRecorder.start()
                    HapticFeedback.impact(.medium)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    guard audioRecorder.isRecording, !recordingCancelled else { return }
                    if val.translation.width < -60 {
                        recordingCancelled = true
                        _ = audioRecorder.stop()
                        HapticFeedback.warning()
                    }
                }
                .onEnded { _ in
                    guard audioRecorder.isRecording, !recordingCancelled else {
                        recordingCancelled = false
                        return
                    }
                    if let url = audioRecorder.stop() {
                        Task { await sendAudio(url) }
                    }
                }
        )
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
            let sender_name: String
            let recipient_name: String
            let body: String
            let property_id: String?
            let reply_to: String?
            let sender_id: String?
            let recipient_member_id: String?
            let expires_at: String?
        }

        let replyId = replyingTo?.id.uuidString
        do {
            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(Payload(sender_name: myName, recipient_name: member.name,
                                body: text, property_id: propertyService.primary?.id.uuidString,
                                reply_to: replyId,
                                sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                recipient_member_id: member.id.uuidString,
                                expires_at: dmExpiresAt))
                .select()
                .single()
                .execute()
                .value
            directMessageService.dms.append(sent)
            withAnimation { replyingTo = nil }
            HapticFeedback.impact(.light)
        } catch {
            // Offline / send failed → queue it; sends automatically when back online.
            if let pid = propertyService.primary?.id {
                outbox.enqueue(PendingMessage(
                    propertyId: pid, senderName: myName, recipientName: member.name,
                    body: text, replyTo: replyingTo?.id
                ))
            }
            withAnimation { replyingTo = nil }
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
                let sender_id, expires_at: String?
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

        switch dest {
        case .group:
            if isImage {
                try? await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                               attachmentUrl: message.body, attachmentType: "image")
            } else if isAudio {
                try? await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                               attachmentUrl: message.body, attachmentType: "audio")
            } else {
                try? await messageService.send(propertyId: propId, senderName: myName, body: message.body)
            }
        case .member(let m):
            struct Payload: Encodable {
                let sender_name, recipient_name, body, property_id: String
                let sender_id, recipient_member_id, expires_at: String?
            }
            let fwdTtl = ChatDisappearStore.ttl(m.name)
            let fwdExpires = fwdTtl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(fwdTtl)) : nil
            if let sent: DirectMessage = try? await supabase
                .from("direct_messages")
                .insert(Payload(sender_name: myName, recipient_name: m.name,
                                body: message.body, property_id: propId.uuidString,
                                sender_id: supabase.auth.currentSession?.user.id.uuidString,
                                recipient_member_id: m.id.uuidString,
                                expires_at: fwdExpires))
                .select().single().execute().value {
                directMessageService.dms.append(sent)
            }
        }
        HapticFeedback.success()
    }

    @MainActor
    private func sendDMContact(_ formatted: String) async {
        guard let pid = propertyService.primary?.id else { return }
        struct Payload: Encodable {
            let sender_name, recipient_name, body, property_id: String
            let sender_id, recipient_member_id, expires_at: String?
        }
        if let sent: DirectMessage = try? await supabase
            .from("direct_messages")
            .insert(Payload(sender_name: myName, recipient_name: member.name,
                            body: "👤 \(formatted)", property_id: pid.uuidString,
                            sender_id: supabase.auth.currentSession?.user.id.uuidString,
                            recipient_member_id: member.id.uuidString,
                            expires_at: dmExpiresAt))
            .select().single().execute().value {
            directMessageService.dms.append(sent)
            HapticFeedback.success()
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
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        await uploadAndSendImage(data: data)
    }

    @MainActor
    private func uploadAndSendImage(data: Data) async {
        guard let propId = propertyService.primary?.id else { return }

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
            print("[DM] image error: \(error)")
#endif
        }
    }

    @MainActor
    private func sendAudio(_ fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL),
              let propId = propertyService.primary?.id else { return }

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
            print("[DM] audio error: \(error)")
#endif
        }
    }

    // MARK: - Helpers

    private func sameDay(_ a: DirectMessage, _ b: DirectMessage) -> Bool {
        guard let da = a.date, let db = b.date else { return false }
        return Calendar.current.isDate(da, inSameDayAs: db)
    }
}

// MARK: - Camera Picker (UIKit bridge)

private struct DMCameraPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: DMCameraPickerView
        init(_ parent: DMCameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            DispatchQueue.main.async {
                if let img { self.parent.onCapture(img) }
                self.parent.isPresented = false
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async { self.parent.isPresented = false }
        }
    }
}

// MARK: - Attachment Option

private struct DMAttachmentOption: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 58, height: 58)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DM Bubble

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    /// Draw the iMessage-style tail — true on the last bubble of a same-sender run.
    let hasTail: Bool
    var myName: String = ""
    var partner: FamilyMember? = nil
    var myAvatarURL: URL? = nil
    var outgoingColor: Color? = nil
    var repliedMessage: DirectMessage? = nil
    var onReact: ((String) -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil
    var onMark: (() -> Void)? = nil
    var onDeleteForEveryone: (() -> Void)? = nil
    var onDeleteForMe: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    /// Tapping the quoted reply jumps to the original message.
    var onQuotedTap: (() -> Void)? = nil
    /// Briefly tinted when the reader jumped here from a reply.
    var isHighlighted: Bool = false

    @State private var swipeOffset: CGFloat = 0
    @State private var showDetails = false
    @State private var viewerItem: ImageViewerItem? = nil

    private static let reactionEmojis = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

    private var reactionCounts: [String: Int] {
        var out: [String: Int] = [:]
        for (_, emoji) in message.reactions ?? [:] { out[emoji, default: 0] += 1 }
        return out
    }

    /// Speech-bubble background; tail only on the last bubble of a run.
    private var bubbleShape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }
    private var myReaction: String? { message.reactions?[myName] }

    private var showsQuickForward: Bool {
        guard onForward != nil, messageType == .text else { return false }
        // Quick-forward button only on link messages.
        return firstDetectedURL(in: message.body) != nil
    }

    private var forwardButton: some View {
        Button { onForward?() } label: {
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.6))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel("Forward")
    }

    private enum DMMessageType { case text, image, audio, deleted }

    private var messageType: DMMessageType {
        if message.deletedForAll == true { return .deleted }
        let lower = message.body.lowercased()
        if lower.hasSuffix(".m4a") || lower.contains("/dm-audio/") { return .audio }
        if lower.contains("supabase") &&
           (lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") ||
            lower.hasSuffix(".png") || lower.hasSuffix(".webp") ||
            lower.contains("/dm-images/")) { return .image }
        return .text
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isOwn {
                Spacer(minLength: 72)
                if showsQuickForward { forwardButton }
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if let replied = repliedMessage, messageType != .deleted {
                    quotedReply(replied)
                        .contentShape(Rectangle())
                        .onTapGesture { onQuotedTap?() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Jump to the replied message")
                }

                Group {
                    switch messageType {
                    case .deleted: deletedBubble
                    case .audio:
                        AudioBubble(
                            audioValue: message.body, isOwn: isOwn,
                            avatarURL: isOwn ? myAvatarURL : partner?.avatarUrl.flatMap { URL(string: $0) },
                            initials: isOwn
                                ? String(myName.prefix(2)).uppercased()
                                : (partner?.initials ?? String(message.senderName.prefix(2)).uppercased()),
                            avatarColor: isOwn ? Color.accentColor : (partner?.swiftColor ?? Color.gray),
                            timeText: message.timeDisplay,
                            tick: isOwn ? (message.readAt != nil ? .read
                                           : (message.deliveredAt != nil ? .delivered : .sent)) : .none,
                            bubbleColor: outgoingColor ?? Color.accentColor,
                            hasTail: hasTail
                        )
                    case .image: imageBubble
                    case .text:  textBubble
                    }
                }
                // Brief accent wash when the reader jumped here from a reply.
                .overlay {
                    if isHighlighted {
                        bubbleShape.fill(Color.accentColor.opacity(0.28))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isHighlighted)
                // Reactions float over the bubble's bottom-sender corner; bottom
                // padding reserves the overhang so the timestamp row clears it.
                .overlay(alignment: isOwn ? .bottomTrailing : .bottomLeading) {
                    if !reactionCounts.isEmpty, messageType != .deleted {
                        reactionPills.offset(x: isOwn ? -6 : 6, y: 12)
                    }
                }
                .padding(.bottom, (!reactionCounts.isEmpty && messageType != .deleted) ? 14 : 0)
                .offset(x: swipeOffset)
                .overlay(alignment: isOwn ? .trailing : .leading) {
                    if abs(swipeOffset) > 12 {
                        Image(systemName: swipeOffset > 0 ? "arrowshape.turn.up.left.fill" : "info.circle.fill")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .offset(x: swipeOffset > 0 ? -28 : 28)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.22) {
                    HapticFeedback.impact(.medium)
                    onLongPress?()
                }

                if messageType == .text, let link = firstDetectedURL(in: message.body) {
                    LinkPreviewView(url: link)
                }

                // Audio bubbles render their own time + ticks inside.
                if messageType != .audio { statusRow }
            }

            if !isOwn {
                if showsQuickForward { forwardButton }
                Spacer(minLength: 72)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .simultaneousGesture(swipeGesture)
        .sheet(isPresented: $showDetails) {
            DMMessageDetailsView(message: message, isOwn: isOwn)
        }
        .fullScreenCover(item: $viewerItem) { item in
            FullScreenImageViewer(url: item.url)
        }
    }

    private var swipeGesture: some Gesture {
        // Only a decisively horizontal drag engages reply/details; vertical
        // travel is left to the scroll view so scrolling on a bubble works.
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                guard messageType != .deleted else { return }
                guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                let w = v.translation.width
                swipeOffset = max(-90, min(90, w > 0 ? w - 24 : w + 24))
            }
            .onEnded { v in
                guard messageType != .deleted else { return }
                let horizontal = abs(v.translation.width) > abs(v.translation.height) * 2
                if horizontal, v.translation.width > 72 { onReply?(); HapticFeedback.impact(.light) }
                else if horizontal, v.translation.width < -90 { showDetails = true; HapticFeedback.impact(.light) }
                withAnimation(.spring(response: 0.3)) { swipeOffset = 0 }
            }
    }

    @ViewBuilder
    private var menuContent: some View {
        if messageType != .deleted {
            if let onReact {
                ForEach(Self.reactionEmojis, id: \.self) { emoji in
                    Button { onReact(emoji) } label: { Text(emoji) }
                }
                Divider()
            }
            if let onReply {
                Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            }
            if let onForward {
                Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            }
            if messageType == .text {
                Button { UIPasteboard.general.string = message.body } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if let onEdit {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                }
            }
            Button { showDetails = true } label: { Label("Details", systemImage: "info.circle") }
            if let onMark {
                Button { onMark() } label: {
                    Label(message.isMarked == true ? "Unmark" : "Mark", systemImage: "flag")
                }
            }
            if let onPin {
                Button { onPin() } label: {
                    Label(message.pinned == true ? "Unpin" : "Pin", systemImage: "pin")
                }
            }
            Divider()
        }
        if isOwn, let onDeleteForEveryone, messageType != .deleted {
            Button(role: .destructive) { onDeleteForEveryone() } label: {
                Label("Delete for everyone", systemImage: "trash")
            }
        }
        if let onDeleteForMe {
            Button(role: .destructive) { onDeleteForMe() } label: {
                Label("Delete for me", systemImage: "trash.slash")
            }
        }
    }

    /// Floating reaction cluster that straddles the bubble's bottom edge (see
    /// the overlay in `body`) — matches the group chat's placement.
    private var reactionPills: some View {
        HStack(spacing: 3) {
            ForEach(Array(reactionCounts.sorted(by: { $0.key < $1.key })), id: \.key) { emoji, count in
                Button {
                    onReact?(emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(.system(size: 13))
                        if count > 1 {
                            Text("\(count)").font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(myReaction == emoji ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(format: String(localized: "Reaction %@"), emoji)))
                .accessibilityValue(count > 1 ? Text("\(count)") : Text(""))
                .accessibilityAddTraits(myReaction == emoji ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            Text(message.timeDisplay)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            if message.editedAt != nil, messageType != .deleted {
                Text("· edited")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            if message.pinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            if message.isMarked == true {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange.opacity(0.7))
            }
            if isOwn, messageType != .deleted {
                MessageTick(status: message.readAt != nil ? .read
                                    : (message.deliveredAt != nil ? .delivered : .sent))
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func quotedReply(_ replied: DirectMessage) -> some View {
        let preview: String = {
            let lower = replied.body.lowercased()
            if replied.deletedForAll == true { return "This message was deleted" }
            if lower.contains("/dm-audio/") || lower.hasSuffix(".m4a") { return "🎤 Voice message" }
            if lower.contains("/dm-images/") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "📷 Photo" }
            return replied.body
        }()
        let accent = outgoingColor ?? Color.accentColor
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(replied.senderName)
                    .font(AppFont.label)
                    .foregroundStyle(accent)
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 5)
        .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .frame(maxWidth: 240, alignment: .leading)
    }

    private var deletedBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "slash.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.4))
            Text("This message was deleted")
                .font(.system(size: 14))
                .italic()
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(Color.primary.opacity(AppOpacity.hairline), in: bubbleShape)
    }

    private var textBubble: some View {
        Text(message.body)
            .font(.system(size: 15))
            .foregroundStyle(isOwn ? .white : .primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                isOwn ? (outgoingColor ?? Color.accentColor) : Color.primary.opacity(0.09),
                in: bubbleShape
            )
            .clipShape(bubbleShape)
    }

    private var imageBubble: some View {
        DMImageBubble(stored: message.body, isOwn: isOwn, hasTail: hasTail) { u in viewerItem = ImageViewerItem(url: u) }
    }
}

// MARK: - DM image bubble (resolves private signed URLs; legacy URLs pass through)

private struct DMImageBubble: View {
    let stored: String
    var isOwn: Bool = false
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?

    private var shape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 180)
                    .clipShape(shape)
                    .onTapGesture { if let url { onTap(url) } }
            case .failure:
                shape
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 220, height: 140)
                    .overlay(Image(systemName: "photo").foregroundStyle(Color.primary.opacity(0.3)))
            default:
                shape
                    .fill(Color.primary.opacity(AppOpacity.hairline))
                    .frame(width: 220, height: 140)
                    .overlay(ProgressView())
            }
        }
        .task(id: stored) { url = await ChatMedia.resolve(stored) }
    }
}

// (DM read-receipt tick now uses the shared MessageTick from ChatComponents.)

// MARK: - DM Starred (marked) messages

private struct DMStarredView: View {
    let messages: [DirectMessage]
    let partner: FamilyMember
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private func snippet(_ m: DirectMessage) -> String {
        let lower = m.body.lowercased()
        if lower.contains("/dm-audio/") || lower.hasSuffix(".m4a") { return "🎤 Voice message" }
        if lower.contains("/dm-images/") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "📷 Photo" }
        return m.body
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if messages.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "flag.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.primary.opacity(0.18))
                        Text("No starred messages")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Mark a message to find it here later.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { msg in
                                Button {
                                    onSelect(msg.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(msg.senderName)
                                                .font(AppFont.captionEmphasis)
                                                .foregroundStyle(.primary)
                                            Text(snippet(msg))
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                                .lineLimit(2)
                                            Text(msg.timeDisplay)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(AppFont.captionStrong)
                                            .foregroundStyle(Color.primary.opacity(0.25))
                                    }
                                    .padding(AppSpacing.base)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppSpacing.lg)
                    }
                }
            }
            .navigationTitle("Starred messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

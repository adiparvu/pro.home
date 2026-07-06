import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import UserNotifications
import UniformTypeIdentifiers
import Supabase

private let kAvatarRingColorKey = "prvio.avatarRingColorName"


struct ChatView: View {
    @Environment(MessageService.self) var messageService
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ProfileService.self) private var profileService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(StickerService.self) private var stickerService
    @Environment(PresenceService.self) private var presenceService
    @Environment(AppRouter.self) private var router
    @State var text = ""
    @State var photoPickerItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showJumpToLatest = false
    /// First unread message on open — anchors the "unread messages" divider.
    /// Frozen for the lifetime of this view so it doesn't chase read receipts.
    @State private var unreadDividerId: UUID? = nil
    @State private var showStarred = false
    @State private var showGroupInfo = false
    @State private var showAddMember = false
    @State private var scrollTarget: UUID? = nil
    @State private var highlightedMessageId: UUID? = nil
    @State private var menuMessage: Message?
    @State private var deleteCandidate: Message?
    @State private var editingMessage: Message? = nil
    @State private var editText = ""
    @State private var lastTypingSent = Date.distantPast
    @State var replyingTo: Message?
    @State private var forwardingMessage: Message?
    @State private var showLocationSheet = false
    @State private var showMentionPicker = false
    @State private var showCameraSheet = false
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    @State private var showStickerPicker = false
    @State private var showAttachmentSheet = false
    @State private var showContactPicker = false
    @State private var showPollComposer = false
    @State private var showEventComposer = false
    @State private var showSendLater = false
    @State var mentionedIds: [String] = []
    @State var mentionedNames: [String] = []
    @State var isSending = false
    @State private var showPhotoPickerTrigger = false
    @State private var showFileImporter = false
    @State var sendError: String? = nil
    @FocusState private var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    // Global defaults from Chat Settings (kept for live reactivity to global changes).
    @AppStorage("prvio.chatTheme") private var chatThemeID: String = "appDefault"
    @AppStorage("prvio.chatBubbleHex") private var chatBubbleHex = ""
    @AppStorage("prvio.chatBgID") private var chatBgID = ""
    @State private var showThemePicker = false
    @State private var themeRefresh = 0
    /// False until the first batch of messages lands — the initial fill must
    /// not animate (bubbles springing into place read as an entry flash).
    @State private var chatDidLoad = false
    @State private var audioRecorder = ChatAudioRecorder()
    @State var outbox = OfflineOutbox()

    // The group conversation's theme scope; overrides live under prvio.chatTheme.<scope>.
    private var themeScope: String { "group" }

    // Per-conversation override wins; otherwise the global default is used.
    private var chatTheme: ChatTheme {
        _ = themeRefresh
        // The @AppStorage globals establish observation so a live global
        // change re-renders; resolution itself is centralized in effective().
        _ = (chatThemeID, chatBubbleHex, chatBgID)
        return .effective(scope: themeScope)
    }
    private var pendingOutbox: [PendingMessage] {
        guard let pid = propertyId else { return [] }
        return outbox.pending(for: pid)
    }

    var propertyId: UUID? { propertyService.primary?.id }

    private var draftKey: String { "draft.group.\(propertyId?.uuidString ?? "none")" }

    private func sameDay(_ a: Message, _ b: Message) -> Bool {
        let dA = a.date ?? Date()
        let dB = b.date ?? Date()
        return Calendar.current.isDate(dA, inSameDayAs: dB)
    }

    /// Scroll to a message (e.g. from tapping a reply's quote) and flash it. No-op
    /// if it isn't in the loaded window — older pages aren't force-loaded here.
    private func jumpToMessage(_ id: UUID) {
        guard filteredMessages.contains(where: { $0.id == id }) else { return }
        scrollTarget = id
        HapticFeedback.impact(.light)
        withAnimation(.easeInOut(duration: 0.25)) { highlightedMessageId = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.4)) {
                if highlightedMessageId == id { highlightedMessageId = nil }
            }
        }
    }

    /// Messages after the "clear conversation" cutoff and disappearing-message
    /// rules, before any search filter. Shared by the list, pins and counts so
    /// none of them show messages the user has cleared or that have expired.
    private var visibleMessages: [Message] {
        let kept = ConversationClearStore.filter(messageService.messages, convId: "group") { $0.date }
        return ChatDisappearStore.filter(kept, convId: "group") { $0.date }
    }
    private var filteredMessages: [Message] {
        guard showSearch && !searchText.isEmpty else { return visibleMessages }
        return visibleMessages.filter {
            ($0.body ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    private var typingText: String? {
        let names = messageService.typingNames.sorted()
        guard let first = names.first else { return nil }
        if names.count == 1 { return String(format: String(localized: "%@ is typing…"), first) }
        return String(format: String(localized: "%d people are typing…"), names.count)
    }
    /// Family members (other than me) currently online, for the header subtitle.
    private var onlineText: String? {
        let me = senderName
        let online = familyService.members
            .map(\.name)
            .filter { $0 != me && presenceService.status(for: $0) == .online }
            .sorted()
        guard let first = online.first else { return nil }
        if online.count == 1 { return String(format: String(localized: "%@ is online"), first) }
        if online.count == 2 { return String(format: String(localized: "%@ and %@ online"), first, online[1]) }
        return String(format: String(localized: "%d online"), online.count)
    }
    private var sharedMediaURLs: [URL] {
        messageService.messages.compactMap { m in
            guard m.isImageMessage, let s = m.attachmentUrl else { return nil }
            return URL(string: s)
        }
    }
    private var exportTranscript: String {
        ChatExport.transcript(title: "Group", lines: messageService.messages.map {
            (sender: $0.senderName, time: $0.timeDisplay, body: $0.body ?? "")
        })
    }
    private var pinnedMessages: [Message] { visibleMessages.filter { $0.pinned == true && $0.deletedForAll != true } }
    private var markedMessages: [Message] { messageService.messages.filter { $0.isMarked == true } }

    @ViewBuilder
    private func actionOverlay(_ m: Message) -> some View {
        let own = m.senderId == supabase.auth.currentSession?.user.id
        ChatActionOverlay(
            previewText: m.deletedForAll == true ? String(localized: "This message was deleted") : pinnedSnippet(m),
            isOwn: own,
            bubbleColor: chatTheme.id == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble,
            myReaction: messageService.reactions[m.id]?.first(where: { $0.userId == supabase.auth.currentSession?.user.id })?.emoji,
            onReact: { e in
                if let pid = propertyId {
                    Task { await messageService.toggleReaction(messageId: m.id, propertyId: pid, emoji: e, reactorName: senderName) }
                }
            },
            actions: messageActions(m),
            onDismiss: { withAnimation(.easeOut(duration: 0.2)) { menuMessage = nil } },
            imageStored: m.isImageMessage ? m.attachmentUrl : nil,
            reactionsDisabled: m.deletedForAll == true
        )
        .transition(.opacity)
    }

    private func messageActions(_ m: Message) -> [ChatActionItem] {
        // A deleted message is just a tombstone: the only thing left to do
        // with it is remove it from your own view.
        if m.deletedForAll == true {
            return [ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m }]
        }
        let own = m.senderId == supabase.auth.currentSession?.user.id
        var items: [ChatActionItem] = [
            ChatActionItem("Reply", "arrowshape.turn.up.left") { withAnimation(.spring(response: 0.3)) { replyingTo = m } },
            ChatActionItem("Forward", "arrowshape.turn.up.right") { forwardingMessage = m },
            ChatActionItem("Copy", "doc.on.doc") { if let b = m.body { UIPasteboard.general.string = b } },
            ChatActionItem(m.isMarked == true ? "Unmark" : "Mark", "flag") { Task { await messageService.toggleMark(m) } },
            ChatActionItem(m.pinned == true ? "Unpin" : "Pin", "pin") { Task { await messageService.togglePin(m) } }
        ]
        if own, m.body?.isEmpty == false, m.attachmentType == nil {
            items.append(ChatActionItem("Edit", "pencil") {
                editingMessage = m; editText = m.body ?? ""
                replyingTo = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true }
            })
        }
        items.append(ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m })
        return items
    }

    private func pinnedSnippet(_ m: Message) -> String {
        // Structured types first, so a poll/event never shows its JSON body.
        if m.isPollMessage { return "📊 Poll" }
        if m.isEventMessage { return "📅 Event" }
        if m.isImageMessage { return "📷 Photo" }
        if m.isVideoMessage { return "🎥 Video" }
        if m.isAudioMessage { return "🎤 Voice message" }
        if m.isLocationMessage { return "📍 Location" }
        if m.isFileMessage { return "📎 File" }
        if m.isStickerMessage { return "😀 Sticker" }
        if let b = m.body, !b.isEmpty { return b }
        return String(localized: "Attachment")
    }
    var senderName: String {
        profileService.profile?.preferredName
            ?? profileService.profile?.fullName
            ?? "Me"
    }
    private var ownerInitial: String {
        String((profileService.profile?.preferredName ?? senderName).prefix(1)).uppercased()
    }

    var body: some View {
        messageList
            .overlay(alignment: .bottom) { inputBar }
            .background(chatTheme.background)
            // iMessage-style header: no bar, the conversation slides under a
            // progressive blur and only glass controls float on top.
            .overlay(alignment: .top) { ChatTopBlur() }
            .overlay {
                if messageService.isLoading && messageService.messages.isEmpty {
                    MessageSkeleton()
                }
            }
            .overlay {
                if let m = menuMessage { actionOverlay(m) }
            }
        .sheet(item: $forwardingMessage) { msg in
            ForwardPicker(members: familyService.members) { dest in
                Task { await forward(msg, to: dest) }
                forwardingMessage = nil
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // The system search field (pull-down / magnifier-presented) replaces
        // the old hand-built bar — instant, with the native cancel flow.
        .searchable(text: $searchText, isPresented: $showSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search messages…"))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatHeaderPill {
                    HStack(spacing: 8) {
                        GroupHeaderAvatar(
                            members: familyService.members,
                            photoUrl: propertyService.primary?.photoUrl,
                            ownerAvatarUrl: profileService.profile?.avatarUrl,
                            ownerInitial: ownerInitial,
                            ringColor: avatarRingColor(for: avatarRingColorName)
                        ) {
                            showGroupInfo = true
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            // The group chat has its own name (chat_group_settings),
                            // independent of the property name.
                            Text(propertyService.groupChatDisplayName)
                                .font(AppFont.subheadline)
                            // Transient typing status wins; otherwise show who's online.
                            if let t = typingText {
                                Text(t)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                            } else if let o = onlineText {
                                Text(o)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.brandSuccess)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { showGroupInfo = true }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                ChatHeaderActions(
                    onVideo: { showVideoSheet = true },
                    onCall: { showCallSheet = true }
                )
            }
        }
        .task {
            guard let pid = propertyId else { return }
            // Freeze where the reader left off BEFORE marking anything read, so
            // the "unread messages" divider lands at the first new message.
            let seen = messageService.lastSeen(propertyId: pid)
            await propertyService.loadGroupChatName()
            await messageService.load(propertyId: pid)
            unreadDividerId = messageService.firstUnreadId(
                since: seen, myId: supabase.auth.currentSession?.user.id)
            messageService.resetUnread()
            await presenceService.load(propertyId: pid)
            await messageService.loadReads(propertyId: pid)
            await messageService.loadDeliveries(propertyId: pid)
            await messageService.loadReactions(propertyId: pid)
            await messageService.markDelivered(propertyId: pid, delivererName: senderName)
            await messageService.markRead(propertyId: pid, readerName: senderName)
        }
        .task {
            guard let pid = propertyId else { return }
            messageService.myName = senderName
            await messageService.subscribeRealtime(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReads(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeDeliveries(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReactions(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.loadPollVotes(propertyId: pid)
            await messageService.subscribePollVotes(propertyId: pid)
        }
        .task {
            // Keep live-location bubbles following the sharer while the
            // conversation is open.
            guard let pid = propertyId else { return }
            while !Task.isCancelled {
                await LiveLocationService.shared.load(propertyId: pid)
                try? await Task.sleep(nanoseconds: 7_000_000_000)
            }
        }
        .task { await flushOutbox() }
        .task { await MemberDirectory.shared.loadIfNeeded() }
        .onChange(of: outbox.isOnline) { _, online in
            if online { Task { await flushOutbox() } }
        }
        .onAppear {
            themeRefresh &+= 1
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = true }
            if text.isEmpty, let d = UserDefaults.standard.string(forKey: draftKey), !d.isEmpty { text = d }
        }
        .onDisappear {
            // Persist the unsent composer draft once, on the way out.
            if text.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
            else { UserDefaults.standard.set(text, forKey: draftKey) }
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = false }
            // Remember we've now seen everything, so the next open computes the
            // unread divider from this point forward.
            if let pid = propertyId { messageService.markSeen(propertyId: pid) }
            // The main messages channel is owned by the chat tab (ConversationsView)
            // so the conversation list keeps its preview + unread badge live; only
            // the per-message receipt channels are thread-scoped, so tear those down.
            Task {
                await messageService.unsubscribeReads()
                await messageService.unsubscribeDeliveries()
                await messageService.unsubscribeReactions()
                await messageService.unsubscribePollVotes()
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue.hasSuffix("@") && !showMentionPicker {
                text = String(newValue.dropLast())
                showMentionPicker = true
            }
            let now = Date()
            if !newValue.isEmpty, now.timeIntervalSince(lastTypingSent) > 2 {
                lastTypingSent = now
                messageService.sendTyping()
            }
            // Draft persistence happens on disappear — a UserDefaults write on
            // every keystroke is measurable typing lag.
        }
        .photosPicker(isPresented: $showPhotoPickerTrigger, selection: $photoPickerItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .onChange(of: photoPickerItems) { _, items in Task { await sendPhoto(items) } }
        .sheet(isPresented: $showLocationSheet) {
            LocationShareSheet(propertyId: propertyId, myName: senderName) { lat, lon in
                Task { await sendLocation(lat: lat, lon: lon) }
            }
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPickerSheet(selectedIds: $mentionedIds, selectedNames: $mentionedNames)
        }
        .sheet(isPresented: $showCallSheet) {
            CallPickerSheet(members: familyService.members, isVideo: false)
        }
        .sheet(isPresented: $showVideoSheet) {
            CallPickerSheet(members: familyService.members, isVideo: true)
        }
        .sheet(isPresented: $showStickerPicker) {
            StickerPicker(onSelect: { sticker in
                Task { await sendSticker(sticker) }
            }, onMemoji: { image in
                Task { await sendCameraPhoto(image) }
            })
            .environment(stickerService)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showStarred) {
            StarredMessagesView(messages: markedMessages, members: familyService.members) { id in
                showStarred = false
                scrollTarget = id
            }
        }
        .sheet(isPresented: $showThemePicker, onDismiss: { themeRefresh += 1 }) {
            ChatThemePicker(scope: themeScope)
        }
        .navigationDestination(isPresented: $showGroupInfo) {
            GroupDetailsView(
                groupName: propertyService.groupChatDisplayName,
                members: familyService.members,
                photoUrl: propertyService.primary?.photoUrl,
                onAudio: { showCallSheet = true },
                onVideo: { showVideoSheet = true },
                onAddMember: { showAddMember = true },
                onSearch: { showSearch = true },
                onStarred: { showStarred = true },
                onTheme: { showThemePicker = true },
                mediaURLs: sharedMediaURLs,
                inviteLink: "https://prvhouse.app/invite/\(propertyId?.uuidString ?? "")",
                propertyId: propertyId,
                exportText: exportTranscript
            )
            .environment(propertyService)
        }
        .sheet(isPresented: $showAddMember) {
            AddFamilyMemberSheet(propertyId: propertyId, propertyName: propertyService.primary?.name)
                .environment(familyService)
        }
        .overlay(alignment: .bottomLeading) {
            if showAttachmentSheet {
                ChatAttachmentSheet(
                    isPresented: $showAttachmentSheet,
                onPhotos: { showPhotoPickerTrigger = true },
                onCamera: { showCameraSheet = true },
                onLocation: { showLocationSheet = true },
                onDocument: { showFileImporter = true },
                onContact: { showContactPicker = true },
                onPoll: { showPollComposer = true },
                onEvent: { showEventComposer = true },
                onSendLater: { showSendLater = true },
                onStickers: { showStickerPicker = true }
            )
                .transition(.scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: showAttachmentSheet)
        .sheet(isPresented: $showSendLater) {
            if let pid = propertyId, let uid = supabase.auth.currentSession?.user.id {
                SendLaterSheet(context: .group(propertyId: pid, authorId: uid, authorName: senderName))
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactMultiPicker(members: familyService.members) { payloads in
                Task { await sendContacts(payloads) }
            }
        }
        .sheet(isPresented: $showPollComposer) {
            PollComposerView { question, options, multi in
                Task { await sendPoll(question: question, options: options, multipleChoice: multi) }
            }
        }
        .sheet(isPresented: $showEventComposer) {
            EventComposerView { title, details, date, location in
                Task { await sendEvent(title: title, details: details, date: date, location: location) }
            }
        }
        .confirmationDialog("Delete message?", isPresented: .init(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            if let m = deleteCandidate {
                if m.senderId == supabase.auth.currentSession?.user.id {
                    Button("Delete for everyone", role: .destructive) {
                        HapticFeedback.warning()
                        Task { await messageService.deleteForEveryone(id: m.id) }
                        deleteCandidate = nil
                    }
                }
                Button("Delete for me", role: .destructive) {
                    HapticFeedback.warning()
                    messageService.deleteForMe(id: m.id)
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            }
        }
        .fullScreenCover(isPresented: $showCameraSheet) {
            CameraPickerView { image in
                Task { await sendCameraPhoto(image) }
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await sendFile(url: url) }
            }
        }
        .alert("Message Not Sent", isPresented: .init(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .userActivity("com.prvio.chat") { activity in
            activity.title = String(localized: "Chat — PRVIO")
            activity.userInfo = ["tab": "chat"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
        }
    }

    // MARK: - Message list

    private let chatBottomInset: CGFloat = 78

    private var messageList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if let pinned = pinnedMessages.last {
                    Button {
                        withAnimation { proxy.scrollTo(pinned.id, anchor: .center) }
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
                                Text(pinnedSnippet(pinned))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Task { await messageService.togglePin(pinned) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Unpin message")
                        }
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, AppSpacing.lg).padding(.top, AppSpacing.sm)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

            // Capture the list ONCE per render. `filteredMessages` is a computed
            // property that re-runs two filter passes on every access; the rows
            // below read neighbours (idx±1), which made scrolling O(n²). The
            // reply lookup gets the same treatment (dictionary instead of a
            // linear scan per bubble).
            let msgs = filteredMessages
            let messagesById = Dictionary(messageService.messages.map { ($0.id, $0) },
                                          uniquingKeysWith: { a, _ in a })
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if messageService.hasMoreOlder && (!showSearch || searchText.isEmpty) {
                        Button {
                            if let pid = propertyId { Task { await messageService.loadOlder(propertyId: pid) } }
                        } label: {
                            if messageService.isLoadingOlder {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Load older messages")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .disabled(messageService.isLoadingOlder)
                    }
                    if showSearch && !searchText.isEmpty && msgs.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                            .padding(.top, AppSpacing.xxl)
                    }
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { idx, msg in
                        let showDate = idx == 0 || !sameDay(msgs[idx - 1], msg)
                        // Consecutive messages from the same sender on the same day form a
                        // visual group: only the first shows the name, only the last the
                        // avatar. Searching yields a sparse subset, so grouping is disabled.
                        let grouping = !(showSearch && !searchText.isEmpty)
                        let prevSameSender = grouping && !showDate && idx > 0
                            && msgs[idx - 1].senderName == msg.senderName
                        let nextSameSender = grouping && idx < msgs.count - 1
                            && sameDay(msg, msgs[idx + 1])
                            && msgs[idx + 1].senderName == msg.senderName
                        if showDate {
                            ChatDateSeparator(dateStr: msg.createdAt)
                        }
                        if grouping, msg.id == unreadDividerId {
                            UnreadDivider().id("UNREAD_DIVIDER")
                        }
                        MessageBubble(
                            message: msg,
                            isOwn: msg.senderId == supabase.auth.currentSession?.user.id,
                            members: familyService.members,
                            outgoingColor: chatTheme.id == "appDefault" ? nil : chatTheme.outgoingBubble,
                            readers: messageService.reads[msg.id] ?? [],
                            deliverers: messageService.deliveries[msg.id] ?? [],
                            persistedReactions: {
                                let rows = messageService.reactions[msg.id] ?? []
                                return Dictionary(rows.map { ($0.emoji, 1) }, uniquingKeysWith: +)
                            }(),
                            persistedMyReaction: messageService.reactions[msg.id]?
                                .first(where: { $0.userId == supabase.auth.currentSession?.user.id })?.emoji,
                            onReact: { emoji in
                                guard let pid = propertyId else { return }
                                Task { await messageService.toggleReaction(
                                    messageId: msg.id, propertyId: pid,
                                    emoji: emoji, reactorName: senderName) }
                            },
                            repliedMessage: msg.replyTo.flatMap { messagesById[$0] },
                            onReply: { withAnimation(.spring(response: 0.3)) { replyingTo = msg } },
                            onPin: { Task { await messageService.togglePin(msg) } },
                            onMark: { Task { await messageService.toggleMark(msg) } },
                            onForward: { forwardingMessage = msg },
                            onEdit: {
                                editingMessage = msg; editText = msg.body ?? ""
                                replyingTo = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true }
                            },
                            onDeleteForEveryone: { Task { await messageService.deleteForEveryone(id: msg.id) } },
                            onDeleteForMe: { messageService.deleteForMe(id: msg.id) },
                            pollVotes: messageService.pollVotes[msg.id] ?? [],
                            myUserId: supabase.auth.currentSession?.user.id,
                            myAvatarURL: profileService.profile?.avatarUrl.flatMap { URL(string: $0) },
                            onPollVote: { idx in
                                guard let pid = propertyId, let poll = ChatPoll.decode(msg.body) else { return }
                                Task { await messageService.togglePollVote(
                                    messageId: msg.id, propertyId: pid,
                                    optionIndex: idx, voterName: senderName, multi: poll.multi) }
                            },
                            onLongPress: { menuMessage = msg },
                            isGroupStart: !prevSameSender,
                            isGroupEnd: !nextSameSender,
                            onQuotedTap: { if let rid = msg.replyTo { jumpToMessage(rid) } },
                            isHighlighted: highlightedMessageId == msg.id
                        )
                        .padding(.top, prevSameSender ? 0 : (showDate ? 0 : 6))
                        .id(msg.id)
                    }
                    // Pending (offline) messages — shown optimistically with a clock.
                    ForEach(pendingOutbox) { pm in
                        let pendingFill = chatTheme.id == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack {
                                Spacer(minLength: 60)
                                HStack(spacing: 6) {
                                    Text(pm.body ?? "")
                                        .font(.system(size: 15))
                                        .foregroundStyle(pendingFill.readableText)
                                    Image(systemName: outbox.isOnline ? "clock" : "exclamationmark.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(pendingFill.readableText.opacity(0.75))
                                }
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
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
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                    .padding(.trailing, AppSpacing.xxs)
                            }
                        }
                    }
                    // Clearance so the newest message rests above the overlaid
                    // input bar (which blurs the messages behind it = real glass).
                    Color.clear.frame(height: chatBottomInset)
                    // Jump-button sentinel: visibility follows the marker
                    // entering/leaving the lazy render window. The previous
                    // GeometryReader preference reset to 0 whenever the
                    // LazyVStack culled the off-screen marker, hiding the
                    // button on any deep scroll-back.
                    Color.clear.frame(height: 1).id("CHAT_BOTTOM")
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = false }
                        }
                        .onDisappear {
                            withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = true }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .animation(chatDidLoad ? .spring(response: 0.35, dampingFraction: 0.86) : nil, value: msgs.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messageService.messages.count) { old, new in
                guard !messageService.messages.isEmpty else { return }
                defer { chatDidLoad = true }
                if old == 0 {
                    proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                } else {
                    withAnimation { proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom) }
                }
                if let pid = propertyId {
                    Task {
                        await messageService.markDelivered(propertyId: pid, delivererName: senderName)
                        await messageService.markRead(propertyId: pid, readerName: senderName)
                    }
                }
            }
            .onAppear {
                // defaultScrollAnchor(.bottom) already rests on the newest
                // message from the first frame — a delayed corrective jump here
                // read as an entry flash. Only the unread divider needs one.
                if unreadDividerId != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("UNREAD_DIVIDER", anchor: .top)
                    }
                }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let t = target else { return }
                withAnimation { proxy.scrollTo(t, anchor: .center) }
                scrollTarget = nil
            }
            } // end VStack (search + scroll)
            .overlay(alignment: .bottom) {
                if showJumpToLatest {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
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
                    .padding(.bottom, chatBottomInset + 8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Jump to latest message")
                }
            }
        } // end ScrollViewReader
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if editingMessage != nil {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Edit message")
                            .font(AppFont.label).foregroundStyle(Color.accentColor)
                        Text(editingMessage?.body ?? "")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        withAnimation { editingMessage = nil; editText = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.4))
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Cancel edit")
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                .background(Color.primary.opacity(0.05))
            }
            if let replyingTo {
                ChatReplyBanner(sender: replyingTo.senderName, snippet: pinnedSnippet(replyingTo)) {
                    withAnimation { self.replyingTo = nil }
                }
            }
            if !mentionedNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(zip(mentionedIds, mentionedNames)), id: \.0) { id, name in
                            HStack(spacing: 4) {
                                Text("@\(name)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.accentColor)
                                Button {
                                    mentionedIds.removeAll { $0 == id }
                                    mentionedNames.removeAll { $0 == name }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                }
                                .accessibilityLabel("Remove mention of \(name)")
                            }
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xxs)
                            .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.xs)
                }
            }

            if audioRecorder.isRecording {
                // Recording bar replaces input
                HStack(spacing: 10) {
                    Button {
                        _ = audioRecorder.stop()
                        HapticFeedback.warning()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel recording")

                    ChatRecordingIndicator(durationText: audioRecorder.durationText)
                        .gesture(
                            DragGesture(minimumDistance: 40)
                                .onEnded { val in
                                    if val.translation.width < -40 {
                                        _ = audioRecorder.stop()
                                        HapticFeedback.warning()
                                    }
                                }
                        )

                    Button {
                        if let url = audioRecorder.stop() {
                            Task { await sendAudio(url: url) }
                        }
                    } label: {
                        ZStack {
                            Circle().fill(Color.accentColor).frame(width: 34, height: 34)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Send"))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xs)
            } else {
                // iMessage-style compose row: a round + button on the left and a
                // slim pill field with the trailing control INSIDE it — the
                // dictation-style mic when empty, the filled send arrow while
                // typing (stickers moved into the + sheet).
                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    Button {
                        focused = false
                        showAttachmentSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            // Clear Liquid Glass on iOS 26; legible material
                            // fallback earlier (a flat fill vanished against
                            // same-brightness wallpapers).
                            .mediaGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add attachment")

                    HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                        TextField("Message…", text: editingMessage != nil ? $editText : $text, axis: .vertical)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .tint(.accentColor)
                            .lineLimit(1...6)
                            .focused($focused)
                            .padding(.vertical, 7)

                        if editingMessage != nil {
                            Button {
                                guard let m = editingMessage else { return }
                                let newText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !newText.isEmpty, newText != (m.body ?? "") {
                                    Task { await messageService.editMessage(id: m.id, newBody: newText) }
                                }
                                editingMessage = nil; editText = ""; focused = false
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 4)
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Confirm edit")
                        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Dictation-style mic (iMessage) — hold to record
                            Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(audioRecorder.isRecording ? Color.red : Color.primary.opacity(AppOpacity.disabled))
                                .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                                .frame(width: 28, height: 28)
                                .padding(.bottom, 4)
                                .onLongPressGesture(minimumDuration: 0.3) {
                                    guard !audioRecorder.isRecording else { return }
                                    audioRecorder.start()
                                    HapticFeedback.impact(.medium)
                                }
                                .accessibilityLabel("Record voice message")
                                .accessibilityHint("Double-tap and hold to record")
                                .accessibilityAddTraits(.isButton)
                        } else {
                            Button {
                                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                Task { await sendText() }
                            } label: {
                                if isSending {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Color.accentColor))
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white, Color.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 4)
                            .disabled(isSending)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Send")
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 5)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
                .animation(.snappy(duration: 0.2), value: text.isEmpty)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xs)
            }
        }
    }
}

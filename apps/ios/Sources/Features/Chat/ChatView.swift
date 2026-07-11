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
    @Environment(FamilyService.self) var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ProfileService.self) var profileService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(PresenceService.self) private var presenceService
    @Environment(NotificationService.self) private var notificationService
    @Environment(AppRouter.self) private var router
    @State var text = ""
    /// The composer's optional subject line (iMessage's "Show Subject Field").
    /// Encoded into the body at send time (see MessageSubject), so the send
    /// pipeline, outbox and realtime stay untouched.
    @State var subject = ""
    /// Chat Settings → "Show Subject Field". OFF by default; gates the row in
    /// the composer for the family chat and every community group.
    @AppStorage(MessageSubject.showFieldDefaultsKey) var showSubjectField = false
    @State var photoPickerItems: [PhotosPickerItem] = []
    @State var searchText = ""
    @State var showSearch = false
    @State var showJumpToLatest = false
    /// Whether the reader is at (or within a bubble of) the bottom — the gate
    /// for auto-following incoming messages and for honest read receipts.
    /// Driven by live scroll geometry on iOS 18+ (see ChatAtBottomModifier);
    /// the bottom sentinel keeps it updated on older systems.
    @State var isAtBottom = true
    /// First unread message on open — anchors the "unread messages" divider.
    /// Frozen for the lifetime of this view so it doesn't chase read receipts.
    @State var unreadDividerId: UUID? = nil
    @State private var showStarred = false
    @State private var showGroupInfo = false
    @State private var showAddMember = false
    @State var scrollTarget: UUID? = nil
    @State var highlightedMessageId: UUID? = nil
    @State var menuMessage: Message?
    @State var deleteCandidate: Message?
    @State var editingMessage: Message? = nil
    @State var editText = ""
    @State var replyingTo: Message?
    @State var forwardingMessage: Message?
    @State private var showLocationSheet = false
    @State private var showMentionPicker = false
    @State private var showCameraSheet = false
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    @State var showAttachmentSheet = false
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
    @FocusState var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    // Global defaults from Chat Settings (kept for live reactivity to global changes).
    @AppStorage("prvio.chatTheme") private var chatThemeID: String = "appDefault"
    @AppStorage("prvio.chatBubbleHex") private var chatBubbleHex = ""
    @AppStorage("prvio.chatBgID") private var chatBgID = ""
    @State private var themeRefresh = 0
    /// False until entry settles. Messages arrive in two batches — the page
    /// already in memory from ConversationsView, then the network refresh that
    /// replaces it — and BOTH must land unanimated, so this flips only after a
    /// short grace window, not on the first count change.
    @State var chatDidLoad = false
    /// Grace timer that flips `chatDidLoad`; started once the list is non-empty.
    @State var chatLoadGraceTask: Task<Void, Never>? = nil
    /// Per-change animation gate, decided in `onChange` (which runs ahead of
    /// the body pass that renders the change): spring only for small deltas
    /// (send/receive), never for bulk merges (refresh, older-page loads).
    @State var animateMessageDelta = false
    /// Newest rendered message id — distinguishes appends (auto-scroll) from
    /// prepends like "load older" (keep the reading position).
    @State var newestMessageId: UUID? = nil
    /// Guards the jump-to-latest button against rapid re-taps mid-flight.
    @State var isJumpingToLatest = false
    /// Scope-keyed offline queue — assigned in init so each conversation
    /// (main chat / each community group) persists to its own file.
    @State var outbox: OfflineOutbox

    // Optional community group scope. When nil, this is the main property chat
    // and every behaviour below is byte-for-byte identical to before; when set,
    // the same rich chat is scoped to a single community group (loading, drafts,
    // theme, title and the settings gear all key off `groupId`).
    var groupId: UUID? = nil
    var groupTitle: String? = nil
    var groupSettingsAction: (() -> Void)? = nil

    /// Explicit init so the offline outbox can key its persistence FILE by the
    /// conversation scope. All group scopes used to share one chat_outbox.json,
    /// so a failed community-group message rendered in — and re-sent into —
    /// whichever conversation flushed first.
    init(groupId: UUID? = nil, groupTitle: String? = nil,
         groupSettingsAction: (() -> Void)? = nil) {
        self.groupId = groupId
        self.groupTitle = groupTitle
        self.groupSettingsAction = groupSettingsAction
        _outbox = State(initialValue: OfflineOutbox(
            filename: groupId.map { "chat_outbox_group_\($0.uuidString).json" } ?? "chat_outbox.json"))
    }

    // The conversation's theme scope; overrides live under prvio.chatTheme.<scope>.
    // Each community group gets its own scope so its theme never collides with
    // the main chat's "group" scope.
    private var themeScope: String { groupId.map { "group.\($0.uuidString)" } ?? "group" }

    // Per-conversation override wins; otherwise the global default is used.
    var chatTheme: ChatTheme {
        _ = themeRefresh
        // The @AppStorage globals establish observation so a live global
        // change re-renders; resolution itself is centralized in effective().
        _ = (chatThemeID, chatBubbleHex, chatBgID)
        return .effective(scope: themeScope)
    }
    var pendingOutbox: [PendingMessage] {
        guard let pid = propertyId else { return [] }
        return outbox.pending(for: pid, groupId: groupId)
    }

    var propertyId: UUID? { propertyService.primary?.id }

    private var draftKey: String { "draft.group.\(propertyId?.uuidString ?? "none").\(groupId?.uuidString ?? "main")" }
    private var subjectDraftKey: String { draftKey + ".subject" }

    private var typingText: String? {
        let names = messageService.typingNames.sorted()
        guard let first = names.first else { return nil }
        if names.count == 1 { return String(format: String(localized: "%@ is typing…"), first) }
        return String(format: String(localized: "%d people are typing…"), names.count)
    }
    /// Family members (other than me) currently online, for the header
    /// subtitle. Presence is keyed by AUTH USER ID (names drift and carry
    /// stray whitespace); `now` is the PresenceTicker's clock so the online
    /// window re-evaluates while the header is visible.
    private func onlineText(at now: Date) -> String? {
        let me = senderName
        let myId = supabase.auth.currentSession?.user.id
        let online = familyService.members
            .filter {
                $0.userId != myId && $0.name != me
                    && presenceService.status(userId: $0.userId, name: $0.name, at: now) == .online
            }
            .map(\.name)
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
            (sender: $0.senderName, time: $0.timeDisplay,
             body: MessageSubject.strip($0.body ?? ""))
        })
    }
    private var markedMessages: [Message] { messageService.messages.filter { $0.isMarked == true } }

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
            // The compose bar lives in the safe-area inset — the canonical
            // iMessage structure (matches the DM thread): the scroll view
            // gains the matching bottom inset automatically and the content
            // still slides under the bar's material.
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
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
        // Search is summoned on demand (group details / the magnifier for
        // community groups) — never a bar pinned under the header.
        .chatOnDemandSearch(text: $searchText, isPresented: $showSearch,
                            prompt: Text("Search messages…"))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatHeaderPill {
                    if groupId != nil {
                        // Community group: its own title (no property avatar or
                        // property group-info tap). Typing/online subtitle stays
                        // for parity — typing is genuinely group-scoped via svc.
                        VStack(alignment: .leading, spacing: 0) {
                            Text(groupTitle ?? "")
                                .font(AppFont.subheadline)
                                .foregroundStyle(.primary)
                            if let t = typingText {
                                Text(t)
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                PresenceTicker { now in
                                    if let o = onlineText(at: now) {
                                        Text(o)
                                            .font(AppFont.scaled(11))
                                            .foregroundStyle(Color.brandSuccess)
                                    }
                                }
                            }
                        }
                    } else {
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
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    PresenceTicker { now in
                                        if let o = onlineText(at: now) {
                                            Text(o)
                                                .font(AppFont.scaled(11))
                                                .foregroundStyle(Color.brandSuccess)
                                        }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showGroupInfo = true }
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if groupId != nil {
                    // A community group manages everything (rename, members,
                    // notifications, delete) through its settings sheet, so the
                    // trailing cluster is magnifier + gear instead of
                    // call/video. The magnifier keeps in-thread search
                    // reachable now that the bar is no longer pinned (a
                    // community group has no group-details page).
                    HStack(spacing: 0) {
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Search messages…"))

                        Button { groupSettingsAction?() } label: {
                            Image(systemName: "gearshape.fill")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Group settings")
                    }
                    // iOS 26 wraps toolbar items in system Liquid Glass —
                    // only pre-26 draws its own capsule (see chatToolbarCapsule).
                    .chatToolbarCapsule()
                } else {
                    ChatHeaderActions(
                        onVideo: { showVideoSheet = true },
                        onCall: { showCallSheet = true }
                    )
                }
            }
        }
        .task {
            guard let pid = propertyId else { return }
            // Freeze where the reader left off BEFORE marking anything read, so
            // the "unread messages" divider lands at the first new message.
            let seen = messageService.lastSeen(propertyId: pid)
            // The property group-chat name only applies to the main chat; a
            // community group carries its own title via `groupTitle`.
            if groupId == nil { await propertyService.loadGroupChatName() }
            await messageService.load(propertyId: pid, groupId: groupId)
            unreadDividerId = messageService.firstUnreadId(
                since: seen, myId: supabase.auth.currentSession?.user.id)
            messageService.resetUnread()
            await presenceService.load(propertyId: pid)
            await messageService.loadReads(propertyId: pid, groupId: groupId)
            await messageService.loadDeliveries(propertyId: pid, groupId: groupId)
            await messageService.loadReactions(propertyId: pid, groupId: groupId)
            await messageService.markDelivered(propertyId: pid, delivererName: senderName)
            await messageService.markRead(propertyId: pid, readerName: senderName)
            // Retry queued messages only after load() scoped the service to
            // this conversation, so a flush can never stamp the wrong group.
            await flushOutbox()
            // Opening the group thread clears the chat notification rows + the
            // springboard badge so the bell can't keep claiming read messages.
            if let uid = supabase.auth.currentSession?.user.id {
                await notificationService.markModuleRead("chat", userId: uid)
            }
        }
        .task {
            guard let pid = propertyId else { return }
            messageService.myName = senderName
            // The group scope rides along explicitly: these tasks race
            // load(), so deriving the channel topic from currentGroupId
            // could subscribe a community thread to the MAIN chat's topic —
            // the realtime client would then return the already-subscribed
            // channel and silently drop the new callbacks.
            await messageService.subscribeRealtime(propertyId: pid, groupId: groupId)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReads(propertyId: pid, groupId: groupId)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeDeliveries(propertyId: pid, groupId: groupId)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReactions(propertyId: pid, groupId: groupId)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.loadPollVotes(propertyId: pid, groupId: groupId)
            await messageService.subscribePollVotes(propertyId: pid, groupId: groupId)
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
            if subject.isEmpty, let s = UserDefaults.standard.string(forKey: subjectDraftKey), !s.isEmpty { subject = s }
        }
        .onDisappear {
            chatLoadGraceTask?.cancel()
            chatLoadGraceTask = nil
            // Persist the unsent composer draft once, on the way out.
            if text.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
            else { UserDefaults.standard.set(text, forKey: draftKey) }
            if subject.isEmpty { UserDefaults.standard.removeObject(forKey: subjectDraftKey) }
            else { UserDefaults.standard.set(subject, forKey: subjectDraftKey) }
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
            // Typing "@" summons the mention picker; the typing broadcast is
            // throttled inside ChatComposerBar. Draft persistence happens on
            // disappear — a UserDefaults write per keystroke is typing lag.
            if newValue.hasSuffix("@") && !showMentionPicker {
                text = String(newValue.dropLast())
                showMentionPicker = true
            }
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
        .sheet(isPresented: $showStarred) {
            StarredMessagesView(messages: markedMessages, members: familyService.members) { id in
                showStarred = false
                scrollTarget = id
            }
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
                onSendLater: { showSendLater = true }
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

}

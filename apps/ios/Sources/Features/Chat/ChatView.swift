import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import UserNotifications
import UniformTypeIdentifiers
import Supabase

private let kAvatarRingColorKey = "prvio.avatarRingColorName"

private struct ChatBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ChatView: View {
    @EnvironmentObject var messageService: MessageService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @EnvironmentObject private var stickerService: StickerService
    @EnvironmentObject private var router: AppRouter
    @State var text = ""
    @State var photoPickerItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showJumpToLatest = false
    @State private var showStarred = false
    @State private var showGroupInfo = false
    @State private var showAddMember = false
    @State private var scrollTarget: UUID? = nil
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
    @State var mentionedIds: [String] = []
    @State var mentionedNames: [String] = []
    @State var isSending = false
    @State private var showPhotoPickerTrigger = false
    @State private var showFileImporter = false
    @State var sendError: String? = nil
    @FocusState private var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @AppStorage("prvio.chatTheme") private var chatThemeID: String = "appDefault"
    @State private var showThemePicker = false
    @StateObject private var audioRecorder = ChatAudioRecorder()
    @StateObject var outbox = OfflineOutbox()

    private var chatTheme: ChatTheme { .theme(for: chatThemeID) }
    private var pendingOutbox: [PendingMessage] {
        guard let pid = propertyId else { return [] }
        return outbox.pending(for: pid)
    }

    var propertyId: UUID? { propertyService.primary?.id }

    private var draftKey: String { "draft.group.\(propertyId?.uuidString ?? "none")" }

    private func sameDay(_ a: Message, _ b: Message) -> Bool {
        let f  = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        let dA = f.date(from: a.createdAt) ?? f2.date(from: a.createdAt) ?? Date()
        let dB = f.date(from: b.createdAt) ?? f2.date(from: b.createdAt) ?? Date()
        return Calendar.current.isDate(dA, inSameDayAs: dB)
    }

    private var filteredMessages: [Message] {
        guard showSearch && !searchText.isEmpty else { return messageService.messages }
        return messageService.messages.filter {
            ($0.body ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    private var typingText: String? {
        let names = messageService.typingNames.sorted()
        guard let first = names.first else { return nil }
        if names.count == 1 { return String(format: String(localized: "%@ is typing…"), first) }
        return String(format: String(localized: "%d people are typing…"), names.count)
    }
    private var pinnedMessages: [Message] { messageService.messages.filter { $0.pinned == true } }
    private var markedMessages: [Message] { messageService.messages.filter { $0.isMarked == true } }

    @ViewBuilder
    private func actionOverlay(_ m: Message) -> some View {
        let own = m.senderId == supabase.auth.currentSession?.user.id
        ChatActionOverlay(
            previewText: pinnedSnippet(m),
            isOwn: own,
            bubbleColor: chatThemeID == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble,
            myReaction: messageService.reactions[m.id]?.first(where: { $0.userId == supabase.auth.currentSession?.user.id })?.emoji,
            onReact: { e in
                if let pid = propertyId {
                    Task { await messageService.toggleReaction(messageId: m.id, propertyId: pid, emoji: e, reactorName: senderName) }
                }
            },
            actions: messageActions(m),
            onDismiss: { withAnimation(.easeOut(duration: 0.2)) { menuMessage = nil } }
        )
        .transition(.opacity)
    }

    private func messageActions(_ m: Message) -> [ChatActionItem] {
        let own = m.senderId == supabase.auth.currentSession?.user.id
        var items: [ChatActionItem] = [
            ChatActionItem("Reply", "arrowshape.turn.up.left") { withAnimation(.spring(response: 0.3)) { replyingTo = m } },
            ChatActionItem("Forward", "arrowshape.turn.up.right") { forwardingMessage = m },
            ChatActionItem("Copy", "doc.on.doc") { if let b = m.body { UIPasteboard.general.string = b } },
            ChatActionItem(m.isMarked == true ? "Unmark" : "Mark", "flag") { Task { await messageService.toggleMark(m) } },
            ChatActionItem(m.pinned == true ? "Unpin" : "Pin", "pin") { Task { await messageService.togglePin(m) } }
        ]
        if own, m.body?.isEmpty == false, m.attachmentType == nil {
            items.append(ChatActionItem("Edit", "pencil") { editingMessage = m; editText = m.body ?? "" })
        }
        items.append(ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m })
        return items
    }

    private func pinnedSnippet(_ m: Message) -> String {
        if let b = m.body, !b.isEmpty { return b }
        if m.isImageMessage { return "📷 Photo" }
        if m.isAudioMessage { return "🎤 Voice message" }
        if m.isLocationMessage { return "📍 Location" }
        if m.isFileMessage { return "📎 File" }
        if m.isStickerMessage { return "😀 Sticker" }
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
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    MemberAvatarStack(
                        members: familyService.members,
                        ownerAvatarUrl: profileService.profile?.avatarUrl,
                        ownerInitial: ownerInitial,
                        ringColor: avatarRingColor(for: avatarRingColorName)
                    ) {
                        showGroupInfo = true
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Chat Grup"))
                            .font(.system(size: 16, weight: .semibold))
                        if let t = typingText {
                            Text(t)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("Grup · \(familyService.members.count + 1) membri")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.45))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showGroupInfo = true }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showVideoSheet = true } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Video call")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCallSheet = true } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call")
            }
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.load(propertyId: pid)
            messageService.resetUnread()
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
        .task { await flushOutbox() }
        .onChange(of: outbox.isOnline) { _, online in
            if online { Task { await flushOutbox() } }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = true }
            if text.isEmpty, let d = UserDefaults.standard.string(forKey: draftKey), !d.isEmpty { text = d }
        }
        .onDisappear {
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = false }
            Task {
                await messageService.unsubscribe()
                await messageService.unsubscribeReads()
                await messageService.unsubscribeDeliveries()
                await messageService.unsubscribeReactions()
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
            // Draft restoration: persist the unsent composer text per conversation.
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
            else { UserDefaults.standard.set(newValue, forKey: draftKey) }
        }
        .photosPicker(isPresented: $showPhotoPickerTrigger, selection: $photoPickerItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoPickerItems) { _, items in Task { await sendPhoto(items) } }
        .sheet(isPresented: $showLocationSheet) {
            LocationShareSheet { lat, lon in
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
            StickerPicker { sticker in
                Task { await sendSticker(sticker) }
            }
            .environmentObject(stickerService)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showStarred) {
            StarredMessagesView(messages: markedMessages, members: familyService.members) { id in
                showStarred = false
                scrollTarget = id
            }
        }
        .sheet(isPresented: $showThemePicker) {
            ChatThemePicker()
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupDetailsView(
                groupName: (propertyService.primary?.name).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Chat Grup"),
                members: familyService.members,
                photoUrl: propertyService.primary?.photoUrl,
                onAudio: { showCallSheet = true },
                onVideo: { showVideoSheet = true },
                onAddMember: { showAddMember = true },
                onSearch: { withAnimation(.spring(response: 0.3)) { showSearch = true } },
                onStarred: { showStarred = true },
                onTheme: { showThemePicker = true }
            )
        }
        .sheet(isPresented: $showAddMember) {
            AddFamilyMemberSheet(propertyId: propertyId, propertyName: propertyService.primary?.name)
                .environmentObject(familyService)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            ChatAttachmentSheet(
                onPhotos: { showPhotoPickerTrigger = true },
                onCamera: { showCameraSheet = true },
                onLocation: { showLocationSheet = true },
                onDocument: { showFileImporter = true },
                onContact: { showContactPicker = true },
                onPoll: { showPollComposer = true },
                onEvent: { showEventComposer = true }
            )
        }
        .sheet(isPresented: $showContactPicker) {
            ChatContactPicker { formatted in Task { await sendContact(formatted) } }
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
                        Task { await messageService.editMessage(id: m.id, newBody: newText) }
                    }
                }
                editingMessage = nil
            }
        }
        .fullScreenCover(isPresented: $showCameraSheet) {
            CameraPickerView { image in
                Task { await sendCameraPhoto(image) }
            }
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
        GeometryReader { outer in
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if showSearch {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        TextField("Search messages…", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .tint(.accentColor)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 16)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

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
                                    .font(.system(size: 11, weight: .semibold))
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
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, 16).padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
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
                        .padding(.vertical, 8)
                        .disabled(messageService.isLoadingOlder)
                    }
                    ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { idx, msg in
                        if idx == 0 || !sameDay(filteredMessages[idx - 1], msg) {
                            ChatDateSeparator(dateStr: msg.createdAt)
                        }
                        MessageBubble(
                            message: msg,
                            isOwn: msg.senderId == supabase.auth.currentSession?.user.id,
                            members: familyService.members,
                            outgoingColor: chatThemeID == "appDefault" ? nil : chatTheme.outgoingBubble,
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
                            repliedMessage: msg.replyTo.flatMap { rid in messageService.messages.first { $0.id == rid } },
                            onReply: { withAnimation(.spring(response: 0.3)) { replyingTo = msg } },
                            onPin: { Task { await messageService.togglePin(msg) } },
                            onMark: { Task { await messageService.toggleMark(msg) } },
                            onForward: { forwardingMessage = msg },
                            onEdit: { editingMessage = msg; editText = msg.body ?? "" },
                            onDeleteForEveryone: { Task { await messageService.deleteForEveryone(id: msg.id) } },
                            onDeleteForMe: { messageService.deleteForMe(id: msg.id) },
                            pollVotes: messageService.pollVotes[msg.id] ?? [],
                            myUserId: supabase.auth.currentSession?.user.id,
                            onPollVote: { idx in
                                guard let pid = propertyId, let poll = ChatPoll.decode(msg.body) else { return }
                                Task { await messageService.togglePollVote(
                                    messageId: msg.id, propertyId: pid,
                                    optionIndex: idx, voterName: senderName, multi: poll.multi) }
                            },
                            onLongPress: { menuMessage = msg }
                        )
                        .id(msg.id)
                    }
                    // Pending (offline) messages — shown optimistically with a clock.
                    ForEach(pendingOutbox) { pm in
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack {
                                Spacer(minLength: 60)
                                HStack(spacing: 6) {
                                    Text(pm.body ?? "")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white)
                                    Image(systemName: outbox.isOnline ? "clock" : "exclamationmark.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(chatThemeID == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble,
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
                                    .foregroundStyle(Color.primary.opacity(0.45))
                                    .padding(.trailing, 4)
                            }
                        }
                    }
                    // Clearance so the newest message rests above the overlaid
                    // input bar (which blurs the messages behind it = real glass).
                    Color.clear.frame(height: chatBottomInset)
                    Color.clear.frame(height: 1).id("CHAT_BOTTOM")
                        .background(GeometryReader { g in
                            Color.clear.preference(key: ChatBottomKey.self,
                                                   value: g.frame(in: .named("CHATOUTER")).maxY)
                        })
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: filteredMessages.count)
            }
            .defaultScrollAnchor(.bottom)
            .onPreferenceChange(ChatBottomKey.self) { maxY in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJumpToLatest = maxY > outer.size.height + 40
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messageService.messages.count) { old, new in
                guard !messageService.messages.isEmpty else { return }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                    .padding(.bottom, chatBottomInset + 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            } // end ScrollViewReader
        }
        .coordinateSpace(name: "CHATOUTER")
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if let replyingTo {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: String(localized: "Reply to %@"), replyingTo.senderName))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                        Text(replyingTo.body?.isEmpty == false ? (replyingTo.body ?? "") : String(localized: "Attachment"))
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                    Button { withAnimation { self.replyingTo = nil } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.4))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
            }
            if !mentionedNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(zip(mentionedIds, mentionedNames)), id: \.0) { id, name in
                            HStack(spacing: 4) {
                                Text("@\(name)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                Button {
                                    mentionedIds.removeAll { $0 == id }
                                    mentionedNames.removeAll { $0 == name }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .symbolEffect(.pulse)
                        Text(audioRecorder.durationText)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("← Slide to cancel")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .liquidGlass(cornerRadius: 22)
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Message…", text: $text, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(1...6)
                        .focused($focused)

                    HStack(spacing: 0) {
                        Button {
                            focused = false
                            showAttachmentSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.55))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)

                        Button {
                            focused = false
                            showStickerPicker = true
                        } label: {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.55))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)

                        Spacer()

                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Mic button — hold to record
                            ZStack {
                                Circle()
                                    .fill(audioRecorder.isRecording ? Color.red.opacity(0.15) : Color.primary.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(audioRecorder.isRecording ? Color.red : Color.primary.opacity(0.45))
                                    .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                            }
                            .onLongPressGesture(minimumDuration: 0.3) {
                                guard !audioRecorder.isRecording else { return }
                                audioRecorder.start()
                                HapticFeedback.impact(.medium)
                            }
                        } else {
                            // Send button
                            Button {
                                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                Task { await sendText() }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 30, height: 30)
                                    if isSending {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSending)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .liquidGlass(cornerRadius: 22)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
    }
}

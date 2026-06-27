import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import UserNotifications
import UniformTypeIdentifiers
import Supabase

private let kAvatarRingColorKey = "prvio.avatarRingColorName"

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
    @State private var showLocationSheet = false
    @State private var showMentionPicker = false
    @State private var showCameraSheet = false
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    @State private var showStickerPicker = false
    @State var mentionedIds: [String] = []
    @State var mentionedNames: [String] = []
    @State var isSending = false
    @State private var showPhotoPickerTrigger = false
    @State private var showFileImporter = false
    @State var sendError: String? = nil
    @FocusState private var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @StateObject private var audioRecorder = ChatAudioRecorder()

    var propertyId: UUID? { propertyService.primary?.id }

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .background(appBackground.ignoresSafeArea())
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
                        withAnimation { showMentionPicker.toggle() }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Chat Grup"))
                            .font(.system(size: 16, weight: .semibold))
                        Text("Grup · \(familyService.members.count + 1) membri")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.3)) { showSearch.toggle() }
                        if !showSearch { searchText = "" }
                    } label: {
                        Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 18)

                    Button { showCallSheet = true } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 18)

                    Button { showVideoSheet = true } label: {
                        Image(systemName: "video.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.load(propertyId: pid)
            messageService.resetUnread()
            await messageService.loadReads(propertyId: pid)
            await messageService.loadReactions(propertyId: pid)
            await messageService.markRead(propertyId: pid, readerName: senderName)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeRealtime(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReads(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReactions(propertyId: pid)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = true } }
        .onDisappear {
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = false }
            Task {
                await messageService.unsubscribe()
                await messageService.unsubscribeReads()
                await messageService.unsubscribeReactions()
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue.hasSuffix("@") && !showMentionPicker {
                text = String(newValue.dropLast())
                showMentionPicker = true
            }
        }
        .photosPicker(isPresented: $showPhotoPickerTrigger, selection: $photoPickerItems, maxSelectionCount: 1, matching: .images)
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

    private var messageList: some View {
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

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { idx, msg in
                        if idx == 0 || !sameDay(filteredMessages[idx - 1], msg) {
                            ChatDateSeparator(dateStr: msg.createdAt)
                        }
                        MessageBubble(
                            message: msg,
                            isOwn: msg.senderId == supabase.auth.currentSession?.user.id,
                            members: familyService.members,
                            readers: messageService.reads[msg.id] ?? [],
                            onDelete: { Task { await messageService.deleteMessage(id: msg.id) } },
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
                            }
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messageService.messages.count) { old, new in
                guard let last = messageService.messages.last else { return }
                if old == 0 {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                if let pid = propertyId {
                    Task { await messageService.markRead(propertyId: pid, readerName: senderName) }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let last = messageService.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            } // end VStack (search + scroll)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
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
                        .lineLimit(1...5)
                        .focused($focused)

                    HStack(spacing: 0) {
                        Menu {
                            Button { showCameraSheet = true } label: { Label("Camera", systemImage: "camera.fill") }
                            Button { showPhotoPickerTrigger = true } label: { Label("Photo / Video", systemImage: "photo") }
                            Button { showLocationSheet = true } label: { Label("Share Location", systemImage: "location.fill") }
                            Button { showFileImporter = true } label: { Label("File", systemImage: "doc.fill") }
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
                                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
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

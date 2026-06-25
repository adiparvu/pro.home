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
    @Environment(\.dismiss) private var dismiss

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
    @FocusState private var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @AppStorage("prvio.voiceInput") private var voiceInputEnabled: Bool = true
    @StateObject var speech = SpeechRecognizer()
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
        profileService.profile?.displayName
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
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    HapticFeedback.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
            }
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
                        Text(String(localized: "Family Chat"))
                            .font(.system(size: 16, weight: .semibold))
                        Text("Group · \(familyService.members.count + 1) members")
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
        .onAppear { withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = true } }
        .onDisappear {
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = false }
            Task {
                await messageService.unsubscribe()
                await messageService.unsubscribeReads()
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
        .userActivity("com.prvio.chat") { activity in
            activity.title = String(localized: "Chat familie — PRVIO")
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
                            readers: messageService.reads[msg.id] ?? []
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messageService.messages.count) { _, _ in
                if let last = messageService.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                if let pid = propertyId {
                    Task { await messageService.markRead(propertyId: pid, readerName: senderName) }
                }
            }
            .onAppear {
                if let last = messageService.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
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

                    if voiceInputEnabled {
                        Button {
                            HapticFeedback.impact(.light)
                            if speech.isListening {
                                speech.stop()
                            } else {
                                focused = false
                                Task { await speech.startListening() }
                            }
                        } label: {
                            Image(systemName: speech.isListening ? "waveform" : "mic")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(speech.isListening ? Color.red : Color.primary.opacity(0.55))
                                .symbolEffect(.pulse, isActive: speech.isListening)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)
                        .onChange(of: speech.transcript) { _, t in
                            if !t.isEmpty { text = t }
                        }
                    }

                    VoiceRecordButton(recorder: audioRecorder) { url in
                        Task { await sendAudio(url: url) }
                    }
                    .padding(.leading, 2)

                    Spacer()

                    Button {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        speech.stop()
                        Task { await sendText() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(text.isEmpty ? Color.primary.opacity(0.12) : Color.primary)
                                .frame(width: 30, height: 30)
                            Image(systemName: isSending ? "stop.fill" : "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(text.isEmpty
                                    ? Color.primary.opacity(0.35)
                                    : Color(UIColor.systemBackground))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty || isSending)
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

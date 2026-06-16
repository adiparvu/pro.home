import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import UserNotifications
import Supabase

private let kAvatarRingColorKey = "prvio.avatarRingColorName"

struct ChatView: View {
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @EnvironmentObject private var stickerService: StickerService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showLocationSheet = false
    @State private var showMentionPicker = false
    @State private var showCameraSheet = false
    @State private var showCallSheet = false
    @State private var showVideoSheet = false
    @State private var showStickerPicker = false
    @State private var mentionedIds: [String] = []
    @State private var mentionedNames: [String] = []
    @State private var isSending = false
    @FocusState private var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @AppStorage("prvio.voiceInput") private var voiceInputEnabled: Bool = true
    @StateObject private var speech = SpeechRecognizer()

    private var propertyId: UUID? { propertyService.primary?.id }
    private var senderName: String {
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
        .navigationTitle("Family Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 6) {
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            router.selectedTab = .home
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)

                    MemberAvatarStack(
                        members: familyService.members,
                        ownerAvatarUrl: profileService.profile?.avatarUrl,
                        ownerInitial: ownerInitial,
                        ringColor: avatarRingColor(for: avatarRingColorName)
                    ) {
                        withAnimation { showMentionPicker.toggle() }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {
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
        .userActivity("com.prvio.chat") { activity in
            activity.title = "Chat familie — PRVIO"
            activity.userInfo = ["tab": "chat"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(messageService.messages) { msg in
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

    // MARK: - Actions

    @State private var showPhotoPickerTrigger = false

    private func sendText() async {
        guard let pid = propertyId else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        HapticFeedback.impact(.light)
        isSending = true
        defer { isSending = false }
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: body, mentionedIds: mentionedIds
        )
        scheduleLocalMentionNotifications(body: body)
        mentionedIds = []; mentionedNames = []
    }

    private func sendSticker(_ sticker: Sticker) async {
        guard let pid = propertyId else { return }
        HapticFeedback.success()
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: sticker.id, attachmentType: "sticker"
        )
    }

    private func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard let pid = propertyId, let item = items.first else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        isSending = true
        defer { isSending = false }
        let fileName = "\(UUID().uuidString).jpg"
        let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/\(fileName)"
        try? await supabase.storage.from("documents")
            .upload(filePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        let url = try? supabase.storage.from("documents").getPublicURL(path: filePath)
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: nil,
            attachmentUrl: url?.absoluteString, attachmentType: "image",
            mentionedIds: mentionedIds
        )
        HapticFeedback.success()
        photoPickerItems = []
        mentionedIds = []; mentionedNames = []
    }

    private func sendCameraPhoto(_ image: UIImage) async {
        guard let pid = propertyId,
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        isSending = true
        defer { isSending = false }
        let fileName = "\(UUID().uuidString).jpg"
        let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/\(fileName)"
        try? await supabase.storage.from("documents")
            .upload(filePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        let url = try? supabase.storage.from("documents").getPublicURL(path: filePath)
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: nil,
            attachmentUrl: url?.absoluteString, attachmentType: "image",
            mentionedIds: mentionedIds
        )
        HapticFeedback.success()
        mentionedIds = []; mentionedNames = []
    }

    private func sendLocation(lat: Double, lon: Double) async {
        guard let pid = propertyId else { return }
        isSending = true
        defer { isSending = false }
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: "📍 Shared a location",
            attachmentType: "location", latitude: lat, longitude: lon,
            mentionedIds: mentionedIds
        )
        HapticFeedback.success()
        mentionedIds = []; mentionedNames = []
    }

    private func scheduleLocalMentionNotifications(body: String) {
        guard !mentionedNames.isEmpty else { return }
        guard NotificationScheduler.prefEnabled(NotificationScheduler.Keys.mentions) else { return }
        let center = UNUserNotificationCenter.current()
        for name in mentionedNames {
            let content = UNMutableNotificationContent()
            content.title = "\(senderName) mentioned \(name)"
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "mention.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(req)
        }
    }
}

import SwiftUI
import PhotosUI
import UIKit
import Supabase

// MARK: - Direct Message View (1-on-1 private chat)

struct DirectMessageView: View {
    let member: FamilyMember

    @EnvironmentObject private var directMessageService: DirectMessageService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService

    @State private var input = ""
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State private var showAttachmentTray = false
    @State private var showProfile = false
    @State private var sendError: String? = nil
    @FocusState private var focused: Bool
    @State private var isSending = false
    @StateObject private var audioRecorder = ChatAudioRecorder()
    @State private var recordingCancelled = false

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    private var conversationMessages: [DirectMessage] {
        directMessageService.messages(with: member.name, myName: myName)
    }

    private var isTextEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                messageList
                inputBar
            }
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
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(member.roleLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showProfile) {
            MemberProfileSheet(member: member)
                .environmentObject(familyService)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            DMCameraPickerView(isPresented: $showCameraPicker) { img in
                Task { @MainActor in await sendCameraImage(img) }
            }
            .ignoresSafeArea()
        }
        .onAppear { directMessageService.markRead(partner: member.name) }
        .alert("Message Not Sent", isPresented: .init(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            Group {
                if conversationMessages.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(conversationMessages.enumerated()), id: \.element.id) { idx, msg in
                                let isOwn = msg.senderName == myName
                                let prevSameSender = idx > 0 && conversationMessages[idx - 1].senderName == msg.senderName
                                let showDate = idx == 0 || !sameDay(conversationMessages[idx - 1], msg)

                                if showDate {
                                    ChatDateSeparator(dateStr: msg.createdAt)
                                        .padding(.top, idx == 0 ? 8 : 16)
                                }

                                DMBubble(
                                    message: msg,
                                    isOwn: isOwn,
                                    showSenderBubbleTail: !prevSameSender || showDate,
                                    onDelete: isOwn ? { Task { await directMessageService.deleteMessage(id: msg.id) } } : nil
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: conversationMessages.count) { _, _ in
                        if let last = conversationMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        directMessageService.markRead(partner: member.name)
                    }
                    .onAppear {
                        if let last = conversationMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
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

    private var inputBar: some View {
        VStack(spacing: 0) {
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
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlass(cornerRadius: 20)
                        .opacity(audioRecorder.isRecording ? 0 : 1)
                        .allowsHitTesting(!audioRecorder.isRecording)
                        .onChange(of: input) { _, val in
                            if !val.isEmpty, showAttachmentTray {
                                withAnimation { showAttachmentTray = false }
                            }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .animation(.spring(duration: 0.3), value: showAttachmentTray)
        .animation(.spring(duration: 0.2), value: audioRecorder.isRecording)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems,
                      maxSelectionCount: 1, matching: .images)
        .onChange(of: photoPickerItems) { _, items in Task { await sendPhoto(items) } }
    }

    private var plusButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                showAttachmentTray.toggle()
                if showAttachmentTray { focused = false }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 34, height: 34)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(showAttachmentTray ? Color.accentColor : Color.primary.opacity(0.5))
                    .rotationEffect(.degrees(showAttachmentTray ? 45 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    private var recordingIndicator: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse)
            Text(audioRecorder.durationText)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Spacer()
            Image(systemName: "lessthan")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.3))
            Text("Slide to cancel")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlass(cornerRadius: 20)
    }

    private var cameraButton: some View {
        Button {
            withAnimation { showAttachmentTray = false }
            showCameraPicker = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.07), in: Circle())
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
                .fill(audioRecorder.isRecording ? Color.red.opacity(0.12) : Color.primary.opacity(0.07))
                .frame(width: 34, height: 34)
            Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
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
        .padding(.vertical, 16)
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
        }

        do {
            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(Payload(sender_name: myName, recipient_name: member.name,
                                body: text, property_id: propertyService.primary?.id.uuidString))
                .select()
                .single()
                .execute()
                .value
            directMessageService.dms.append(sent)
            HapticFeedback.impact(.light)
        } catch {
            HapticFeedback.warning()
            sendError = String(localized: "Failed to send message. Check your connection and try again.")
#if DEBUG
            print("[DM] send error: \(error)")
#endif
        }
    }

    @MainActor
    private func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard let item = items.first else { return }
        photoPickerItems = []
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await uploadAndSendImage(data: data)
    }

    @MainActor
    private func sendCameraImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        await uploadAndSendImage(data: data)
    }

    @MainActor
    private func uploadAndSendImage(data: Data) async {
        guard let propId = propertyService.primary?.id else { return }
        let filename = "dm-images/\(UUID().uuidString).jpg"

        do {
            try await supabase.storage.from("documents")
                .upload(filename, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            guard let urlStr = try? supabase.storage.from("documents").getPublicURL(path: filename).absoluteString,
                  !urlStr.isEmpty else { return }

            struct PhotoPayload: Encodable {
                let sender_name, recipient_name, body, property_id: String
            }

            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(PhotoPayload(sender_name: myName, recipient_name: member.name,
                                     body: urlStr, property_id: propId.uuidString))
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
        let filename = "dm-audio/\(UUID().uuidString).m4a"

        do {
            try await supabase.storage.from("documents")
                .upload(filename, data: data, options: FileOptions(contentType: "audio/mp4", upsert: false))
            guard let urlStr = try? supabase.storage.from("documents").getPublicURL(path: filename).absoluteString,
                  !urlStr.isEmpty else { return }

            struct AudioPayload: Encodable {
                let sender_name, recipient_name, body, property_id: String
            }

            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(AudioPayload(sender_name: myName, recipient_name: member.name,
                                     body: urlStr, property_id: propId.uuidString))
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
                    .font(.system(size: 11, weight: .medium))
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
    let showSenderBubbleTail: Bool
    var onDelete: (() -> Void)? = nil

    private enum DMMessageType { case text, image, audio }

    private var messageType: DMMessageType {
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
            if isOwn { Spacer(minLength: 72) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                Group {
                    switch messageType {
                    case .audio: AudioBubble(url: URL(string: message.body), isOwn: isOwn)
                    case .image: imageBubble
                    case .text:  textBubble
                    }
                }
                .contextMenu {
                    if messageType == .text {
                        Button {
                            UIPasteboard.general.string = message.body
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    if isOwn, let onDelete {
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Text(message.timeDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .padding(.horizontal, 2)
            }

            if !isOwn { Spacer(minLength: 72) }
        }
        .padding(.vertical, 1)
    }

    private var textBubble: some View {
        Text(message.body)
            .font(.system(size: 15))
            .foregroundStyle(isOwn ? .white : .primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                isOwn ? Color.accentColor : Color.primary.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var imageBubble: some View {
        AsyncImage(url: URL(string: message.body)) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            case .failure:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 220, height: 140)
                    .overlay(Image(systemName: "photo").foregroundStyle(Color.primary.opacity(0.3)))
            default:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 220, height: 140)
                    .overlay(ProgressView())
            }
        }
    }
}

import SwiftUI
import PhotosUI
import UserNotifications
import UniformTypeIdentifiers

// MARK: - ChatView send actions

extension ChatView {

    /// The single persistent send path for EVERY group message type. It attempts
    /// the insert (MessageService.send handles the optimistic bubble + a bounded,
    /// timed insert); on ANY failure — offline, RLS, or a hung/timed-out call —
    /// it enqueues to the offline outbox so the message survives and retries
    /// automatically when connectivity returns, instead of silently vanishing.
    /// Media callers upload first and pass the resulting storage path.
    @discardableResult
    func performGroupSend(
        body: String?,
        attachmentUrl: String? = nil,
        attachmentType: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        kind: PendingKind = .text,
        mentionedIds: [String] = [],
        replyTo: UUID? = nil
    ) async -> Bool {
        guard let pid = propertyId else { return false }
        do {
            try await messageService.send(
                propertyId: pid, senderName: senderName, body: body,
                attachmentUrl: attachmentUrl, attachmentType: attachmentType,
                latitude: latitude, longitude: longitude,
                mentionedIds: mentionedIds, replyTo: replyTo
            )
            return true
        } catch {
            // The queued row records its conversation scope so it can only
            // ever render in — and re-send into — this group (or main chat).
            outbox.enqueue(PendingMessage(
                propertyId: pid, groupId: groupId, senderName: senderName, body: body,
                attachmentUrl: attachmentUrl, attachmentType: attachmentType,
                latitude: latitude, longitude: longitude, kind: kind,
                mentionedIds: mentionedIds, replyTo: replyTo
            ))
            HapticFeedback.warning()
            return false
        }
    }

    func sendText() async {
        guard propertyId != nil else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        text = ""
        HapticFeedback.impact(.light)
        MessageSounds.sent()
        isSending = true
        defer { isSending = false }
        let ids = mentionedIds
        let names = mentionedNames
        let replyId = replyingTo?.id
        mentionedIds = []; mentionedNames = []
        replyingTo = nil
        let ok = await performGroupSend(body: body, kind: .text, mentionedIds: ids, replyTo: replyId)
        // Only fire local mention notifications for a message that actually left.
        if ok { scheduleLocalMentionNotifications(names: names, body: body) }
    }

    /// Retries every queued message for this conversation, attachments
    /// included. Scope-guarded twice: the queued row must belong to this
    /// property AND group, and the service must already be scoped to the same
    /// group (send stamps group_id from currentGroupId) — a flush racing
    /// load() can otherwise re-send a group message into the main chat.
    func flushOutbox() async {
        guard let pid = propertyId, messageService.currentGroupId == groupId else { return }
        await outbox.flush { pm in
            guard pm.propertyId == pid, pm.groupId == groupId else { return false }
            do {
                try await messageService.send(
                    propertyId: pm.propertyId, senderName: pm.senderName,
                    body: pm.body, attachmentUrl: pm.attachmentUrl,
                    attachmentType: pm.attachmentType,
                    latitude: pm.latitude, longitude: pm.longitude,
                    mentionedIds: pm.mentionedIds, replyTo: pm.replyTo
                )
                return true
            } catch {
                return false
            }
        }
    }

    func forward(_ message: Message, to dest: ForwardDestination) async {
        guard let pid = propertyId else { return }
        do {
            switch dest {
            case .group:
                try await messageService.send(
                    propertyId: pid, senderName: senderName,
                    body: message.body, attachmentUrl: message.attachmentUrl,
                    attachmentType: message.attachmentType,
                    latitude: message.latitude, longitude: message.longitude
                )
            case .member(let m):
                try await DirectMessageService.forward(
                    body: message.body ?? "📎", senderName: senderName,
                    to: m, propertyId: pid)
            }
            HapticFeedback.success()
        } catch {
            sendError = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    // MARK: - Multi-select (iMessage "Select")

    /// Enter selection mode with the tapped message pre-checked.
    func enterSelection(_ m: Message) {
        selectedIDs = [m.id]
        withAnimation(.snappy(duration: 0.2)) { selecting = true }
    }

    func toggleSelect(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        HapticFeedback.impact(.light)
    }

    func exitSelection() {
        withAnimation(.snappy(duration: 0.2)) { selecting = false }
        selectedIDs = []
    }

    /// Bulk-remove the selection from this device's transcript (delete-for-me,
    /// the always-permitted, non-destructive bulk action iMessage's trash maps to).
    func deleteSelected() {
        for id in selectedIDs { messageService.deleteForMe(id: id) }
        HapticFeedback.success()
        exitSelection()
    }

    /// Forward every selected message to one destination, oldest-first so the
    /// order is preserved, then leave selection mode.
    func forwardSelected(to dest: ForwardDestination) {
        let ordered = messageService.messages.filter { selectedIDs.contains($0.id) }
        Task {
            for m in ordered { await forward(m, to: dest) }
        }
        exitSelection()
    }

    func sendContacts(_ payloads: [SharedContactPayload]) async {
        guard !payloads.isEmpty,
              let body = SharedContactPayload.encodeGroup(payloads) else { return }
        MessageSounds.sent()
        await performGroupSend(body: body, attachmentType: "contact", kind: .contact)
        HapticFeedback.success()
    }

    func sendContact(_ formatted: String) async {
        MessageSounds.sent()
        await performGroupSend(body: "👤 \(formatted)", kind: .contact)
        HapticFeedback.success()
    }

    func sendPoll(question: String, options: [String], multipleChoice: Bool) async {
        let poll = ChatPoll(q: question, opts: options, multi: multipleChoice)
        guard let body = poll.encoded() else { return }
        MessageSounds.sent()
        await performGroupSend(body: body, attachmentType: "poll", kind: .poll)
        HapticFeedback.success()
    }

    func sendEvent(_ draft: ChatEventDraft) async {
        guard let body = draft.payload().encoded() else { return }
        MessageSounds.sent()
        await performGroupSend(body: body, attachmentType: "event", kind: .event)
        HapticFeedback.success()
    }

    func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard let pid = propertyId, !items.isEmpty else { return }
        MessageSounds.sent()
        isSending = true
        defer { isSending = false }
        // A caption typed in the composer is attached to the first image, then cleared.
        let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        // Send each selected item as its own message (preserves order). Images
        // and videos are both supported by the picker.
        let ids = mentionedIds
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let isQuickTime = item.supportedContentTypes.contains { $0.conforms(to: .quickTimeMovie) }
            let ext = isVideo ? (isQuickTime ? "mov" : "mp4") : "jpg"
            let contentType = isVideo ? (isQuickTime ? "video/quicktime" : "video/mp4") : "image/jpeg"
            // Images and videos → private chat-media bucket (signed URL at display).
            guard let path = await ChatMedia.upload(data, propertyId: pid, subdir: "chat",
                                                    ext: ext, contentType: contentType) else {
                sendError = String(localized: "chat_upload_failed")
                HapticFeedback.warning()
                continue
            }
            await performGroupSend(
                body: (index == 0 && !caption.isEmpty) ? caption : nil,
                attachmentUrl: path, attachmentType: isVideo ? "video" : "image",
                kind: isVideo ? .video : .image, mentionedIds: ids
            )
        }
        HapticFeedback.success()
        photoPickerItems = []
        mentionedIds = []; mentionedNames = []
    }

    func sendCameraPhoto(_ image: UIImage) async {
        guard let pid = propertyId,
              let data = image.uploadJPEG(quality: 0.8, maxDimension: 2048) else { return }
        MessageSounds.sent()
        isSending = true
        defer { isSending = false }
        let ids = mentionedIds
        // Private bucket + signed URL (resolved at display via ChatMedia).
        guard let path = await ChatMedia.upload(data, propertyId: pid, subdir: "chat",
                                                ext: "jpg", contentType: "image/jpeg") else {
            sendError = String(localized: "chat_upload_failed"); HapticFeedback.warning(); return
        }
        await performGroupSend(
            body: nil, attachmentUrl: path, attachmentType: "image",
            kind: .image, mentionedIds: ids
        )
        HapticFeedback.success()
        mentionedIds = []; mentionedNames = []
    }

    func sendLocation(lat: Double, lon: Double) async {
        MessageSounds.sent()
        isSending = true
        defer { isSending = false }
        let ids = mentionedIds
        await performGroupSend(
            body: String(localized: "📍 Shared a location"),
            attachmentType: "location", latitude: lat, longitude: lon,
            kind: .location, mentionedIds: ids
        )
        HapticFeedback.success()
        mentionedIds = []; mentionedNames = []
    }

    func sendAudio(url: URL) async {
        guard let pid = propertyId else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        MessageSounds.sent()
        isSending = true
        defer { isSending = false; try? FileManager.default.removeItem(at: url) }
        // Private bucket + signed URL (resolved at playback via ChatMedia).
        guard let path = await ChatMedia.upload(data, propertyId: pid, subdir: "audio",
                                                ext: "m4a", contentType: "audio/mp4") else {
            sendError = String(localized: "chat_upload_failed"); HapticFeedback.warning(); return
        }
        await performGroupSend(
            body: nil, attachmentUrl: path, attachmentType: "audio", kind: .audio
        )
        HapticFeedback.success()
    }

    func sendFile(url: URL) async {
        guard let pid = propertyId else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        MessageSounds.sent()
        isSending = true
        defer { isSending = false }
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let mime = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "application/octet-stream"
        let filename = url.lastPathComponent
        // Private bucket + signed URL (resolved at preview via ChatMedia).
        guard let path = await ChatMedia.upload(data, propertyId: pid, subdir: "files",
                                                ext: ext, contentType: mime) else {
            sendError = String(localized: "chat_upload_failed"); HapticFeedback.warning(); return
        }
        await performGroupSend(
            body: filename, attachmentUrl: path, attachmentType: "file", kind: .file
        )
        HapticFeedback.success()
    }

    func scheduleLocalMentionNotifications(names: [String], body: String) {
        guard !names.isEmpty else { return }
        guard NotificationScheduler.prefEnabled(NotificationScheduler.Keys.mentions) else { return }
        let center = UNUserNotificationCenter.current()
        for name in names {
            let content = UNMutableNotificationContent()
            content.title = String(format: String(localized: "%@ mentioned %@"), senderName, name)
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "MESSAGE"
            let req = UNNotificationRequest(
                identifier: "mention.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(req)
        }
    }
}

// MARK: - Forward destination + picker

enum ForwardDestination {
    case group
    case member(FamilyMember)
}

struct ForwardPicker: View {
    let members: [FamilyMember]
    let onPick: (ForwardDestination) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                List {
                    Section {
                        Button {
                            onPick(.group); dismiss()
                        } label: {
                            Label("Group chat", systemImage: "person.2.fill")
                        }
                    }
                    if !members.isEmpty {
                        Section("People") {
                            ForEach(members) { m in
                                Button {
                                    onPick(.member(m)); dismiss()
                                } label: {
                                    Label(m.name, systemImage: "person.crop.circle")
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Forward to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(.thinMaterial)
    }
}

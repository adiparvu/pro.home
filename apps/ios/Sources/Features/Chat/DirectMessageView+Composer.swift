import SwiftUI
import PhotosUI
import UIKit
import Supabase
import UniformTypeIdentifiers

// MARK: - DirectMessageView — composer (input bar), attachments
// and send helpers (mechanically extracted from
// DirectMessageView.swift; bodies unchanged).

extension DirectMessageView {
    // MARK: - Input Bar

    var sharedMediaURLs: [URL] {
        conversationMessages.compactMap { m in
            guard ChatMedia.dmBodyKind(m.body) == .image else { return nil }
            return URL(string: m.body)
        }
    }

    var exportTranscript: String {
        ChatExport.transcript(title: peerName, lines: conversationMessages.map {
            (sender: $0.senderName, time: $0.timeDisplay,
             body: MessageSubject.strip($0.body))
        })
    }

    var blockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").font(AppFont.scaled(13))
            Text("You blocked this contact.")
                .font(AppFont.scaled(14))
            Button("Unblock") {
                ChatBlockStore.setBlocked(convId, false)
                blockRefresh.toggle()
            }
            .font(AppFont.footnoteEmphasis)
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.base)
        .background(.regularMaterial)
    }

    // The shared iMessage composer (ChatComposerBar) — same component as the
    // group chat, configured with this thread's capabilities.
    var inputBar: some View {
        ChatComposerBar(
            text: $input,
            focused: $focused,
            isSending: isSending,
            config: ChatComposerConfig(
                onPlus: { showAttachmentSheet = true },
                onTyping: { directMessageService.sendTyping() },
                onSendText: { Task { await sendMessage() } },
                onSendAudio: { url in Task { await sendAudio(url) } },
                onRecordingActivity: { directMessageService.sendRecording() },
                disappearingLabel: chatDisappearingChipLabel(ttl: ChatDisappearStore.ttl(disappearKey)),
                showsSubject: showSubjectField
            ),
            subject: showSubjectField ? $subject : nil
        )
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems,
                      maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .onChange(of: photoPickerItems) { _, items in Task { await sendPhoto(items) } }
    }

    // MARK: - Send

    /// The single persistent send path for EVERY DM kind. It routes through
    /// `DirectMessageService.send` (optimistic bubble + bounded, timed insert);
    /// on ANY failure — offline, RLS or a hung/timed-out call — it enqueues to
    /// the offline outbox so the message survives and retries automatically,
    /// instead of silently vanishing. Media callers upload first and pass the
    /// resulting storage path as `body` (the bubble classifies it by prefix).
    @discardableResult
    private func performDMSend(body: String, kind: PendingKind, replyTo: UUID? = nil) async -> Bool {
        do {
            try await directMessageService.send(
                propertyId: propertyService.primary?.id, senderName: myName,
                to: thread, body: body, replyTo: replyTo, expiresAt: dmExpiresAt)
            return true
        } catch {
            if let pid = propertyService.primary?.id {
                outbox.enqueue(PendingMessage(
                    propertyId: pid, senderName: myName,
                    recipientName: member?.name ?? peerName,
                    recipientMemberId: member?.id,
                    recipientUserId: thread.peerUserId,
                    body: body, kind: kind, replyTo: replyTo))
            }
            HapticFeedback.warning()
            return false
        }
    }

    @MainActor
    private func sendMessage() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        // Fold the subject into the body (see MessageSubject) so the whole
        // persistence path — send, outbox, realtime — carries one opaque
        // string. An empty subject encodes to the text unchanged.
        let body = MessageSubject.encode(subject: showSubjectField ? subject : "", text: text)
        input = ""
        subject = ""
        isSending = true
        defer { isSending = false }
        let replyUUID = replyingTo?.id
        withAnimation { replyingTo = nil }
        HapticFeedback.impact(.light)
        MessageSounds.sent()
        await performDMSend(body: body, kind: .text, replyTo: replyUUID)
    }

    func flushOutbox() async {
        guard let pid = propertyService.primary?.id else { return }
        await outbox.flush { pm in
            guard pm.propertyId == pid, let recipient = pm.recipientName else { return false }
            struct P: Encodable {
                let sender_name, recipient_name, body, property_id: String
                let reply_to: String?
                let sender_id, recipient_id, recipient_member_id, expires_at: String?
            }
            let obTtl = ChatDisappearStore.ttl(recipient)
            let obExpires = obTtl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(obTtl)) : nil
            let payload = P(sender_name: pm.senderName, recipient_name: recipient,
                            body: pm.body ?? "", property_id: pid.uuidString,
                            reply_to: pm.replyTo?.uuidString,
                            sender_id: supabase.auth.currentSession?.user.id.uuidString,
                            recipient_id: pm.recipientUserId?.uuidString,
                            recipient_member_id: pm.recipientMemberId?.uuidString,
                            expires_at: obExpires)
            do {
                let sent: DirectMessage = try await withChatTimeout {
                    try await supabase
                        .from("direct_messages")
                        .insert(payload)
                        .select().single().execute().value
                }
                directMessageService.dms.append(sent)
                return true
            } catch {
                return false
            }
        }
    }

    @MainActor
    func forward(_ message: DirectMessage, to dest: ForwardDestination) async {
        guard let propId = propertyService.primary?.id else { return }

        do {
            switch dest {
            case .group:
                // The group table stores media in attachment columns; map the
                // DM body kind onto the matching attachment type.
                switch ChatMedia.dmBodyKind(message.body) {
                case .image:
                    try await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                                  attachmentUrl: message.body, attachmentType: "image")
                case .audio:
                    try await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                                  attachmentUrl: message.body, attachmentType: "audio")
                case .video:
                    try await messageService.send(propertyId: propId, senderName: myName, body: nil,
                                                  attachmentUrl: message.body, attachmentType: "video")
                case .text:
                    try await messageService.send(propertyId: propId, senderName: myName, body: message.body)
                }
            case .member(let m):
                let fwdTtl = ChatDisappearStore.ttl(m.name)
                let fwdExpires = fwdTtl > 0 ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(fwdTtl)) : nil
                try await directMessageService.send(
                    propertyId: propId, senderName: myName, to: DMThread(member: m),
                    body: message.body, expiresAt: fwdExpires)
            }
            HapticFeedback.success()
        } catch {
            sendError = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    // MARK: - Multi-select (iMessage "Select")

    /// Enter selection mode with the tapped message pre-checked (iMessage
    /// selects the message you invoked "Select" on).
    func enterSelection(_ m: DirectMessage) {
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
    /// the always-permitted, non-destructive bulk action iMessage's trash maps
    /// to). Deletes newest-first so the service's index math stays stable.
    func deleteSelected() {
        for id in selectedIDs { directMessageService.deleteForMe(id: id) }
        HapticFeedback.success()
        exitSelection()
    }

    /// Forward every selected message to one destination, oldest-first so the
    /// order is preserved at the other end, then leave selection mode.
    func forwardSelected(to dest: ForwardDestination) {
        let ordered = conversationMessages.filter { selectedIDs.contains($0.id) }
        Task {
            for m in ordered { await forward(m, to: dest) }
        }
        exitSelection()
    }

    @MainActor
    func sendDMContacts(_ payloads: [SharedContactPayload]) async {
        guard !payloads.isEmpty,
              let body = SharedContactPayload.encodeDM(payloads) else { return }
        await sendDMContact(body)
    }

    private func sendDMContact(_ formatted: String) async {
        MessageSounds.sent()
        let body = formatted.hasPrefix(SharedContactPayload.dmMarker) ? formatted : "👤 \(formatted)"
        if await performDMSend(body: body, kind: .contact) { HapticFeedback.success() }
    }

    // MARK: Rich attachments (marker-encoded in the body — parity with group chat)

    @MainActor
    func sendDMLocation(lat: Double, lon: Double) async {
        MessageSounds.sent()
        if await performDMSend(body: DMRich.encodeLocation(lat: lat, lon: lon), kind: .location) {
            HapticFeedback.success()
        }
    }

    @MainActor
    func sendDMEvent(_ draft: ChatEventDraft) async {
        guard let body = DMRich.encodeEvent(draft.payload()) else { return }
        MessageSounds.sent()
        if await performDMSend(body: body, kind: .event) { HapticFeedback.success() }
    }

    @MainActor
    func sendDMFile(url: URL) async {
        guard let propId = propertyService.primary?.id else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        MessageSounds.sent()
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let mime = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "application/octet-stream"
        let filename = url.lastPathComponent
        // Private bucket + signed URL at preview (via ChatMedia), mirroring the
        // group file path; the stored path rides inside the marker-encoded body.
        guard let path = await ChatMedia.upload(data, propertyId: propId, subdir: "dm-files",
                                                ext: ext, contentType: mime) else {
            sendError = String(localized: "chat_upload_failed"); HapticFeedback.warning(); return
        }
        guard let body = DMRich.encodeFile(name: filename, path: path) else { return }
        if await performDMSend(body: body, kind: .file) { HapticFeedback.impact(.light) }
    }

    @MainActor
    private func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        photoPickerItems = []
        // Send each selected item as its own message (preserves order). The
        // picker offers images and videos; branch on the item's content type.
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                let isQuickTime = item.supportedContentTypes.contains { $0.conforms(to: .quickTimeMovie) }
                await uploadAndSendMedia(data: data, subdir: "dm-video",
                                         ext: isQuickTime ? "mov" : "mp4",
                                         contentType: isQuickTime ? "video/quicktime" : "video/mp4",
                                         kind: .video)
            } else {
                await uploadAndSendMedia(data: data, subdir: "dm",
                                         ext: "jpg", contentType: "image/jpeg", kind: .image)
            }
        }
    }

    @MainActor
    func sendCameraImage(_ image: UIImage) async {
        guard let data = image.uploadJPEG(quality: 0.85, maxDimension: 2048) else { return }
        await uploadAndSendMedia(data: data, subdir: "dm", ext: "jpg", contentType: "image/jpeg", kind: .image)
    }

    @MainActor
    private func uploadAndSendMedia(data: Data, subdir: String, ext: String, contentType: String, kind: PendingKind) async {
        guard let propId = propertyService.primary?.id else { return }
        MessageSounds.sent()
        // Private bucket + signed URL at display (via ChatMedia; the subdir in
        // the stored path is what dmBodyKind classifies bubbles by). Once the
        // media lives in the bucket, the insert goes through the unified send so
        // a failed insert queues the (already-uploaded) path instead of orphaning it.
        guard let path = await ChatMedia.upload(data, propertyId: propId, subdir: subdir,
                                                ext: ext, contentType: contentType) else {
            sendError = String(localized: "chat_upload_failed"); HapticFeedback.warning(); return
        }
        if await performDMSend(body: path, kind: kind) { HapticFeedback.impact(.light) }
    }

    @MainActor
    private func sendAudio(_ fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL),
              let propId = propertyService.primary?.id else { return }
        MessageSounds.sent()
        // Private bucket + signed URL at playback (via ChatMedia / AudioBubble).
        guard let path = await ChatMedia.upload(data, propertyId: propId, subdir: "dm-audio",
                                                ext: "m4a", contentType: "audio/mp4") else {
            sendError = String(localized: "chat_upload_failed"); HapticFeedback.warning(); return
        }
        if await performDMSend(body: path, kind: .audio) { HapticFeedback.impact(.light) }
    }
}

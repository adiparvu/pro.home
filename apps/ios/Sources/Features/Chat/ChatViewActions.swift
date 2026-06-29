import SwiftUI
import PhotosUI
import UserNotifications
import Supabase
import UniformTypeIdentifiers

// MARK: - ChatView send actions

extension ChatView {

    func sendText() async {
        guard let pid = propertyId else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        HapticFeedback.impact(.light)
        isSending = true
        defer { isSending = false }
        let replyId = replyingTo?.id
        do {
            try await messageService.send(
                propertyId: pid, senderName: senderName,
                body: body, mentionedIds: mentionedIds, replyTo: replyId
            )
            scheduleLocalMentionNotifications(body: body)
            mentionedIds = []; mentionedNames = []
            replyingTo = nil
        } catch {
            // Offline / send failed → queue it; it sends automatically when back online.
            outbox.enqueue(PendingMessage(
                propertyId: pid, senderName: senderName, body: body,
                mentionedIds: mentionedIds, replyTo: replyId
            ))
            mentionedIds = []; mentionedNames = []
            replyingTo = nil
            HapticFeedback.warning()
        }
    }

    /// Retries every queued message for this property.
    func flushOutbox() async {
        guard let pid = propertyId else { return }
        await outbox.flush { pm in
            guard pm.propertyId == pid else { return false }
            do {
                try await messageService.send(
                    propertyId: pm.propertyId, senderName: pm.senderName,
                    body: pm.body, attachmentUrl: pm.attachmentUrl,
                    attachmentType: pm.attachmentType,
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
        switch dest {
        case .group:
            try? await messageService.send(
                propertyId: pid, senderName: senderName,
                body: message.body, attachmentUrl: message.attachmentUrl,
                attachmentType: message.attachmentType,
                latitude: message.latitude, longitude: message.longitude
            )
        case .member(let m):
            struct DMForward: Encodable {
                let sender_name: String; let recipient_name: String
                let body: String; let property_id: String?
            }
            try? await supabase.from("direct_messages").insert(
                DMForward(sender_name: senderName, recipient_name: m.name,
                          body: message.body ?? "📎", property_id: pid.uuidString)
            ).execute()
        }
        HapticFeedback.success()
    }

    func sendSticker(_ sticker: Sticker) async {
        guard let pid = propertyId else { return }
        HapticFeedback.success()
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: sticker.id, attachmentType: "sticker"
        )
    }

    func sendContact(_ formatted: String) async {
        guard let pid = propertyId else { return }
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: "👤 \(formatted)"
        )
        HapticFeedback.success()
    }

    func sendPoll(question: String, options: [String], multipleChoice: Bool) async {
        guard let pid = propertyId else { return }
        let poll = ChatPoll(q: question, opts: options, multi: multipleChoice)
        guard let body = poll.encoded() else { return }
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: body, attachmentType: "poll"
        )
        HapticFeedback.success()
    }

    func sendEvent(title: String, details: String, date: Date, location: String) async {
        guard let pid = propertyId else { return }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        let ev = ChatEvent(t: title, d: details.isEmpty ? nil : details,
                           date: f.string(from: date), loc: location.isEmpty ? nil : location)
        guard let body = ev.encoded() else { return }
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: body, attachmentType: "event"
        )
        HapticFeedback.success()
    }

    func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard let pid = propertyId, !items.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        // A caption typed in the composer is attached to the first image, then cleared.
        let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        // Send each selected item as its own message (preserves order). Images
        // and videos are both supported by the picker.
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let isQuickTime = item.supportedContentTypes.contains { $0.conforms(to: .quickTimeMovie) }
            let ext = isVideo ? (isQuickTime ? "mov" : "mp4") : "jpg"
            let contentType = isVideo ? (isQuickTime ? "video/quicktime" : "video/mp4") : "image/jpeg"
            let fileName = "\(UUID().uuidString).\(ext)"
            let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/\(fileName)"
            try? await supabase.storage.from("documents")
                .upload(filePath, data: data, options: FileOptions(contentType: contentType, upsert: false))
            let url = try? supabase.storage.from("documents").getPublicURL(path: filePath)
            try? await messageService.send(
                propertyId: pid, senderName: senderName,
                body: (index == 0 && !caption.isEmpty) ? caption : nil,
                attachmentUrl: url?.absoluteString, attachmentType: isVideo ? "video" : "image",
                mentionedIds: mentionedIds
            )
        }
        HapticFeedback.success()
        photoPickerItems = []
        mentionedIds = []; mentionedNames = []
    }

    func sendCameraPhoto(_ image: UIImage) async {
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

    func sendLocation(lat: Double, lon: Double) async {
        guard let pid = propertyId else { return }
        isSending = true
        defer { isSending = false }
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: String(localized: "📍 Shared a location"),
            attachmentType: "location", latitude: lat, longitude: lon,
            mentionedIds: mentionedIds
        )
        HapticFeedback.success()
        mentionedIds = []; mentionedNames = []
    }

    func sendAudio(url: URL) async {
        guard let pid = propertyId else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        isSending = true
        defer { isSending = false; try? FileManager.default.removeItem(at: url) }
        let fileName = "\(UUID().uuidString).m4a"
        let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/audio/\(fileName)"
        try? await supabase.storage.from("documents")
            .upload(filePath, data: data, options: FileOptions(contentType: "audio/mp4", upsert: false))
        let remoteURL = try? supabase.storage.from("documents").getPublicURL(path: filePath)
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: nil,
            attachmentUrl: remoteURL?.absoluteString, attachmentType: "audio",
            mentionedIds: []
        )
        HapticFeedback.success()
    }

    func sendFile(url: URL) async {
        guard let pid = propertyId else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        isSending = true
        defer { isSending = false }
        let fileName = "\(UUID().uuidString)_\(url.lastPathComponent)"
        let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/files/\(fileName)"
        let mime = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "application/octet-stream"
        try? await supabase.storage.from("documents")
            .upload(filePath, data: data, options: FileOptions(contentType: mime, upsert: false))
        let remoteURL = try? supabase.storage.from("documents").getPublicURL(path: filePath)
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: url.lastPathComponent,
            attachmentUrl: remoteURL?.absoluteString, attachmentType: "file",
            mentionedIds: []
        )
        HapticFeedback.success()
    }

    func scheduleLocalMentionNotifications(body: String) {
        guard !mentionedNames.isEmpty else { return }
        guard NotificationScheduler.prefEnabled(NotificationScheduler.Keys.mentions) else { return }
        let center = UNUserNotificationCenter.current()
        for name in mentionedNames {
            let content = UNMutableNotificationContent()
            content.title = String(format: String(localized: "%@ mentioned %@"), senderName, name)
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
                appBackground.ignoresSafeArea()
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
    }
}

import SwiftUI
import PhotosUI
import UserNotifications
import Supabase

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
            HapticFeedback.warning()
            sendError = String(localized: "Failed to send message. Check your connection and try again.")
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

    func sendPhoto(_ items: [PhotosPickerItem]) async {
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

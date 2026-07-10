import UserNotifications
import Intents
import UniformTypeIdentifiers

/// Enriches incoming chat pushes into WhatsApp-grade notifications before the
/// system shows them:
///
///  1. **Sender avatar on the banner** — donates an `INSendMessageIntent`
///     (Communication Notifications) built from the `chat` payload the
///     `send-chat-push` edge function attaches, so iOS renders the person's
///     photo instead of the app icon.
///  2. **Playable media in the expanded view** — voice messages and photos
///     ride as a short-lived signed URL (`media_url`); downloading them into a
///     `UNNotificationAttachment` gives the long-press/pull-down expanded
///     notification the system audio player / full-size image.
///
/// Everything here is best-effort: any failure falls back to the plain push
/// exactly as it arrived. `serviceExtensionTimeWillExpire` guarantees the
/// banner is never lost to a slow download.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent)
            ?? UNMutableNotificationContent()
        bestAttempt = content

        guard let chat = request.content.userInfo["chat"] as? [String: Any] else {
            contentHandler(content)
            return
        }

        Task {
            let enriched = await Self.enrich(content, chat: chat)
            contentHandler(enriched)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttempt { contentHandler?(bestAttempt) }
    }

    // MARK: - Enrichment

    private static func enrich(
        _ content: UNMutableNotificationContent,
        chat: [String: Any]
    ) async -> UNNotificationContent {
        // Media first: even if the communication-intent step fails, the
        // attachment alone already gives the expanded player/photo.
        if let media = chat["media_url"] as? String,
           let url = URL(string: media), url.scheme?.hasPrefix("http") == true,
           let attachment = await downloadAttachment(url, kind: chat["media_kind"] as? String) {
            content.attachments = [attachment]
        }

        let senderName = trimmedNonEmpty(chat["peer_name"] as? String)
            ?? trimmedNonEmpty(content.title)
            ?? "PRVIO"

        var avatar: INImage?
        if let raw = chat["avatar_url"] as? String,
           let url = URL(string: raw), url.scheme?.hasPrefix("http") == true,
           let data = await cachedAvatarData(url) {
            avatar = INImage(imageData: data)
        }

        // A stable per-person handle keeps iOS grouping/summarising correctly.
        let handleValue = (chat["sender_id"] as? String)
            ?? (chat["peer_user_id"] as? String)
            ?? senderName
        let sender = INPerson(
            personHandle: INPersonHandle(value: handleValue, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: handleValue
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: content.threadIdentifier.isEmpty ? handleValue : content.threadIdentifier,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        if let avatar {
            intent.setImage(avatar, forParameterNamed: \.sender)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()

        return (try? content.updating(from: intent)) ?? content
    }

    private static func trimmedNonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    // MARK: - Media attachment

    private static func downloadAttachment(_ url: URL, kind: String?) async -> UNNotificationAttachment? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }

        let (ext, utType): (String, UTType) = {
            switch kind {
            case "audio": return ("m4a", .mpeg4Audio)
            case "video": return ("mp4", .mpeg4Movie)
            default:
                let pathExt = url.pathExtension.lowercased()
                if pathExt == "png"  { return ("png", .png) }
                if pathExt == "webp" { return ("webp", .webP) }
                return ("jpg", .jpeg)
            }
        }()

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try data.write(to: file)
            return try UNNotificationAttachment(
                identifier: "chat-media",
                url: file,
                options: [UNNotificationAttachmentOptionsTypeHintKey: utType.identifier]
            )
        } catch {
            return nil
        }
    }

    // MARK: - Avatar cache

    /// Avatars change rarely; caching them in the shared app-group container
    /// makes every notification after the first render instantly and offline.
    private static func cachedAvatarData(_ url: URL) async -> Data? {
        let dir = (FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.prvio.app")
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("NotificationAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Stable filename from the URL path (queries hold rotating tokens).
        let key = url.path.unicodeScalars.reduce(into: UInt64(5381)) { hash, c in
            hash = hash &* 33 &+ UInt64(c.value)
        }
        let file = dir.appendingPathComponent("\(key).img")

        if let cached = try? Data(contentsOf: file), !cached.isEmpty {
            return cached
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              !data.isEmpty else { return nil }
        try? data.write(to: file)
        return data
    }
}

// DM message bubbles (split from DirectMessageView). `DMBubble` is a THIN
// adapter since chat unification phase 3: it maps a `DirectMessage` into
// `ChatBubbleModel` and injects the media content; all shared presentation
// (layout, quote, reactions, swipe, status row) lives in
// ChatMessageBubbleShared.
import SwiftUI
import PhotosUI
import UIKit
import Supabase

// MARK: - DM rich attachments (encoded in the body — DMs have no attachment columns)
//
// Like contact shares (see ChatContactSharing), a 1:1 thread carries structured
// attachments as a marker-prefixed body so the direct_messages table needs no
// new columns. Each marker is a sentinel no ordinary message begins with,
// followed by the payload; the bubble decodes and renders the rich variant, and
// the offline outbox re-sends the body verbatim so a queued rich message is
// never lost or corrupted. Poll is intentionally absent (there is no DM poll
// composer); event bubbles DO offer RSVP — their Going / Can't go answers
// live in `dm_poll_votes` (see DMVoteStore), the DM mirror of the group
// `message_poll_votes` table.
enum DMRich {
    case location(lat: Double, lon: Double)
    case sticker(id: String)
    case event(ChatEvent)
    case file(name: String, path: String)

    // A trailing "#" (or a leading glyph for the JSON kinds) keeps these from
    // colliding with anything a person would actually type.
    static let locationMarker = "📍#"
    static let stickerMarker  = "🎟️"
    static let eventMarker    = "🗓️"
    static let fileMarker     = "📄#"

    private struct FilePayload: Codable { let n: String; let p: String }

    static func encodeLocation(lat: Double, lon: Double) -> String {
        "\(locationMarker)\(lat),\(lon)"
    }
    // NB: stickers have no encoder — the catalog picker is gone; the case
    // remains decode-only so already-sent sticker messages keep rendering.
    static func encodeEvent(_ event: ChatEvent) -> String? {
        event.encoded().map { eventMarker + $0 }
    }
    static func encodeFile(name: String, path: String) -> String? {
        (try? JSONEncoder().encode(FilePayload(n: name, p: path)))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { fileMarker + $0 }
    }

    static func decode(_ body: String) -> DMRich? {
        if body.hasPrefix(locationMarker) {
            let parts = body.dropFirst(locationMarker.count).split(separator: ",")
            guard parts.count == 2,
                  let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
            return .location(lat: lat, lon: lon)
        }
        if body.hasPrefix(stickerMarker) {
            let id = String(body.dropFirst(stickerMarker.count))
            return id.isEmpty ? nil : .sticker(id: id)
        }
        if body.hasPrefix(eventMarker) {
            guard let event = ChatEvent.decode(String(body.dropFirst(eventMarker.count))) else { return nil }
            return .event(event)
        }
        if body.hasPrefix(fileMarker) {
            guard let data = String(body.dropFirst(fileMarker.count)).data(using: .utf8),
                  let payload = try? JSONDecoder().decode(FilePayload.self, from: data) else { return nil }
            return .file(name: payload.n, path: payload.p)
        }
        return nil
    }

    /// A faithful one-line preview for lists, pins and reply banners — never the
    /// raw marker/JSON. Returns nil when the body isn't a rich attachment.
    static func snippet(for body: String) -> String? {
        switch decode(body) {
        case .location: return String(localized: "convo_prev_location")
        case .sticker:  return String(localized: "convo_prev_sticker")
        case .event:    return String(localized: "convo_prev_event")
        case .file:     return String(localized: "convo_prev_file")
        case .none:     return nil
        }
    }
}

// MARK: - DM Bubble

struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    /// Draw the iMessage-style tail — true on the last bubble of a same-sender run.
    let hasTail: Bool
    /// First bubble of a same-sender run — anchors the sender-name label (only
    /// shown for an incoming peer who isn't a saved contact, iMessage-style).
    var isFirstInRun: Bool = true
    var myName: String = ""
    /// My auth user id — reactions key on it (names collide and drift).
    var myUserId: UUID? = nil
    var partner: FamilyMember? = nil
    /// Identity-based partner display data (ChatPeer) — wins over the roster
    /// snapshot so avatars come from the live profile.
    var partnerAvatarURL: URL? = nil
    var partnerInitials: String? = nil
    var partnerColor: Color? = nil
    var members: [FamilyMember] = []
    var myAvatarURL: URL? = nil
    var outgoingColor: Color? = nil
    var repliedMessage: DirectMessage? = nil
    var onReact: ((String) -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil
    var onMark: (() -> Void)? = nil
    var onDeleteForEveryone: (() -> Void)? = nil
    var onDeleteForMe: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    /// Tapping the quoted reply jumps to the original message.
    var onQuotedTap: (() -> Void)? = nil
    /// Briefly tinted when the reader jumped here from a reply.
    var isHighlighted: Bool = false
    /// RSVP answers for an EVENT message (DMVoteStore rows for this id);
    /// unused for every other message kind.
    var pollVotes: [PollVote] = []
    /// Going / Can't go tap — nil hides the RSVP chips entirely (EventBubble's
    /// own no-dead-controls contract).
    var onRSVP: ((Int) -> Void)? = nil

    @State private var viewerItem: ImageViewerItem? = nil
    @State private var videoItem: ImageViewerItem? = nil
    @State private var fileItem: FilePreviewItem? = nil

    private var reactionCounts: [String: Int] {
        var out: [String: Int] = [:]
        for (_, emoji) in message.reactions ?? [:] { out[emoji, default: 0] += 1 }
        return out
    }

    private var myReaction: String? { message.myReaction(myUserId: myUserId, myName: myName) }

    /// The default theme (no custom `outgoingColor`) draws the iMessage-blue
    /// gradient; a custom theme keeps its picked solid colour.
    private var usesDefaultBlue: Bool { outgoingColor == nil }
    private var ownFill: Color { outgoingColor ?? Color.imessageBlue }

    private var showsQuickForward: Bool {
        guard onForward != nil, messageType == .text else { return false }
        // Quick-forward button only on link messages.
        return firstDetectedURL(in: message.body) != nil
    }

    private enum DMMessageType { case text, image, audio, video, contacts, location, sticker, event, file, deleted }

    private var messageType: DMMessageType {
        if message.deletedForAll == true { return .deleted }
        // Rich attachments (marker-encoded in the body) win over media/text
        // classification so a shared location/sticker/event/file renders as
        // itself rather than as raw text.
        if let rich = DMRich.decode(message.body) {
            switch rich {
            case .location: return .location
            case .sticker:  return .sticker
            case .event:    return .event
            case .file:     return .file
            }
        }
        if message.isContactShare { return .contacts }
        switch ChatMedia.dmBodyKind(message.body) {
        case .audio: return .audio
        case .image: return .image
        case .video: return .video
        case .text:  return .text
        }
    }

    // MARK: Shared-renderer mapping

    private var bubbleModel: ChatBubbleModel {
        ChatBubbleModel(
            isMine: isOwn,
            hasTail: hasTail,
            isDeleted: messageType == .deleted,
            // A peer who isn't a saved contact (no roster member) gets their
            // name above the first bubble of a run — matches iMessage DMs with
            // unknown senders; saved contacts stay label-free.
            senderLabel: (!isOwn && isFirstInRun && partner == nil)
                ? message.senderName : nil,
            timeText: message.timeDisplay,
            isEdited: message.editedAt != nil,
            showsPinned: message.pinned == true,
            showsStarred: message.isMarked == true,
            tick: (isOwn && messageType != .deleted)
                ? (message.readAt != nil ? .read
                   : (message.deliveredAt != nil ? .delivered : .sent))
                : nil,
            reactions: reactionCounts,
            myReaction: myReaction,
            replyQuote: repliedMessage.map {
                ChatReplyQuote(sender: $0.senderName, snippet: $0.previewSnippet)
            },
            linkURL: messageType == .text ? firstDetectedURL(in: message.body) : nil,
            hidesStatusRow: messageType == .audio,
            accent: outgoingColor ?? Color.accentColor,
            minClearance: 72,
            edgeInset: AppSpacing.md
        )
    }

    private var bubbleActions: ChatBubbleActions {
        ChatBubbleActions(
            onReact: onReact,
            onReply: onReply,
            onQuotedTap: onQuotedTap,
            onLongPress: onLongPress,
            onQuickForward: showsQuickForward ? { onForward?() } : nil
        )
    }

    var body: some View {
        ChatMessageBubbleShared(
            model: bubbleModel,
            actions: bubbleActions,
            isHighlighted: isHighlighted,
            content: { bubbleContent }
        )
        .padding(.vertical, 1)
        .fullScreenCover(item: $viewerItem) { item in
            FullScreenImageViewer(url: item.url)
        }
        .fullScreenCover(item: $videoItem) { item in
            VideoPlayerSheet(url: item.url)
        }
        .sheet(item: $fileItem) { item in
            FilePreviewSheet(url: item.url, filename: item.name)
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch messageType {
        case .deleted:
            ChatDeletedBubbleView(isOwn: isOwn, hasTail: hasTail)
        case .audio:
            AudioBubble(
                audioValue: message.body, isOwn: isOwn,
                avatarURL: isOwn ? myAvatarURL
                    : (partnerAvatarURL ?? partner?.avatarUrl.flatMap { URL(string: $0) }),
                initials: isOwn
                    ? String(myName.prefix(2)).uppercased()
                    : (partnerInitials ?? partner?.initials
                       ?? String(message.senderName.prefix(2)).uppercased()),
                avatarColor: isOwn ? Color.accentColor
                    : (partnerColor ?? partner?.swiftColor ?? Color.gray),
                timeText: message.timeDisplay,
                tick: isOwn ? (message.readAt != nil ? .read
                               : (message.deliveredAt != nil ? .delivered : .sent)) : .none,
                bubbleColor: ownFill,
                hasTail: hasTail
            )
        case .image:
            DMImageBubble(stored: message.body, isOwn: isOwn, hasTail: hasTail) { u in
                viewerItem = ImageViewerItem(url: u)
            }
        case .video:
            // Same bubble the group chat uses — resolves the signed URL and
            // plays full-screen through VideoPlayerSheet.
            ChatVideoBubble(stored: message.body, isOwn: isOwn, hasTail: hasTail) { u in
                videoItem = ImageViewerItem(url: u)
            }
        case .contacts:
            ContactCardBubble(payloads: SharedContactPayload.decode(message.body),
                              isOwn: isOwn,
                              bubbleColor: ownFill,
                              hasTail: hasTail, members: members)
        case .location:
            if case .location(let lat, let lon) = DMRich.decode(message.body) {
                LocationBubble(lat: lat, lon: lon, isOwn: isOwn,
                               label: message.senderName, hasTail: hasTail,
                               senderId: message.senderId, sentAt: message.createdAt)
            }
        case .sticker:
            if case .sticker(let id) = DMRich.decode(message.body) {
                StickerBubble(stickerId: id)
            }
        case .event:
            if case .event(let event) = DMRich.decode(message.body) {
                EventBubble(event: event, isOwn: isOwn,
                            bubbleColor: ownFill,
                            votes: pollVotes, myUserId: myUserId, onRSVP: onRSVP)
            }
        case .file:
            if case .file(let name, let path) = DMRich.decode(message.body) {
                ChatFileBubble(stored: path, name: name, isOwn: isOwn,
                               ownBubbleColor: ownFill,
                               hasTail: hasTail) { url, filename in
                    fileItem = FilePreviewItem(url: url, name: filename)
                }
            }
        case .text:
            ChatTextBubbleView(text: message.body, isOwn: isOwn, hasTail: hasTail,
                               fill: ownFill,
                               useDefaultBlueGradient: isOwn && usesDefaultBlue)
        }
    }
}

// MARK: - DM image bubble (resolves private signed URLs; legacy URLs pass through)

struct DMImageBubble: View {
    let stored: String
    var isOwn: Bool = false
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?

    private var shape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }

    var body: some View {
        StorageImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 180)
                    .clipShape(shape)
                    .onTapGesture { if let url { onTap(url) } }
            case .failure:
                shape
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 220, height: 140)
                    .overlay(Image(systemName: "photo").foregroundStyle(Color.primary.opacity(0.3)))
            default:
                shape
                    .fill(Color.primary.opacity(AppOpacity.hairline))
                    .frame(width: 220, height: 140)
                    .overlay(ProgressView())
            }
        }
        .task(id: stored) { url = await ChatMedia.resolve(stored) }
    }
}

// (DM read-receipt tick now uses the shared MessageTick from ChatComponents.)

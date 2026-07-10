// The group-chat message bubble and its seen-by sheet (split from
// ChatComponents). A THIN adapter since chat unification phase 3: it maps the
// group `Message` into `ChatBubbleModel` and injects the media content; all
// shared presentation (layout, quote, reactions, swipe, status row) lives in
// ChatMessageBubbleShared.
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let isOwn: Bool
    let members: [FamilyMember]
    var outgoingColor: Color? = nil
    var readers: [MessageRead] = []
    var deliverers: [MessageDelivery] = []
    var onDelete: (() -> Void)? = nil
    /// Aggregated reaction counts from DB (emoji → count). When provided, overrides local state.
    var persistedReactions: [String: Int] = [:]
    /// The current user's persisted reaction, if any.
    var persistedMyReaction: String? = nil
    /// Called when user toggles a reaction emoji; nil = use local-only state.
    var onReact: ((String) -> Void)? = nil
    /// The message this one replies to (for the quoted snippet), if any.
    var repliedMessage: Message? = nil
    var onReply: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil
    var onMark: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDeleteForEveryone: (() -> Void)? = nil
    var onDeleteForMe: (() -> Void)? = nil
    var pollVotes: [PollVote] = []
    var myUserId: UUID? = nil
    var myAvatarURL: URL? = nil
    var onPollVote: ((Int) -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    /// First message of a same-sender run — shows the sender's name label.
    var isGroupStart: Bool = true
    /// Last message of a same-sender run — anchors the avatar to this bubble.
    var isGroupEnd: Bool = true
    /// Tapping the quoted reply snippet jumps to the original message.
    var onQuotedTap: (() -> Void)? = nil
    /// Briefly tinted when the reader jumped here from a reply/pin.
    var isHighlighted: Bool = false

    private var isDeleted: Bool { message.deletedForAll == true }
    private var ownBubbleColor: Color { outgoingColor ?? Color.blue.opacity(0.75) }
    private var linkURL: URL? {
        guard !isDeleted, message.attachmentType == nil, let body = message.body else { return nil }
        return firstDetectedURL(in: body)
    }

    @State private var showReaders = false
    @State private var localReactions: [String: Int] = [:]
    @State private var localMyReaction: String? = nil
    @State private var viewerItem: ImageViewerItem? = nil
    @State private var videoItem: ImageViewerItem? = nil
    @State private var filePreview: FilePreviewItem? = nil
    @State private var showDetails = false

    private var displayReactions: [String: Int] {
        onReact != nil ? persistedReactions : localReactions
    }
    private var displayMyReaction: String? {
        onReact != nil ? persistedMyReaction : localMyReaction
    }

    private var sender: FamilyMember? {
        // Messages carry the sender's display name, not a family-member id, so we
        // match by name. Compare case- and whitespace-insensitively so a member's
        // photo still resolves despite minor formatting differences.
        let target = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return members.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(target) == .orderedSame
        }
    }
    private var seen: Bool { !readers.isEmpty }
    /// 3-state tick: read (someone read) > delivered (someone received) > sent.
    private var tickStatus: MessageTick.Status {
        if !readers.isEmpty { return .read }
        if !deliverers.isEmpty { return .delivered }
        return .sent
    }

    // MARK: Shared-renderer mapping

    private var bubbleModel: ChatBubbleModel {
        ChatBubbleModel(
            isMine: isOwn,
            hasTail: isGroupEnd,
            isDeleted: isDeleted,
            senderLabel: (!isOwn && isGroupStart) ? message.senderName : nil,
            senderLabelColor: sender?.swiftColor ?? Self.color(for: message.senderName),
            timeText: message.timeDisplay,
            isEdited: message.editedAt != nil,
            showsPinned: message.pinned == true,
            showsStarred: message.isMarked == true,
            tick: (isOwn && !isDeleted) ? tickStatus : nil,
            reactions: displayReactions,
            myReaction: displayMyReaction,
            replyQuote: isDeleted ? nil : repliedMessage.map {
                ChatReplyQuote(sender: $0.senderName, snippet: Self.replyPreview($0))
            },
            linkURL: linkURL,
            hidesStatusRow: message.isAudioMessage,
            accent: outgoingColor ?? Color.accentColor,
            minClearance: 60,
            edgeInset: AppSpacing.lg
        )
    }

    private var bubbleActions: ChatBubbleActions {
        ChatBubbleActions(
            onReact: { emoji in
                if let onReact { onReact(emoji) } else { toggleLocalReaction(emoji) }
            },
            onReply: onReply,
            onQuotedTap: onQuotedTap,
            onLongPress: onLongPress,
            onDetails: { showDetails = true },
            // The seen-by sheet only opens once someone actually received it.
            onStatusTap: (isOwn && (seen || !deliverers.isEmpty)) ? { showReaders = true } : nil
        )
    }

    var body: some View {
        ChatMessageBubbleShared(
            model: bubbleModel,
            actions: bubbleActions,
            isHighlighted: isHighlighted,
            content: { bubbleContent }
        ) {
            // Avatar anchors to the last bubble of a same-sender run; earlier
            // bubbles reserve its width so they stay left-aligned with it.
            if isGroupEnd {
                chatAvatar
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .sheet(isPresented: $showReaders) {
            SeenBySheet(readers: readers, deliverers: deliverers, members: members)
        }
        .fullScreenCover(item: $viewerItem) { item in
            FullScreenImageViewer(url: item.url)
        }
        .sheet(item: $filePreview) { item in
            FilePreviewSheet(url: item.url, filename: item.name)
        }
        .fullScreenCover(item: $videoItem) { item in
            VideoPlayerSheet(url: item.url)
        }
        .sheet(isPresented: $showDetails) {
            MessageDetailsView(message: message, readers: readers, deliverers: deliverers)
        }
    }

    /// A short, human-readable preview for a replied/pinned message — checks
    /// the structured types (poll/event/attachments) before falling back to the
    /// raw body so a poll/event never shows its JSON payload.
    static func replyPreview(_ m: Message) -> String {
        if m.isPollMessage { return "📊 Poll" }
        if m.isEventMessage { return "📅 Event" }
        if m.isTaskShare { return "🧰 Task" }
        if m.isContactShare { return "👤 Contact" }
        if m.isAudioMessage { return "🎤 Voice message" }
        if m.isImageMessage { return "📷 Photo" }
        if m.isVideoMessage { return "🎥 Video" }
        if m.isLocationMessage { return "📍 Location" }
        if m.isStickerMessage { return "😀 Sticker" }
        if m.isFileMessage { return "📎 File" }
        if let b = m.body, !b.isEmpty { return b }
        return "Attachment"
    }

    private func toggleLocalReaction(_ emoji: String) {
        if localMyReaction == emoji {
            localMyReaction = nil
            if let count = localReactions[emoji] {
                if count <= 1 { localReactions.removeValue(forKey: emoji) }
                else { localReactions[emoji] = count - 1 }
            }
        } else {
            if let old = localMyReaction, let count = localReactions[old] {
                if count <= 1 { localReactions.removeValue(forKey: old) }
                else { localReactions[old] = count - 1 }
            }
            localMyReaction = emoji
            localReactions[emoji, default: 0] += 1
        }
    }

    @ViewBuilder
    private var chatAvatar: some View {
        // Resolve the best available identity for this sender. The member
        // directory (real account profiles, keyed by sender id) is the primary
        // source for the photo; the name-matched family contact is a fallback.
        // Otherwise: initials on a deterministic color derived from the name —
        // never a blank circle.
        let color = sender?.swiftColor ?? Self.color(for: message.senderName)
        let initials = sender?.initials ?? Self.initials(from: message.senderName)
        let avatarURL = MemberDirectory.shared.avatarURL(for: message.senderId)
            ?? sender?.avatarUrl.flatMap { URL(string: $0) }

        ZStack {
            Circle().fill(color.opacity(0.18))
            if let avatarURL {
                StorageImage(url: avatarURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Text(initials)
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
            } else {
                Text(initials)
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color, lineWidth: 2))
    }

    /// Initials for an arbitrary sender name (used when the sender isn't a
    /// resolvable family member — e.g. cross-app / external messages).
    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Deterministic, pleasant avatar tint from a name so unknown senders get a
    /// stable, distinguishable color instead of a gray blank.
    static func color(for name: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal,
                                 .green, .indigo, .red, .cyan, .mint]
        var hash = 5381
        for byte in name.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return palette[abs(hash) % palette.count]
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isDeleted {
            ChatDeletedBubbleView(isOwn: isOwn, hasTail: isGroupEnd)
        } else if message.isPollMessage, let poll = ChatPoll.decode(message.body) {
            PollBubble(poll: poll, votes: pollVotes, myUserId: myUserId, isOwn: isOwn,
                       bubbleColor: ownBubbleColor, onVote: { onPollVote?($0) })
        } else if message.isEventMessage, let event = ChatEvent.decode(message.body) {
            EventBubble(event: event, isOwn: isOwn, bubbleColor: ownBubbleColor)
        } else if message.isTaskShare, let sharedTask = SharedTaskPayload.decode(message.body) {
            TaskCardBubble(payload: sharedTask, isOwn: isOwn,
                           bubbleColor: ownBubbleColor, hasTail: isGroupEnd)
        } else if message.isContactShare {
            ContactCardBubble(payloads: SharedContactPayload.decode(message.body),
                              isOwn: isOwn, bubbleColor: ownBubbleColor,
                              hasTail: isGroupEnd, members: members)
        } else if message.isStickerMessage, let stickerId = message.body {
            StickerBubble(stickerId: stickerId)
        } else if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
            LocationBubble(lat: lat, lon: lon, isOwn: isOwn, label: message.senderName,
                           hasTail: isGroupEnd, senderId: message.senderId,
                           sentAt: message.createdAt)
        } else if message.isAudioMessage, let urlStr = message.attachmentUrl {
            AudioBubble(
                audioValue: urlStr, isOwn: isOwn,
                avatarURL: isOwn ? myAvatarURL : sender?.avatarUrl.flatMap { URL(string: $0) },
                initials: sender?.initials ?? String(message.senderName.prefix(2)).uppercased(),
                avatarColor: sender?.swiftColor ?? Color.gray,
                timeText: message.timeDisplay,
                tick: isOwn ? (tickStatus == .read ? .read : (tickStatus == .delivered ? .delivered : .sent)) : .none,
                bubbleColor: ownBubbleColor,
                hasTail: isGroupEnd
            )
        } else if message.isFileMessage {
            ChatFileBubble(stored: message.attachmentUrl, name: message.body,
                           isOwn: isOwn, ownBubbleColor: ownBubbleColor, hasTail: isGroupEnd) { u, n in
                filePreview = FilePreviewItem(url: u, name: n)
            }
        } else if message.isImageMessage, let urlStr = message.attachmentUrl {
            ChatImageBubble(stored: urlStr, caption: message.body, isOwn: isOwn,
                            ownBubbleColor: ownBubbleColor, hasTail: isGroupEnd) { resolved in
                viewerItem = ImageViewerItem(url: resolved)
            }
        } else if message.isVideoMessage, let urlStr = message.attachmentUrl {
            ChatVideoBubble(stored: urlStr, isOwn: isOwn, hasTail: isGroupEnd) { resolved in videoItem = ImageViewerItem(url: resolved) }
        } else {
            ChatTextBubbleView(text: message.body ?? "", isOwn: isOwn,
                               hasTail: isGroupEnd, fill: ownBubbleColor)
        }
    }
}

// MARK: - Seen By Sheet

private struct SeenBySheet: View {
    let readers: [MessageRead]
    var deliverers: [MessageDelivery] = []
    let members: [FamilyMember]
    @Environment(\.dismiss) private var dismiss

    private func member(for name: String) -> FamilyMember? {
        members.first { $0.name == name }
    }

    /// Members who received the message but have not read it yet.
    private var deliveredOnly: [MessageDelivery] {
        let readerNames = Set(readers.map { $0.readerName })
        return deliverers
            .filter { !readerNames.contains($0.delivererName) }
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(readers.sorted { $0.readAt > $1.readAt }) { read in
                            HStack(spacing: 12) {
                                avatar(for: read)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(read.readerName.isEmpty ? "Member" : read.readerName)
                                        .font(AppFont.subheadline)
                                        .foregroundStyle(.primary)
                                    Text("Seen \(read.readTimeDisplay)")
                                        .font(AppFont.scaled(12))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                }
                                Spacer()
                                Image(systemName: "checkmark.seal.fill")
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if !deliveredOnly.isEmpty {
                            HStack {
                                Text("Delivered")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                Spacer()
                            }
                            .padding(.top, AppSpacing.xs)
                            ForEach(deliveredOnly) { d in
                                HStack(spacing: 12) {
                                    Text(d.delivererName.isEmpty ? "Member" : d.delivererName)
                                        .font(AppFont.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .font(AppFont.scaled(14, weight: .bold))
                                        .foregroundStyle(Color.primary.opacity(0.4))
                                }
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Seen by \(readers.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    @ViewBuilder
    private func avatar(for read: MessageRead) -> some View {
        let m = member(for: read.readerName)
        let color = m?.swiftColor ?? .blue
        ZStack {
            Circle().fill(color.opacity(0.2))
            Text(m?.initials ?? String(read.readerName.prefix(1)).uppercased())
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 38, height: 38)
        .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
    }
}

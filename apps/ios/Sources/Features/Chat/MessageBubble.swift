// The group-chat message bubble and its seen-by sheet (split from
// ChatComponents).
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Message Bubble

/// The bubble's frame within the row, so the swipe glyphs can center on the
/// bubble itself rather than on the (name + quote + timestamp) row.
private struct BubbleFrameKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

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
    /// Foreground for content inside the own bubble — tracks the theme colour's
    /// luminance so a light custom bubble gets dark text, not invisible white.
    private var ownTextColor: Color { ownBubbleColor.readableText }
    /// Speech-bubble background; the tail is drawn only on the last bubble of a
    /// same-sender group so a run reads as one block ending in a single tail.
    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(isOwn: isOwn, hasTail: isGroupEnd)
    }

    private var showsQuickForward: Bool {
        // Forwarding is available only from the long-press menu — no inline arrow.
        return false
    }

    private var forwardButton: some View {
        Button { onForward?() } label: {
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.6))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel("Forward")
    }
    private var linkURL: URL? {
        guard !isDeleted, message.attachmentType == nil, let body = message.body else { return nil }
        return firstDetectedURL(in: body)
    }

    @State private var showReaders = false
    @State private var localReactions: [String: Int] = [:]
    @State private var localMyReaction: String? = nil
    @State private var showReactionPicker = false
    @State private var swipeOffset: CGFloat = 0
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

    private static let reactionEmojis = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

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

    // Swipe affordance, pinned to a screen edge (WhatsApp-style) but centered
    // on the BUBBLE's vertical middle — the row also contains the sender name,
    // a quoted reply and the timestamp, so centering on the row dropped the
    // glyph next to the timestamp whenever a quote made the row tall. The
    // bubble reports its frame through an anchor preference and the glyph is
    // positioned at its midY.
    @ViewBuilder private func swipeIndicator(in geo: GeometryProxy,
                                             bubble: Anchor<CGRect>?) -> some View {
        let midY = bubble.map { geo[$0].midY } ?? geo.size.height / 2
        if swipeOffset > 12 {
            let progress = min(1, (swipeOffset - 12) / 60)
            swipeGlyph("arrowshape.turn.up.left.fill", progress: progress)
                .position(x: AppSpacing.lg + 17, y: midY)
                .allowsHitTesting(false)
        } else if swipeOffset < -12 {
            let progress = min(1, (-swipeOffset - 12) / 60)
            swipeGlyph("info.circle.fill", progress: progress)
                .position(x: geo.size.width - AppSpacing.lg - 17, y: midY)
                .allowsHitTesting(false)
        }
    }

    private func swipeGlyph(_ symbol: String, progress: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(AppOpacity.hairline))
                .frame(width: 34, height: 34)
            Image(systemName: symbol)
                .font(AppFont.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .scaleEffect(0.55 + 0.45 * progress)
        .opacity(Double(progress))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 60)
                if showsQuickForward { forwardButton }
            } else {
                // Avatar anchors to the last bubble of a same-sender run; earlier
                // bubbles reserve its width so they stay left-aligned with it.
                if isGroupEnd {
                    chatAvatar
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn, isGroupStart {
                    Text(message.senderName)
                        .font(AppFont.label)
                        .foregroundStyle(sender?.swiftColor ?? Self.color(for: message.senderName))
                        .padding(.leading, AppSpacing.xxs)
                }
                if let replied = repliedMessage, !isDeleted {
                    quotedReply(replied)
                        .contentShape(Rectangle())
                        .onTapGesture { onQuotedTap?() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Jump to the replied message")
                }
                bubbleContent
                    // The swipe glyph centers on this frame (see swipeIndicator).
                    .anchorPreference(key: BubbleFrameKey.self, value: .bounds) { $0 }
                    // Brief accent wash when the reader jumped here from a reply.
                    .overlay {
                        if isHighlighted {
                            bubbleShape.fill(Color.accentColor.opacity(0.28))
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: isHighlighted)
                    // Reactions float over the bubble's bottom-sender corner; the
                    // bottom padding reserves the overhang so they don't collide
                    // with the timestamp row below.
                    .overlay(alignment: isOwn ? .bottomTrailing : .bottomLeading) {
                        if !displayReactions.isEmpty, !isDeleted {
                            reactionPills.offset(x: isOwn ? -6 : 6, y: 12)
                        }
                    }
                    .padding(.bottom, (!displayReactions.isEmpty && !isDeleted) ? 14 : 0)
                    .offset(x: swipeOffset)
                    .onLongPressGesture(minimumDuration: 0.3) {
                        HapticFeedback.impact(.medium)
                        onLongPress?()
                    }
                if let link = linkURL {
                    LinkPreviewView(url: link)
                }
                // Audio bubbles render their own time + ticks inside.
                if !message.isAudioMessage { statusRow }
            }

            if !isOwn {
                if showsQuickForward { forwardButton }
                Spacer(minLength: 60)
            }
        }
        .contentShape(Rectangle())
        .overlayPreferenceValue(BubbleFrameKey.self) { anchor in
            GeometryReader { geo in
                swipeIndicator(in: geo, bubble: anchor)
            }
            .allowsHitTesting(false)
        }
        .simultaneousGesture(
            // Only a decisively horizontal drag engages the reply/details swipe;
            // anything with real vertical travel is left to the scroll view, so
            // scrolling with a finger on a bubble never nudges it or fires a reply.
            DragGesture(minimumDistance: 24)
                .onChanged { v in
                    guard !isDeleted else { return }
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    // Track past the activation distance so the bubble doesn't jump.
                    let w = v.translation.width
                    swipeOffset = max(-90, min(90, w > 0 ? w - 24 : w + 24))
                }
                .onEnded { v in
                    guard !isDeleted else { return }
                    let horizontal = abs(v.translation.width) > abs(v.translation.height) * 2
                    if horizontal, v.translation.width > 72 { onReply?(); HapticFeedback.impact(.light) }
                    else if horizontal, v.translation.width < -90 { showDetails = true; HapticFeedback.impact(.light) }
                    withAnimation(.spring(response: 0.3)) { swipeOffset = 0 }
                }
        )
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
            MessageDetailsView(message: message, readers: readers)
        }
        .sheet(isPresented: $showReactionPicker) {
            ReactionPickerView(myReaction: displayMyReaction) { emoji in
                if let onReact {
                    onReact(emoji)
                } else {
                    toggleLocalReaction(emoji)
                }
            }
            .presentationDetents([.height(100)])
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if !isDeleted {
            ForEach(Self.reactionEmojis, id: \.self) { emoji in
                Button {
                    if let onReact { onReact(emoji) } else { toggleLocalReaction(emoji) }
                } label: { Text(emoji) }
            }
            Divider()
            if let onReply {
                Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            }
            if let onForward {
                Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            }
            if message.attachmentType == nil, let body = message.body, !body.isEmpty {
                Button { UIPasteboard.general.string = body } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            if isOwn, message.body?.isEmpty == false, message.attachmentType == nil, let onEdit {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            Button { showDetails = true } label: {
                Label("Details", systemImage: "info.circle")
            }
            if let onMark {
                Button { onMark() } label: {
                    Label(message.isMarked == true ? "Unmark" : "Mark", systemImage: "flag")
                }
            }
            if let onPin {
                Button { onPin() } label: {
                    Label(message.pinned == true ? "Unpin" : "Pin", systemImage: "pin")
                }
            }
            Divider()
        }
        if isOwn, let onDeleteForEveryone, !isDeleted {
            Button(role: .destructive) { onDeleteForEveryone() } label: {
                Label("Delete for everyone", systemImage: "trash")
            }
        }
        if let onDeleteForMe {
            Button(role: .destructive) { onDeleteForMe() } label: {
                Label("Delete for me", systemImage: "trash.slash")
            }
        } else if isOwn, let onDelete, isDeleted == false, onDeleteForEveryone == nil {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func quotedReply(_ replied: Message) -> some View {
        let accent = outgoingColor ?? Color.accentColor
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5).fill(accent).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(replied.senderName)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(accent)
                Text(Self.replyPreview(replied))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .frame(maxWidth: 250, alignment: .leading)
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

    /// A single floating capsule of reactions that straddles the bubble's
    /// bottom edge (see the overlay in `body`), rather than a separate row
    /// underneath — the WhatsApp/iMessage placement. The reader's own reaction
    /// gets a subtle accent chip inside the cluster.
    private var reactionPills: some View {
        HStack(spacing: 3) {
            ForEach(Array(displayReactions.sorted(by: { $0.key < $1.key })), id: \.key) { emoji, count in
                Button {
                    if let onReact { onReact(emoji) } else { toggleLocalReaction(emoji) }
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(.system(size: 13))
                        if count > 1 {
                            Text("\(count)").font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(displayMyReaction == emoji ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(format: String(localized: "Reaction %@"), emoji)))
                .accessibilityValue(count > 1 ? Text("\(count)") : Text(""))
                .accessibilityAddTraits(displayMyReaction == emoji ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
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
    private var statusRow: some View {
        if isOwn {
            Button {
                if seen || !deliverers.isEmpty { showReaders = true }
            } label: {
                HStack(spacing: 4) {
                    Text(message.timeDisplay)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.3))
                    if message.editedAt != nil, !isDeleted {
                        Text("· edited")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.3))
                    }
                    if !isDeleted { MessageTick(status: tickStatus) }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
            .buttonStyle(.plain)
            .disabled(!seen && deliverers.isEmpty)
        } else {
            HStack(spacing: 4) {
                Text(message.timeDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.3))
                if message.editedAt != nil, !isDeleted {
                    Text("· edited")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
            .padding(.horizontal, AppSpacing.xxs)
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
            } else {
                Text(initials)
                    .font(.system(size: 11, weight: .bold))
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
            HStack(spacing: 6) {
                Image(systemName: "slash.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.4))
                Text("This message was deleted")
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
            .background(Color.primary.opacity(AppOpacity.hairline), in: bubbleShape)
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
            Text(message.body ?? "")
                .font(.system(size: 15))
                .foregroundStyle(isOwn ? ownTextColor : .primary)
                .tint(isOwn ? ownTextColor : Color.accentColor)
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                .background(isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
                            in: bubbleShape)
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
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                }
                                Spacer()
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 16))
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
                                        .font(.system(size: 14, weight: .bold))
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 38, height: 38)
        .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
    }
}

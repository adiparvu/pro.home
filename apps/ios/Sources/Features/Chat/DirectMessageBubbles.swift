// DM message bubbles (split from DirectMessageView).
import SwiftUI
import PhotosUI
import UIKit
import Supabase

// MARK: - DM Bubble

struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    /// Draw the iMessage-style tail — true on the last bubble of a same-sender run.
    let hasTail: Bool
    var myName: String = ""
    var partner: FamilyMember? = nil
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

    @State private var swipeOffset: CGFloat = 0
    @State private var showDetails = false
    @State private var viewerItem: ImageViewerItem? = nil
    @State private var videoItem: ImageViewerItem? = nil

    private var reactionCounts: [String: Int] {
        var out: [String: Int] = [:]
        for (_, emoji) in message.reactions ?? [:] { out[emoji, default: 0] += 1 }
        return out
    }

    /// Speech-bubble background; tail only on the last bubble of a run.
    private var bubbleShape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }
    private var myReaction: String? { message.reactions?[myName] }

    private var showsQuickForward: Bool {
        guard onForward != nil, messageType == .text else { return false }
        // Quick-forward button only on link messages.
        return firstDetectedURL(in: message.body) != nil
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

    private enum DMMessageType { case text, image, audio, video, contacts, deleted }

    private var messageType: DMMessageType {
        if message.deletedForAll == true { return .deleted }
        if message.isContactShare { return .contacts }
        switch ChatMedia.dmBodyKind(message.body) {
        case .audio: return .audio
        case .image: return .image
        case .video: return .video
        case .text:  return .text
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isOwn {
                Spacer(minLength: 72)
                if showsQuickForward { forwardButton }
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if let replied = repliedMessage, messageType != .deleted {
                    quotedReply(replied)
                        .contentShape(Rectangle())
                        .onTapGesture { onQuotedTap?() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Jump to the replied message")
                }

                Group {
                    switch messageType {
                    case .deleted: deletedBubble
                    case .audio:
                        AudioBubble(
                            audioValue: message.body, isOwn: isOwn,
                            avatarURL: isOwn ? myAvatarURL : partner?.avatarUrl.flatMap { URL(string: $0) },
                            initials: isOwn
                                ? String(myName.prefix(2)).uppercased()
                                : (partner?.initials ?? String(message.senderName.prefix(2)).uppercased()),
                            avatarColor: isOwn ? Color.accentColor : (partner?.swiftColor ?? Color.gray),
                            timeText: message.timeDisplay,
                            tick: isOwn ? (message.readAt != nil ? .read
                                           : (message.deliveredAt != nil ? .delivered : .sent)) : .none,
                            bubbleColor: outgoingColor ?? Color.accentColor,
                            hasTail: hasTail
                        )
                    case .image: imageBubble
                    case .video: videoBubble
                    case .contacts:
                        ContactCardBubble(payloads: SharedContactPayload.decode(message.body),
                                          isOwn: isOwn,
                                          bubbleColor: outgoingColor ?? Color.accentColor,
                                          hasTail: hasTail, members: members)
                    case .text:  textBubble
                    }
                }
                // Brief accent wash when the reader jumped here from a reply.
                .overlay {
                    if isHighlighted {
                        bubbleShape.fill(Color.accentColor.opacity(0.28))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isHighlighted)
                // Reactions float over the bubble's bottom-sender corner; bottom
                // padding reserves the overhang so the timestamp row clears it.
                .overlay(alignment: isOwn ? .bottomTrailing : .bottomLeading) {
                    if !reactionCounts.isEmpty, messageType != .deleted {
                        reactionPills.offset(x: isOwn ? -6 : 6, y: 12)
                    }
                }
                .padding(.bottom, (!reactionCounts.isEmpty && messageType != .deleted) ? 14 : 0)
                .offset(x: swipeOffset)
                .overlay(alignment: isOwn ? .trailing : .leading) {
                    if abs(swipeOffset) > 12 {
                        Image(systemName: swipeOffset > 0 ? "arrowshape.turn.up.left.fill" : "info.circle.fill")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .offset(x: swipeOffset > 0 ? -28 : 28)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.22) {
                    HapticFeedback.impact(.medium)
                    onLongPress?()
                }

                if messageType == .text, let link = firstDetectedURL(in: message.body) {
                    LinkPreviewView(url: link)
                }

                // Audio bubbles render their own time + ticks inside.
                if messageType != .audio { statusRow }
            }

            if !isOwn {
                if showsQuickForward { forwardButton }
                Spacer(minLength: 72)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .simultaneousGesture(swipeGesture)
        .sheet(isPresented: $showDetails) {
            DMMessageDetailsView(message: message, isOwn: isOwn)
        }
        .fullScreenCover(item: $viewerItem) { item in
            FullScreenImageViewer(url: item.url)
        }
        .fullScreenCover(item: $videoItem) { item in
            VideoPlayerSheet(url: item.url)
        }
    }

    private var swipeGesture: some Gesture {
        // Only a decisively horizontal drag engages reply/details; vertical
        // travel is left to the scroll view so scrolling on a bubble works.
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                guard messageType != .deleted else { return }
                guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                let w = v.translation.width
                swipeOffset = max(-90, min(90, w > 0 ? w - 24 : w + 24))
            }
            .onEnded { v in
                guard messageType != .deleted else { return }
                let horizontal = abs(v.translation.width) > abs(v.translation.height) * 2
                if horizontal, v.translation.width > 72 { onReply?(); HapticFeedback.impact(.light) }
                else if horizontal, v.translation.width < -90 { showDetails = true; HapticFeedback.impact(.light) }
                withAnimation(.spring(response: 0.3)) { swipeOffset = 0 }
            }
    }

    /// Floating reaction cluster that straddles the bubble's bottom edge (see
    /// the overlay in `body`) — matches the group chat's placement.
    private var reactionPills: some View {
        HStack(spacing: 3) {
            ForEach(Array(reactionCounts.sorted(by: { $0.key < $1.key })), id: \.key) { emoji, count in
                Button {
                    onReact?(emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(AppFont.scaled(13))
                        if count > 1 {
                            Text("\(count)").font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(myReaction == emoji ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(format: String(localized: "Reaction %@"), emoji)))
                .accessibilityValue(count > 1 ? Text("\(count)") : Text(""))
                .accessibilityAddTraits(myReaction == emoji ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            Text(message.timeDisplay)
                .font(AppFont.scaled(10))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            if message.editedAt != nil, messageType != .deleted {
                Text("· edited")
                    .font(AppFont.scaled(10))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            if message.pinned == true {
                Image(systemName: "pin.fill")
                    .font(AppFont.scaled(8))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            if message.isMarked == true {
                Image(systemName: "flag.fill")
                    .font(AppFont.scaled(8))
                    .foregroundStyle(.orange.opacity(0.7))
            }
            if isOwn, messageType != .deleted {
                MessageTick(status: message.readAt != nil ? .read
                                    : (message.deliveredAt != nil ? .delivered : .sent))
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func quotedReply(_ replied: DirectMessage) -> some View {
        let preview: String = {
            if replied.deletedForAll == true { return "This message was deleted" }
            switch ChatMedia.dmBodyKind(replied.body) {
            case .audio: return String(localized: "dm_prev_audio")
            case .image: return String(localized: "dm_prev_photo")
            case .video: return String(localized: "dm_prev_video")
            case .text:  return replied.body
            }
        }()
        let accent = outgoingColor ?? Color.accentColor
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(replied.senderName)
                    .font(AppFont.label)
                    .foregroundStyle(accent)
                Text(preview)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 5)
        .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .frame(maxWidth: 240, alignment: .leading)
    }

    private var deletedBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "slash.circle")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(0.4))
            Text("This message was deleted")
                .font(AppFont.scaled(14))
                .italic()
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(Color.primary.opacity(AppOpacity.hairline), in: bubbleShape)
    }

    private var textBubble: some View {
        let fill = outgoingColor ?? Color.accentColor
        // Foreground tracks the bubble colour's luminance so a light custom
        // theme colour gets dark text instead of unreadable white.
        return Text(message.body)
            .font(AppFont.scaled(15))
            .foregroundStyle(isOwn ? fill.readableText : .primary)
            .tint(isOwn ? fill.readableText : Color.accentColor)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            // Incoming bubbles use an OPAQUE system fill (like iMessage) so they
            // stay legible over any wallpaper; a translucent tint vanished
            // against photo backgrounds. Opaque, it also satisfies Reduce
            // Transparency.
            .background(
                isOwn ? fill : Color(.secondarySystemBackground),
                in: bubbleShape
            )
            .clipShape(bubbleShape)
    }

    private var imageBubble: some View {
        DMImageBubble(stored: message.body, isOwn: isOwn, hasTail: hasTail) { u in viewerItem = ImageViewerItem(url: u) }
    }

    private var videoBubble: some View {
        // Same bubble the group chat uses — resolves the signed URL and plays
        // full-screen through VideoPlayerSheet.
        ChatVideoBubble(stored: message.body, isOwn: isOwn, hasTail: hasTail) { u in videoItem = ImageViewerItem(url: u) }
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

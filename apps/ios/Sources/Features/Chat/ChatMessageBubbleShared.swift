// The ONE message-bubble renderer shared by both chat engines. The group
// chat's MessageBubble and the DM thread's DMBubble used to duplicate the
// whole presentation layer — row layout and spacers, sender label, quoted
// reply, reaction cluster, highlight wash, swipe-to-reply/details, link
// preview, the time/edited/pinned/starred/ticks status row, and the deleted
// and plain-text bubbles. Both are now thin adapters that map their models
// into `ChatBubbleModel` and inject only their media content; everything
// visual lives here once.
import SwiftUI

// MARK: - Abstraction

/// The quoted message a bubble replies to.
struct ChatReplyQuote {
    let sender: String
    let snippet: String
}

/// Everything the shared renderer needs to draw a bubble row, independent of
/// the underlying message model (group `Message` or `DirectMessage`).
struct ChatBubbleModel {
    var isMine: Bool
    /// iMessage-style tail — true on the last bubble of a same-sender run.
    var hasTail: Bool = true
    var isDeleted: Bool = false
    /// Sender name label above the bubble (group incoming, first of a run).
    var senderLabel: String? = nil
    var senderLabelColor: Color = .accentColor
    var timeText: String = ""
    var isEdited: Bool = false
    var showsPinned: Bool = false
    var showsStarred: Bool = false
    /// Delivery tick for own messages; nil hides it (incoming / deleted).
    var tick: MessageTick.Status? = nil
    /// Aggregated reactions (emoji → count) floating over the bubble edge.
    var reactions: [String: Int] = [:]
    /// The reader's own reaction — its pill gets the accent chip.
    var myReaction: String? = nil
    var replyQuote: ChatReplyQuote? = nil
    /// First URL in a text body — renders the link-preview card below.
    var linkURL: URL? = nil
    /// Audio bubbles draw their own time + ticks inside — hides the row.
    var hidesStatusRow: Bool = false
    /// Theme accent for the quoted-reply bar (the outgoing bubble colour).
    var accent: Color = .accentColor
    /// Minimum clearance kept on the opposite side of the bubble.
    var minClearance: CGFloat = 60
    /// Screen-edge inset the swipe glyphs center on.
    var edgeInset: CGFloat = AppSpacing.lg
}

/// Optional interactions; a nil closure disables its affordance.
struct ChatBubbleActions {
    var onReact: ((String) -> Void)? = nil
    /// Swipe right past the threshold.
    var onReply: (() -> Void)? = nil
    var onQuotedTap: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    /// Swipe left past the threshold (message details).
    var onDetails: (() -> Void)? = nil
    /// Tap on an own message's status row (group: the seen-by sheet).
    var onStatusTap: (() -> Void)? = nil
    /// Quick-forward glass button beside the bubble (DM link messages).
    var onQuickForward: (() -> Void)? = nil
}

// MARK: - Bubble frame preference

/// The bubble's frame within the row, so the swipe glyphs can center on the
/// bubble itself rather than on the (name + quote + timestamp) row.
private struct SharedBubbleFrameKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Shared bubble row

struct ChatMessageBubbleShared<Content: View, Leading: View>: View {
    let model: ChatBubbleModel
    var actions = ChatBubbleActions()
    /// Briefly tinted when the reader jumped here from a reply/pin.
    var isHighlighted: Bool = false
    /// The bubble itself — text, media, poll, sticker… (adapter-provided).
    @ViewBuilder let content: () -> Content
    /// Column before an incoming bubble (the group avatar); EmptyView for DM.
    @ViewBuilder let leading: () -> Leading

    @State private var swipeOffset: CGFloat = 0

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(isOwn: model.isMine, hasTail: model.hasTail)
    }
    private var showsReactions: Bool { !model.reactions.isEmpty && !model.isDeleted }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if model.isMine {
                Spacer(minLength: model.minClearance)
                if actions.onQuickForward != nil { forwardButton }
            } else {
                leading()
            }

            VStack(alignment: model.isMine ? .trailing : .leading, spacing: 3) {
                if let name = model.senderLabel {
                    Text(name)
                        .font(AppFont.label)
                        .foregroundStyle(model.senderLabelColor)
                        .padding(.leading, AppSpacing.xxs)
                }
                if let quote = model.replyQuote, !model.isDeleted {
                    quotedReply(quote)
                        .contentShape(Rectangle())
                        .onTapGesture { actions.onQuotedTap?() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Jump to the replied message")
                }
                content()
                    // The swipe glyph centers on this frame (see swipeIndicator).
                    .anchorPreference(key: SharedBubbleFrameKey.self, value: .bounds) { $0 }
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
                    .overlay(alignment: model.isMine ? .bottomTrailing : .bottomLeading) {
                        if showsReactions {
                            reactionPills.offset(x: model.isMine ? -6 : 6, y: 12)
                        }
                    }
                    .padding(.bottom, showsReactions ? 14 : 0)
                    .offset(x: swipeOffset)
                    .onLongPressGesture(minimumDuration: 0.25) {
                        HapticFeedback.impact(.medium)
                        actions.onLongPress?()
                    }
                if let link = model.linkURL {
                    LinkPreviewView(url: link)
                }
                // Audio bubbles render their own time + ticks inside.
                if !model.hidesStatusRow { statusRow }
            }

            if !model.isMine {
                if actions.onQuickForward != nil { forwardButton }
                Spacer(minLength: model.minClearance)
            }
        }
        .contentShape(Rectangle())
        .overlayPreferenceValue(SharedBubbleFrameKey.self) { anchor in
            GeometryReader { geo in
                swipeIndicator(in: geo, bubble: anchor)
            }
            .allowsHitTesting(false)
        }
        .simultaneousGesture(swipeGesture)
    }

    // MARK: Swipe (reply / details)

    private var swipeGesture: some Gesture {
        // Only a decisively horizontal drag engages the reply/details swipe;
        // anything with real vertical travel is left to the scroll view, so
        // scrolling with a finger on a bubble never nudges it or fires a reply.
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                guard !model.isDeleted else { return }
                guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                // Track past the activation distance so the bubble doesn't jump.
                let w = v.translation.width
                swipeOffset = max(-90, min(90, w > 0 ? w - 24 : w + 24))
            }
            .onEnded { v in
                guard !model.isDeleted else { return }
                let horizontal = abs(v.translation.width) > abs(v.translation.height) * 2
                if horizontal, v.translation.width > 72 {
                    actions.onReply?(); HapticFeedback.impact(.light)
                } else if horizontal, v.translation.width < -90 {
                    actions.onDetails?(); HapticFeedback.impact(.light)
                }
                withAnimation(.spring(response: 0.3)) { swipeOffset = 0 }
            }
    }

    // Swipe affordance, pinned to a screen edge (WhatsApp-style) but centered
    // on the BUBBLE's vertical middle — the row can also contain the sender
    // name, a quoted reply and the timestamp, so centering on the row dropped
    // the glyph next to the timestamp whenever a quote made the row tall.
    @ViewBuilder private func swipeIndicator(in geo: GeometryProxy,
                                             bubble: Anchor<CGRect>?) -> some View {
        let midY = bubble.map { geo[$0].midY } ?? geo.size.height / 2
        if swipeOffset > 12 {
            let progress = min(1, (swipeOffset - 12) / 60)
            swipeGlyph("arrowshape.turn.up.left.fill", progress: progress)
                .position(x: model.edgeInset + 17, y: midY)
                .allowsHitTesting(false)
        } else if swipeOffset < -12 {
            let progress = min(1, (-swipeOffset - 12) / 60)
            swipeGlyph("info.circle.fill", progress: progress)
                .position(x: geo.size.width - model.edgeInset - 17, y: midY)
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

    // MARK: Pieces

    private var forwardButton: some View {
        Button { actions.onQuickForward?() } label: {
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.6))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel("Forward")
    }

    private func quotedReply(_ quote: ChatReplyQuote) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5).fill(model.accent).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.sender)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(model.accent)
                Text(quote.snippet)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(AppOpacity.hairline),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .frame(maxWidth: 250, alignment: .leading)
    }

    /// A single floating capsule of reactions that straddles the bubble's
    /// bottom edge (see the overlay in `body`) — the WhatsApp/iMessage
    /// placement. The reader's own reaction gets a subtle accent chip.
    private var reactionPills: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.reactions.sorted(by: { $0.key < $1.key })), id: \.key) { emoji, count in
                Button {
                    actions.onReact?(emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(AppFont.scaled(13))
                        if count > 1 {
                            Text("\(count)").font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(model.myReaction == emoji ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(format: String(localized: "Reaction %@"), emoji)))
                .accessibilityValue(count > 1 ? Text("\(count)") : Text(""))
                .accessibilityAddTraits(model.myReaction == emoji ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
    }

    /// time · edited · pinned/starred glyphs · delivery ticks. Own messages
    /// with an `onStatusTap` (group seen-by sheet) wrap the row in a button.
    @ViewBuilder private var statusRow: some View {
        if model.isMine, let onStatusTap = actions.onStatusTap {
            Button(action: onStatusTap) { statusRowContent }
                .buttonStyle(.plain)
        } else {
            statusRowContent
        }
    }

    private var statusRowContent: some View {
        HStack(spacing: 4) {
            Text(model.timeText)
                .font(AppFont.scaled(10))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            if model.isEdited, !model.isDeleted {
                Text("· edited")
                    .font(AppFont.scaled(10))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            if model.showsPinned {
                Image(systemName: "pin.fill")
                    .font(AppFont.scaled(8))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            if model.showsStarred {
                Image(systemName: "flag.fill")
                    .font(AppFont.scaled(8))
                    .foregroundStyle(.orange.opacity(0.7))
            }
            if let tick = model.tick, !model.isDeleted {
                MessageTick(status: tick)
            }
        }
        .padding(.horizontal, AppSpacing.xxs)
    }
}

extension ChatMessageBubbleShared where Leading == EmptyView {
    /// Convenience for surfaces without a leading avatar column (the DM).
    init(model: ChatBubbleModel,
         actions: ChatBubbleActions = ChatBubbleActions(),
         isHighlighted: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(model: model, actions: actions, isHighlighted: isHighlighted,
                  content: content) { EmptyView() }
    }
}

// MARK: - Shared bubble content pieces

/// The "This message was deleted" tombstone bubble.
struct ChatDeletedBubbleView: View {
    let isOwn: Bool
    var hasTail: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "slash.circle")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(0.4))
            Text("This message was deleted")
                .font(AppFont.scaled(15))
                .italic()
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
        .background(Color.primary.opacity(AppOpacity.hairline),
                    in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
    }
}

/// The plain-text bubble: coloured for own messages, opaque system fill for
/// incoming (like iMessage) so it stays legible over any wallpaper — a
/// translucent tint vanished against photo backgrounds, and opaque by
/// construction it also satisfies Reduce Transparency. The foreground tracks
/// the fill's luminance so a light custom theme colour gets dark text.
struct ChatTextBubbleView: View {
    let text: String
    let isOwn: Bool
    var hasTail: Bool = true
    /// Own-bubble fill — driven by the selected chat theme.
    var fill: Color = .accentColor

    var body: some View {
        // A subject-bearing body (see MessageSubject) renders iMessage-style:
        // the subject as a semibold title line above the message text, in one
        // bubble. Marker-free bodies — every pre-existing message — take the
        // single-Text path unchanged.
        let parts = MessageSubject.parse(text)
        VStack(alignment: .leading, spacing: 1) {
            if let subject = parts.subject {
                Text(subject)
                    .font(AppFont.scaled(15, weight: .semibold))
            }
            if parts.subject == nil || !parts.text.isEmpty {
                Text(parts.text)
                    .font(AppFont.scaled(15))
            }
        }
        .foregroundStyle(isOwn ? fill.readableText : .primary)
        .tint(isOwn ? fill.readableText : Color.accentColor)
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
        .background(isOwn ? fill : Color(.secondarySystemBackground),
                    in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
    }
}

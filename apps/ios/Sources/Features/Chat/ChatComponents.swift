import SwiftUI
import MapKit
import CoreLocation

// MARK: - Camera picker

struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Call picker sheet

struct CallPickerSheet: View {
    let members: [FamilyMember]
    let isVideo: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if members.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: isVideo ? "video.slash.fill" : "phone.slash.fill")
                            .font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
                        Text("No family members yet")
                            .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(members) { member in
                                MemberCallRow(member: member, isVideo: isVideo)
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                    }
                }
            }
            .navigationTitle(isVideo ? String(localized: "Video Call") : String(localized: "Call"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
            }
        }
    }
}

private struct MemberCallRow: View {
    let member: FamilyMember
    let isVideo: Bool

    private var callOptions: [(label: String, icon: String, url: URL?)] {
        var opts: [(String, String, URL?)] = []

        if let email = member.email, !email.isEmpty {
            let scheme = isVideo ? "facetime" : "facetime-audio"
            opts.append(("FaceTime (\(email))", isVideo ? "facetime.fill" : "phone.fill",
                         URL(string: "\(scheme)://\(email)")))
        }
        if let phone = member.phone, !phone.isEmpty {
            let digits = phone.filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty {
                let scheme = isVideo ? "facetime" : "facetime-audio"
                opts.append(("FaceTime (\(phone))", isVideo ? "facetime.fill" : "phone.fill",
                             URL(string: "\(scheme)://\(digits)")))
            }
        }
        if let wa = member.socialLinks?.first(where: { $0.platform == "whatsapp" }) {
            let digits = wa.handle.filter { $0.isNumber }
            if !digits.isEmpty {
                let waScheme = isVideo ? "whatsapp://video?phone=\(digits)" : "whatsapp://call?phone=\(digits)"
                opts.append(("WhatsApp (\(wa.handle))", "message.fill", URL(string: waScheme)))
            }
        }
        if opts.isEmpty, let phone = member.phone, !phone.isEmpty {
            let digits = phone.filter { $0.isNumber }
            if !digits.isEmpty {
                opts.append(("Phone (\(phone))", "phone.fill", URL(string: "tel://\(digits)")))
            }
        }
        return opts
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(member.swiftColor.opacity(0.18))
                        Text(member.initials)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(member.swiftColor)
                    }
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(member.swiftColor, lineWidth: 1.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                        Text(LocalizedStringKey(member.roleLabel))
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }

                if callOptions.isEmpty {
                    Text("No contact info available")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(callOptions.enumerated()), id: \.offset) { _, opt in
                            Button {
                                HapticFeedback.impact(.light)
                                if let url = opt.url { UIApplication.shared.open(url) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: opt.icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 20)
                                    Text(opt.label)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(AppFont.caption2)
                                        .foregroundStyle(Color.primary.opacity(0.3))
                                }
                                .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
                                .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Date Separator

struct ChatDateSeparator: View {
    let dateStr: String

    private var label: String {
        let d = ISODate.date(from: dateStr) ?? Date()
        let cal = Calendar.current
        if cal.isDateInToday(d)     { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        let out = DateFormatter(); out.dateFormat = "d MMMM"
        return out.string(from: d)
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .fixedSize()
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
    }
}

/// The reply-preview banner shown above the composer while replying. Shared by
/// the group and DM input bars — both pass a plain sender + snippet so it works
/// across the two message types.
struct ChatReplyBanner: View {
    let sender: String
    let snippet: String
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2.5).fill(Color.accentColor).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "Reply to %@"), sender))
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.accentColor)
                Text(snippet)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
        .background(.regularMaterial)
    }
}

/// The recording status pill (pulsing dot · elapsed time · "slide to cancel")
/// shared by both input bars while a voice message is being recorded.
struct ChatRecordingIndicator: View {
    let durationText: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse)
            Text(durationText)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            Image(systemName: "lessthan")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.3))
            Text("Slide to cancel")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.4))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 9)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }
}

/// The "unread messages" marker shown at the point the reader left off, tinted
/// with the accent colour to stand apart from the neutral date separators.
struct UnreadDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.accentColor.opacity(0.3)).frame(height: 0.5)
            Text("Unread messages")
                .font(AppFont.caption2)
                .foregroundStyle(Color.accentColor)
                .fixedSize()
            Rectangle().fill(Color.accentColor.opacity(0.3)).frame(height: 0.5)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Unread messages"))
    }
}

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

    private var isDeleted: Bool { message.deletedForAll == true }
    private var ownBubbleColor: Color { outgoingColor ?? Color.blue.opacity(0.75) }
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
        members.first { $0.name == message.senderName }
    }
    private var seen: Bool { !readers.isEmpty }
    /// 3-state tick: read (someone read) > delivered (someone received) > sent.
    private var tickStatus: MessageTick.Status {
        if !readers.isEmpty { return .read }
        if !deliverers.isEmpty { return .delivered }
        return .sent
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
                        .foregroundStyle(sender?.swiftColor ?? Color.primary.opacity(AppOpacity.secondaryText))
                        .padding(.leading, AppSpacing.xxs)
                }
                if let replied = repliedMessage, !isDeleted {
                    quotedReply(replied)
                }
                bubbleContent
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
                    .overlay(alignment: isOwn ? .trailing : .leading) {
                        if abs(swipeOffset) > 12 {
                            Image(systemName: swipeOffset > 0 ? "arrowshape.turn.up.left.fill" : "info.circle.fill")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .offset(x: swipeOffset > 0 ? -28 : 28)
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.15) {
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    guard !isDeleted else { return }
                    // Engage across the full row width, only on a clearly horizontal
                    // drag so vertical scrolling still works. Right = reply, left = details.
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    swipeOffset = max(-70, min(70, v.translation.width))
                }
                .onEnded { v in
                    guard !isDeleted else { return }
                    if v.translation.width > 44 { onReply?(); HapticFeedback.impact(.light) }
                    else if v.translation.width < -60 { showDetails = true; HapticFeedback.impact(.light) }
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
        if let member = sender {
            ZStack {
                Circle()
                    .fill(member.swiftColor.opacity(0.18))
                Text(member.initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle()
                    .strokeBorder(member.swiftColor, lineWidth: 2)
            )
        } else {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5))
        }
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
        } else if message.isStickerMessage, let stickerId = message.body {
            StickerBubble(stickerId: stickerId)
        } else if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
            LocationBubble(lat: lat, lon: lon, isOwn: isOwn, label: message.senderName, hasTail: isGroupEnd)
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
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                .background(isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
                            in: bubbleShape)
        }
    }
}

// MARK: - Message status tick (shared)

/// WhatsApp-style delivery tick: single check = sent, double check =
/// delivered, blue double check = read. The second check grows in and the
/// colour morphs as the status advances, so a message reads sent → delivered
/// → read with a smooth transition rather than a hard swap.
struct MessageTick: View {
    enum Status { case sent, delivered, read }
    let status: Status
    /// Colour for the sent/delivered states.
    var color: Color = Color.primary.opacity(0.45)
    /// Colour for the read state — blue on a neutral status row, or white
    /// when the tick sits inside a coloured (own) bubble.
    var readColor: Color = .blue
    var size: CGFloat = 11

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            if status != .sent {
                Image(systemName: "checkmark")
                    .offset(x: size * 0.42)
                    .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: status == .sent ? size : size * 1.42, alignment: .leading)
        .foregroundStyle(status == .read ? readColor : color)
        .animation(.snappy(duration: 0.22), value: status)
        .accessibilityLabel(status == .read ? Text("Read")
                             : status == .delivered ? Text("Delivered") : Text("Sent"))
    }
}

// MARK: - Bubble shape (shared)

/// A speech-bubble background whose bottom corner nearest the sender tightens
/// into a "tail" on the last bubble of a same-sender run — the iMessage /
/// WhatsApp read for "this is where the group ends, and who it's from". Middle
/// bubbles of a run stay fully rounded so the column reads as one block.
struct ChatBubbleShape: Shape {
    let isOwn: Bool
    /// Draw the tail — true only on the last bubble of a same-sender group.
    var hasTail: Bool = true
    var radius: CGFloat = 18
    var tailRadius: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: hasTail && !isOwn ? tailRadius : radius,
            bottomTrailingRadius: hasTail && isOwn ? tailRadius : radius,
            topTrailingRadius: radius,
            style: .continuous
        ).path(in: rect)
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
                appBackground.ignoresSafeArea()
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

// MARK: - Reaction Picker

struct ReactionPickerView: View {
    let myReaction: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let emojis = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                    dismiss()
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .scaleEffect(myReaction == emoji ? 1.2 : 1.0)
                        .padding(AppSpacing.sm)
                        .background(myReaction == emoji ? Color.blue.opacity(0.15) : Color.clear,
                                    in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackground.ignoresSafeArea())
    }
}

// MARK: - Chat file / video bubbles (resolve private signed URLs; legacy URLs pass through)

struct ChatFileBubble: View {
    let stored: String?
    let name: String?
    let isOwn: Bool
    let ownBubbleColor: Color
    var hasTail: Bool = true
    let onPreview: (URL, String) -> Void
    @State private var url: URL?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(isOwn ? .white : Color.accentColor)
            Text(name ?? "File")
                .font(AppFont.footnote)
                .foregroundStyle(isOwn ? .white : .primary)
                .lineLimit(2)
            if url != nil {
                Spacer()
                Image(systemName: "eye.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isOwn ? .white.opacity(0.8) : Color.accentColor)
                    .onTapGesture { if let url { onPreview(url, name ?? url.lastPathComponent) } }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let url { onPreview(url, name ?? url.lastPathComponent) } }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(
            isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
            in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail)
        )
        .frame(maxWidth: 240)
        .task(id: stored ?? "") { if let stored { url = await ChatMedia.resolve(stored) } }
    }
}

struct ChatVideoBubble: View {
    let stored: String
    var isOwn: Bool = false
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?

    private var shape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .frame(width: 200, height: 140)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if let url { onTap(url) } }
        .task(id: stored) { url = await ChatMedia.resolve(stored) }
    }
}

// MARK: - Chat image bubble (resolves private signed URLs; passes legacy URLs through)

struct ChatImageBubble: View {
    let stored: String
    let caption: String?
    let isOwn: Bool
    let ownBubbleColor: Color
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?

    private var hasCaption: Bool { (caption?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 160)
                } else {
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                        .frame(width: 160, height: 120)
                        .overlay(ProgressView().tint(.white))
                }
            }
            .onTapGesture { if let url { onTap(url) } }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 15))
                    .foregroundStyle(isOwn ? .white : .primary)
                    .padding(.horizontal, 10).padding(.top, AppSpacing.xs)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(hasCaption ? 4 : 0)
        .background(hasCaption ? (isOwn ? ownBubbleColor : Color.primary.opacity(0.08)) : Color.clear)
        // Clip the whole card (image + caption) to the bubble so a group ending
        // on a photo carries the same tail as a text bubble.
        .clipShape(ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
        .task(id: stored) { url = await ChatMedia.resolve(stored) }
    }
}

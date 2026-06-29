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
                            .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.5))
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(members) { member in
                                MemberCallRow(member: member, isVideo: isVideo)
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 8)
                    }
                }
            }
            .navigationTitle(isVideo ? String(localized: "Video Call") : String(localized: "Call"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
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
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Text(LocalizedStringKey(member.roleLabel))
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
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
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.primary.opacity(0.3))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        let f  = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        let d  = f.date(from: dateStr) ?? f2.date(from: dateStr) ?? Date()
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.35))
                .fixedSize()
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
    var onPollVote: ((Int) -> Void)? = nil
    var onLongPress: (() -> Void)? = nil

    private var isDeleted: Bool { message.deletedForAll == true }
    private var ownBubbleColor: Color { outgoingColor ?? Color.blue.opacity(0.75) }

    private var showsQuickForward: Bool {
        guard onForward != nil, !isDeleted else { return false }
        // Quick-forward button only on link messages.
        return linkURL != nil
    }

    private var forwardButton: some View {
        Button { onForward?() } label: {
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassCircle()
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
    private var tickStatus: ReadCheck.Status {
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
                chatAvatar
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sender?.swiftColor ?? Color.primary.opacity(0.45))
                        .padding(.leading, 4)
                }
                if let replied = repliedMessage, !isDeleted {
                    quotedReply(replied)
                }
                bubbleContent
                    .offset(x: swipeOffset)
                    .overlay(alignment: isOwn ? .trailing : .leading) {
                        if abs(swipeOffset) > 12 {
                            Image(systemName: swipeOffset > 0 ? "arrowshape.turn.up.left.fill" : "info.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .offset(x: swipeOffset > 0 ? -28 : 28)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 18)
                            .onChanged { v in
                                guard !isDeleted else { return }
                                // right = reply, left = details; clamp the rubber-band
                                swipeOffset = max(-70, min(70, v.translation.width))
                            }
                            .onEnded { v in
                                guard !isDeleted else { return }
                                if v.translation.width > 55 { onReply?(); HapticFeedback.impact(.light) }
                                else if v.translation.width < -55 { showDetails = true; HapticFeedback.impact(.light) }
                                withAnimation(.spring(response: 0.3)) { swipeOffset = 0 }
                            }
                    )
                    .onLongPressGesture(minimumDuration: 0.35) {
                        HapticFeedback.impact(.medium)
                        onLongPress?()
                    }
                if let link = linkURL {
                    LinkPreviewView(url: link)
                }
                if !displayReactions.isEmpty, !isDeleted {
                    reactionPills
                }
                statusRow
            }

            if !isOwn {
                if showsQuickForward { forwardButton }
                Spacer(minLength: 60)
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
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(replied.senderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(replied.body?.isEmpty == false ? (replied.body ?? "") :
                        (replied.isAudioMessage ? "🎤 Voice message" :
                         replied.isImageMessage ? "📷 Photo" :
                         replied.isLocationMessage ? "📍 Location" : "Attachment"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 240, alignment: .leading)
    }

    private var reactionPills: some View {
        HStack(spacing: 4) {
            ForEach(Array(displayReactions.sorted(by: { $0.key < $1.key })), id: \.key) { emoji, count in
                Button {
                    if let onReact {
                        onReact(emoji)
                    } else {
                        toggleLocalReaction(emoji)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji).font(.system(size: 14))
                        if count > 1 {
                            Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(displayMyReaction == emoji ? Color.blue.opacity(0.15) : Color.primary.opacity(0.07),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(displayMyReaction == emoji ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
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
                    if !isDeleted { ReadCheck(status: tickStatus) }
                }
                .padding(.horizontal, 4)
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
            .padding(.horizontal, 4)
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
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if message.isPollMessage, let poll = ChatPoll.decode(message.body) {
            PollBubble(poll: poll, votes: pollVotes, myUserId: myUserId, isOwn: isOwn,
                       onVote: { onPollVote?($0) })
        } else if message.isEventMessage, let event = ChatEvent.decode(message.body) {
            EventBubble(event: event, isOwn: isOwn)
        } else if message.isStickerMessage, let stickerId = message.body {
            StickerBubble(stickerId: stickerId)
        } else if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
            LocationBubble(lat: lat, lon: lon, isOwn: isOwn)
        } else if message.isAudioMessage, let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
            AudioBubble(url: url, isOwn: isOwn)
        } else if message.isFileMessage {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isOwn ? .white : Color.accentColor)
                Text(message.body ?? "File")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isOwn ? .white : .primary)
                    .lineLimit(2)
                if let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
                    Spacer()
                    Image(systemName: "eye.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isOwn ? .white.opacity(0.8) : Color.accentColor)
                        .onTapGesture {
                            filePreview = FilePreviewItem(url: url, name: message.body ?? url.lastPathComponent)
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
                    filePreview = FilePreviewItem(url: url, name: message.body ?? url.lastPathComponent)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .frame(maxWidth: 240)
        } else if message.isImageMessage, let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.07))
                            .frame(width: 160, height: 120)
                            .overlay(ProgressView().tint(.white))
                    }
                }
                .onTapGesture { viewerItem = ImageViewerItem(url: url) }
                // Optional caption stored in the message body.
                if let caption = message.body, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 15))
                        .foregroundStyle(isOwn ? .white : .primary)
                        .padding(.horizontal, 10).padding(.top, 6)
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
            .padding(message.body?.isEmpty == false ? 4 : 0)
            .background(
                (message.body?.isEmpty == false) ? (isOwn ? ownBubbleColor : Color.primary.opacity(0.08)) : Color.clear,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        } else if message.isVideoMessage, let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 200, height: 140)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { videoItem = ImageViewerItem(url: url) }
        } else {
            Text(message.body ?? "")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Read Receipt Check

private struct ReadCheck: View {
    enum Status { case sent, delivered, read }
    let status: Status

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            // Single tick = sent; second tick appears once delivered/read.
            if status != .sent {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .offset(x: 3.5)
            }
        }
        .frame(width: 14, alignment: .leading)
        .foregroundStyle(status == .read ? Color.blue : Color.primary.opacity(0.4))
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
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("Seen \(read.readTimeDisplay)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.primary.opacity(0.45))
                                }
                                Spacer()
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if !deliveredOnly.isEmpty {
                            HStack {
                                Text("Delivered")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.45))
                                Spacer()
                            }
                            .padding(.top, 6)
                            ForEach(deliveredOnly) { d in
                                HStack(spacing: 12) {
                                    Text(d.delivererName.isEmpty ? "Member" : d.delivererName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.primary.opacity(0.4))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Seen by \(readers.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
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
                        .padding(8)
                        .background(myReaction == emoji ? Color.blue.opacity(0.15) : Color.clear,
                                    in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackground.ignoresSafeArea())
    }
}

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
    var readers: [MessageRead] = []
    var onDelete: (() -> Void)? = nil

    @State private var showReaders = false
    @State private var localReactions: [String: Int] = [:]
    @State private var myReaction: String? = nil
    @State private var showReactionPicker = false

    private static let reactionEmojis = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

    private var sender: FamilyMember? {
        members.first { $0.name == message.senderName }
    }
    private var seen: Bool { !readers.isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 60)
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
                bubbleContent
                    .contextMenu {
                        Button { UIPasteboard.general.string = message.body } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button { showReactionPicker = true } label: {
                            Label("React", systemImage: "face.smiling")
                        }
                        if isOwn, let onDelete {
                            Divider()
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        HapticFeedback.impact(.medium)
                        showReactionPicker = true
                    }
                if !localReactions.isEmpty {
                    reactionPills
                }
                statusRow
            }

            if !isOwn { Spacer(minLength: 60) }
        }
        .sheet(isPresented: $showReaders) {
            SeenBySheet(readers: readers, members: members)
        }
        .sheet(isPresented: $showReactionPicker) {
            ReactionPickerView(myReaction: myReaction) { emoji in
                toggleReaction(emoji)
            }
            .presentationDetents([.height(100)])
        }
    }

    private var reactionPills: some View {
        HStack(spacing: 4) {
            ForEach(Array(localReactions.sorted(by: { $0.key < $1.key })), id: \.key) { emoji, count in
                Button {
                    toggleReaction(emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji).font(.system(size: 14))
                        if count > 1 {
                            Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(myReaction == emoji ? Color.blue.opacity(0.15) : Color.primary.opacity(0.07),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(myReaction == emoji ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleReaction(_ emoji: String) {
        if myReaction == emoji {
            myReaction = nil
            if let count = localReactions[emoji] {
                if count <= 1 { localReactions.removeValue(forKey: emoji) }
                else { localReactions[emoji] = count - 1 }
            }
        } else {
            if let old = myReaction, let count = localReactions[old] {
                if count <= 1 { localReactions.removeValue(forKey: old) }
                else { localReactions[old] = count - 1 }
            }
            myReaction = emoji
            localReactions[emoji, default: 0] += 1
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if isOwn {
            Button {
                if seen { showReaders = true }
            } label: {
                HStack(spacing: 4) {
                    Text(message.timeDisplay)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.3))
                    ReadCheck(seen: seen)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .disabled(!seen)
        } else {
            Text(message.timeDisplay)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.3))
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
        if message.isStickerMessage, let stickerId = message.body {
            StickerBubble(stickerId: stickerId)
        } else if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
            LocationBubble(lat: lat, lon: lon, isOwn: isOwn)
        } else if message.isAudioMessage, let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
            AudioBubble(url: url, duration: 0, isOwn: isOwn)
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
                    Link(destination: url) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isOwn ? .white.opacity(0.8) : Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                isOwn ? Color.blue.opacity(0.75) : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .frame(maxWidth: 240)
        } else if message.isImageMessage, let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
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
        } else {
            Text(message.body ?? "")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(isOwn ? Color.blue.opacity(0.75) : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Read Receipt Check

private struct ReadCheck: View {
    let seen: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .offset(x: 3.5)
        }
        .frame(width: 14, alignment: .leading)
        .foregroundStyle(seen ? Color.blue : Color.primary.opacity(0.4))
    }
}

// MARK: - Seen By Sheet

private struct SeenBySheet: View {
    let readers: [MessageRead]
    let members: [FamilyMember]
    @Environment(\.dismiss) private var dismiss

    private func member(for name: String) -> FamilyMember? {
        members.first { $0.name == name }
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

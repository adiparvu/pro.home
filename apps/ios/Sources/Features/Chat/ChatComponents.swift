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
                Color.clear
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
        .presentationBackground(.thinMaterial)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            if status != .sent {
                Image(systemName: "checkmark")
                    .offset(x: size * 0.42)
                    // Reduce Motion: fade the second check in without the scale morph.
                    .transition(reduceMotion ? .opacity
                                : .scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: status == .sent ? size : size * 1.42, alignment: .leading)
        .foregroundStyle(status == .read ? readColor : color)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: status)
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
        .presentationBackground(.ultraThinMaterial)
    }
}

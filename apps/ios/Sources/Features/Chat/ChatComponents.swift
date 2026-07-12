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
                            .font(AppFont.scaled(44)).foregroundStyle(Color.primary.opacity(0.18))
                        Text("No family members yet")
                            .font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                            .font(AppFont.scaled(13, weight: .bold))
                            .foregroundStyle(member.swiftColor)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                        Text(LocalizedStringKey(member.roleLabel))
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }

                if callOptions.isEmpty {
                    Text("No contact info available")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(callOptions.enumerated()), id: \.offset) { _, opt in
                            Button {
                                HapticFeedback.impact(.light)
                                if let url = opt.url { UIApplication.shared.open(url) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: opt.icon)
                                        .font(AppFont.scaled(13, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 20)
                                    Text(opt.label)
                                        .font(AppFont.scaled(13))
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
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(18))
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

// (ReactionPickerView is gone — its only presenter was a dead sheet in the
// old MessageBubble; reactions live in the long-press ChatActionOverlay.)

// MARK: - Presence ticker (shared)

/// Re-evaluates its content on a fixed clock so presence-derived text can't
/// freeze while visible: "last seen 5 minutes ago" keeps counting and an
/// "online" that stopped heartbeating decays to "last seen" without needing a
/// new realtime event. Pass the tick's date into `PresenceService.status(at:)`
/// so the re-render actually re-evaluates the window.
struct PresenceTicker<Content: View>: View {
    var interval: TimeInterval = 30
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            content(context.date)
        }
    }
}

// MARK: - On-demand in-thread search (shared by both chat engines)

/// In-thread search summoned on demand instead of a bar pinned permanently
/// under the header: `searchable` is attached only while search is open, so
/// the field appears when the user asks for it (details page / magnifier
/// button) and the native cancel removes it entirely — the thread's top edge
/// stays clean the rest of the time.
struct ChatOnDemandSearch: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: Text

    func body(content: Content) -> some View {
        Group {
            if isPresented {
                content.searchable(text: $text, isPresented: $isPresented,
                                   placement: .navigationBarDrawer(displayMode: .always),
                                   prompt: prompt)
            } else {
                content
            }
        }
        .onChange(of: isPresented) { _, open in
            // Leaving search must never keep filtering the thread.
            if !open { text = "" }
        }
    }
}

extension View {
    /// Presents the system search field only while `isPresented` is true (see
    /// ``ChatOnDemandSearch``).
    func chatOnDemandSearch(text: Binding<String>, isPresented: Binding<Bool>,
                            prompt: Text) -> some View {
        modifier(ChatOnDemandSearch(text: text, isPresented: isPresented, prompt: prompt))
    }
}

// MARK: - At-bottom tracking (shared by both chat engines)

/// Robust "is the reader at (or within a bubble of) the bottom?" detection for
/// a chat ScrollView, from live scroll geometry (iOS 18+). The bottom-sentinel
/// onAppear/onDisappear fallback used alone goes stale: a LazyVStack culls and
/// re-mounts the sentinel on its own schedule (keyboard presentation, a tall
/// incoming bubble, deep scroll-back), which left the flag claiming "not at
/// bottom" while the reader WAS there — so incoming messages didn't auto-follow
/// until a manual scroll. Callers keep the sentinel only as the pre-iOS-18 path.
struct ChatAtBottomModifier: ViewModifier {
    /// Slack below which the reader still counts as "at the bottom" — roughly
    /// one bubble, so a sub-point settle or a just-landed message never flips
    /// the state.
    var threshold: CGFloat = 120
    let update: (Bool) -> Void

    /// True when live scroll geometry drives the detection on this OS, so
    /// callers can mute the legacy sentinel toggles and avoid the two sources
    /// fighting over the same state.
    static var isGeometryDriven: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            // Quantized distance, NOT a Bool: a Bool transform emits only on
            // threshold crossings, so a single emission evaluated mid keyboard
            // or composer-inset animation could go stale and strand the jump
            // button visible at the bottom rest. Buckets re-emit every ~40pt
            // of real movement, so the state self-corrects on the next tick.
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                // How much content lies below the visible span. visibleRect
                // already accounts for every inset, so this stays ≤ 0 at rest
                // on the newest message. The previous form re-added
                // contentInsets.bottom on top of an offset that already spans
                // it — in the group chat (compose bar + tab bar ≈ 150pt) the
                // at-rest distance never dropped under the 120pt threshold,
                // so the jump button burned permanently.
                let distance = geometry.contentSize.height - geometry.visibleRect.maxY
                return (distance / 40).rounded(.down)
            } action: { _, bucket in
                update(bucket * 40 < threshold)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Reports at-bottom transitions of a chat scroll view (see
    /// ``ChatAtBottomModifier``). No-op below iOS 18 — pair with the bottom
    /// sentinel for those systems.
    func chatAtBottomTracking(threshold: CGFloat = 120,
                              _ update: @escaping (Bool) -> Void) -> some View {
        modifier(ChatAtBottomModifier(threshold: threshold, update: update))
    }
}

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

/// The precise "weekday, day month, time" stamp iMessage floats above the
/// message you're replying to while in reply focus (IMG_8495) — e.g.
/// "lun., 6 iul., 10:57". Unlike `ChatDateSeparator` (day only, periodic), this
/// always carries the exact minute of the focused message, and it stays sharp
/// while the rest of the thread recedes behind the reply blur.
struct ReplyFocusTimestamp: View {
    let dateStr: String

    private var label: String {
        let d = ISODate.date(from: dateStr) ?? Date()
        let out = DateFormatter()
        out.locale = .current
        // Template (not a fixed pattern) so the field order localizes: RO gives
        // "lun., 6 iul., 10:57", EN "Mon, Jul 6, 10:57".
        out.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return out.string(from: d)
    }

    var body: some View {
        Text(label)
            .font(AppFont.caption2)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xs)
            .accessibilityLabel(Text(label))
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

/// A speech-bubble background that grows a real iMessage tail — a small curl
/// merged into the bottom corner nearest the sender — on the LAST bubble of a
/// same-sender run. Every bubble reserves the same `tail` strip on its sender
/// side so a run's bodies stay edge-aligned; only the last bubble fills that
/// strip with the tail curl, while earlier bubbles stay fully rounded and the
/// column reads as one block. The tail is authored entirely within `rect` (it
/// never protrudes past the view bounds), so the shape is safe as a `.fill`,
/// a `.background(in:)`, a `.clipShape`, and an iOS 26 `.glassEffect(in:)` mask.
struct ChatBubbleShape: Shape {
    let isOwn: Bool
    /// Draw the tail — true only on the last bubble of a same-sender group.
    var hasTail: Bool = true
    /// Continuous corner radius of the bubble body.
    var radius: CGFloat = 18
    /// How far the body is inset from the sender edge (and, on the last bubble,
    /// how far the tail curl reaches back out to that edge).
    var tail: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Clamp so tiny bubbles (a single glyph) never self-intersect.
        let r = min(radius, (w - tail) / 2, h / 2)
        let t = min(tail, max(0, (w - 2 * r) / 2))
        // How high up the sender edge the tail curl re-joins the body.
        let th = min(9, h - r)

        if isOwn {
            // Body occupies [0, w - t]; tail curls out to the bottom-right (w, h).
            var p = Path()
            p.move(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: w - t - r, y: 0))
            p.addQuadCurve(to: CGPoint(x: w - t, y: r), control: CGPoint(x: w - t, y: 0))
            if hasTail {
                p.addLine(to: CGPoint(x: w - t, y: h - th))
                // Sweep out and down to the tip at the true bottom-right corner…
                p.addQuadCurve(to: CGPoint(x: w, y: h),
                               control: CGPoint(x: w - t * 0.5, y: h - th * 0.5))
                // …then curl back in to the body's bottom-right corner.
                p.addQuadCurve(to: CGPoint(x: w - t, y: h),
                               control: CGPoint(x: w - t * 0.2, y: h))
            } else {
                p.addLine(to: CGPoint(x: w - t, y: h - r))
                p.addQuadCurve(to: CGPoint(x: w - t - r, y: h), control: CGPoint(x: w - t, y: h))
            }
            p.addLine(to: CGPoint(x: r, y: h))
            p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
            p.closeSubpath()
            return p
        } else {
            // Body occupies [t, w]; tail curls out to the bottom-left (0, h).
            var p = Path()
            p.move(to: CGPoint(x: t + r, y: 0))
            p.addLine(to: CGPoint(x: w - r, y: 0))
            p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h - r))
            p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
            if hasTail {
                p.addLine(to: CGPoint(x: t, y: h))
                // Sweep out and down to the tip at the true bottom-left corner…
                p.addQuadCurve(to: CGPoint(x: 0, y: h),
                               control: CGPoint(x: t * 0.5, y: h))
                // …then curl back in and up the sender edge.
                p.addQuadCurve(to: CGPoint(x: t, y: h - th),
                               control: CGPoint(x: t * 0.5, y: h - th * 0.5))
            } else {
                p.addLine(to: CGPoint(x: t + r, y: h))
                p.addQuadCurve(to: CGPoint(x: t, y: h - r), control: CGPoint(x: t, y: h))
            }
            p.addLine(to: CGPoint(x: t, y: r))
            p.addQuadCurve(to: CGPoint(x: t + r, y: 0), control: CGPoint(x: t, y: 0))
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - Incoming bubble glass (iOS 26 Liquid Glass)

extension View {
    /// The received-bubble background: translucent Liquid Glass on iOS 26 (the
    /// iMessage look), a system material on earlier systems, and — under Reduce
    /// Transparency — the opaque iMessage gray, all in the tail-aware bubble
    /// shape. Text over it stays `.primary`, which the system keeps legible on
    /// glass and material in both light and dark.
    func incomingBubbleGlass(hasTail: Bool) -> some View {
        modifier(IncomingBubbleGlass(hasTail: hasTail))
    }

    /// The one bubble-background entry point shared by the text and voice
    /// bubbles: incoming → Liquid Glass; outgoing → the themed solid fill, or
    /// the default iMessage-blue gradient when `gradient` is set.
    @ViewBuilder
    func chatBubbleBackground(isOwn: Bool, hasTail: Bool, fill: Color,
                              gradient: Bool = false) -> some View {
        if isOwn {
            if gradient {
                background(Color.imessageBlueGradient,
                           in: ChatBubbleShape(isOwn: true, hasTail: hasTail))
            } else {
                background(fill, in: ChatBubbleShape(isOwn: true, hasTail: hasTail))
            }
        } else {
            incomingBubbleGlass(hasTail: hasTail)
        }
    }
}

private struct IncomingBubbleGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let hasTail: Bool

    private var shape: ChatBubbleShape { ChatBubbleShape(isOwn: false, hasTail: hasTail) }

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Honor the accessibility request explicitly: an opaque elevated
            // surface with the exact iMessage gray, never a blur to read through.
            content.background(Color.imessageIncoming, in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
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

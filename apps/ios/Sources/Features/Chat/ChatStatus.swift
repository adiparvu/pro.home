import SwiftUI
import Combine

// MARK: - Status / Stories (Instagram-style)
//
// Backed by the status_updates / status_views tables (24h expiry + per-viewer
// seen tracking) via StatusService — posting uploads an image and inserts a
// row, text statuses are pre-rendered to a gradient card image by
// TextStatusComposer, viewing upserts into status_views. Only the
// presentation is Instagram-like; the data plumbing (load / post /
// markViewed / viewers / delete) is unchanged.

// MARK: - Story ring

/// The Instagram-style angular gradient stroked around avatars that have
/// unseen stories. This is a semantic "unseen" indicator, not a tinted
/// control, so the glass-only button law does not apply to it.
private enum StoryRing {
    static let gradient = AngularGradient(
        colors: [.brandWarning, .brandDanger, .brandPink, .brandPurple, .brandWarning],
        center: .center,
        angle: .degrees(-45)
    )
}

private enum StoryRingState {
    /// No active stories — your own empty circle.
    case none
    /// Unseen stories — gradient ring.
    case unseen
    /// Everything seen — thin gray ring.
    case seen
}

/// Avatar circle with the story ring around it.
private struct StoryAvatar: View {
    static let ringSize: CGFloat = 72
    static let avatarSize: CGFloat = 62

    let member: FamilyMember?
    let fallbackInitials: String
    let ring: StoryRingState

    var body: some View {
        ZStack {
            ringCircle
            avatar
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    @ViewBuilder private var ringCircle: some View {
        switch ring {
        case .unseen: Circle().strokeBorder(StoryRing.gradient, lineWidth: 2.5)
        case .seen:   Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
        case .none:   EmptyView()
        }
    }

    @ViewBuilder private var avatar: some View {
        if let member {
            MemberAvatar(member: member, size: Self.avatarSize)
        } else {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18))
                Text(fallbackInitials)
                    .font(.system(size: Self.avatarSize * 0.33, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: Self.avatarSize, height: Self.avatarSize)
        }
    }
}

/// One tray entry: ringed avatar + one-line name beneath.
private struct StoryCircleButton: View {
    let title: String
    let member: FamilyMember?
    let fallbackInitials: String
    let ring: StoryRingState
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: AppSpacing.xs) {
                StoryAvatar(member: member, fallbackInitials: fallbackInitials, ring: ring)
                Text(title)
                    .font(AppFont.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: StoryAvatar.ringSize)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Identifiable wrapper so the tray can present the viewer at a given member.
private struct StoryDestination: Identifiable {
    let groupId: UUID
    var id: UUID { groupId }
}

// MARK: - Status page (story tray)

struct StatusView: View {
    var propertyId: UUID?
    let myName: String
    let members: [FamilyMember]
    var onAddStatus: () -> Void = {}

    private let status = StatusService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: StoryDestination?
    @State private var deleteCandidate: StatusUpdate?

    private var myId: UUID? { supabase.auth.currentSession?.user.id }
    private var myMember: FamilyMember? { members.first { $0.name == myName } }
    private var myInitials: String { String(myName.prefix(1)).uppercased() }
    private var myGroup: StatusGroup? { status.myGroup(myId: myId) }
    private var others: [StatusGroup] { status.otherGroups(myId: myId) }
    /// Tray order = viewer order: your story first, then the members'.
    private var allGroups: [StatusGroup] { (myGroup.map { [$0] } ?? []) + others }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    storyBar

                    if others.isEmpty {
                        Text("No recent updates")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    Text("Status updates disappear after 24 hours.")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .padding(.horizontal, AppSpacing.xl)

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(.top, AppSpacing.md)
            }
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { if let pid = propertyId { await status.load(propertyId: pid) } }
            .fullScreenCover(item: $viewing) { dest in
                StoryViewer(groups: allGroups, startGroupId: dest.groupId,
                            myName: myName, members: members, propertyId: propertyId)
            }
            .confirmationDialog("Delete status",
                                isPresented: Binding(get: { deleteCandidate != nil },
                                                     set: { if !$0 { deleteCandidate = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let item = deleteCandidate, let pid = propertyId else { return }
                    deleteCandidate = nil
                    Task { await status.delete(item, propertyId: pid) }
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            } message: {
                Text("This status will be deleted for everyone.")
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: Story tray

    private var storyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppSpacing.lg) {
                myStoryCircle
                ForEach(others) { g in
                    StoryCircleButton(
                        title: g.authorName,
                        member: members.first { $0.name == g.authorName },
                        fallbackInitials: String(g.authorName.prefix(2)).uppercased(),
                        ring: status.allSeen(g) ? .seen : .unseen
                    ) {
                        viewing = StoryDestination(groupId: g.id)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.xs)
        }
    }

    private var myStoryCircle: some View {
        Button {
            HapticFeedback.impact(.light)
            if let g = myGroup { viewing = StoryDestination(groupId: g.id) } else { onAddStatus() }
        } label: {
            VStack(spacing: AppSpacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    StoryAvatar(member: myMember, fallbackInitials: myInitials,
                                ring: myGroup == nil ? .none : .unseen)
                    addBadge
                }
                Text("Povestea ta")
                    .font(AppFont.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: StoryAvatar.ringSize)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onAddStatus() } label: { Label("Add status", systemImage: "plus") }
            if let latest = myGroup?.latest {
                Button(role: .destructive) { deleteCandidate = latest } label: {
                    Label("Delete status", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(myGroup == nil ? Text("Add status") : Text("Povestea ta"))
    }

    /// Instagram's blue "+" badge. Once you already have a story the whole
    /// circle opens the viewer, so the badge becomes its own compose button.
    @ViewBuilder private var addBadge: some View {
        if myGroup == nil {
            plusGlyph
        } else {
            Button { onAddStatus() } label: { plusGlyph }
                .buttonStyle(.plain)
                .accessibilityLabel("Add status")
        }
    }

    private var plusGlyph: some View {
        Image(systemName: "plus.circle.fill")
            .font(AppFont.scaled(20, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.brandPrimaryBlue)
            .background(Circle().fill(Color(.systemBackground)).padding(-2))
            .offset(x: AppSpacing.xxs, y: AppSpacing.xxs)
    }
}

// MARK: - Text status composer (Instagram text mode: text on a gradient)

struct TextStatusComposer: View {
    let onPost: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var bgIndex = 0
    @FocusState private var focused: Bool

    /// Story background palettes — content baked into the posted image
    /// (not UI chrome), so they intentionally stay literal colors.
    private static let gradients: [[Color]] = [
        [Color(red: 0.16, green: 0.20, blue: 0.52), Color(red: 0.36, green: 0.20, blue: 0.68)],
        [Color(red: 0.90, green: 0.42, blue: 0.28), Color(red: 0.98, green: 0.70, blue: 0.52)],
        [Color(red: 0.00, green: 0.48, blue: 0.66), Color(red: 0.60, green: 0.79, blue: 0.88)],
        [Color(red: 0.13, green: 0.69, blue: 0.30), Color(red: 0.30, green: 0.85, blue: 0.45)],
        [Color(red: 0.82, green: 0.35, blue: 0.55), Color(red: 0.96, green: 0.66, blue: 0.72)],
        [Color(white: 0.05), Color(white: 0.18)],
    ]

    private var gradient: LinearGradient {
        LinearGradient(colors: Self.gradients[bgIndex],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The 9:16 card that gets rendered to the posted image.
    private var renderCard: some View {
        ZStack {
            gradient
            Text(text.isEmpty ? " " : text)
                .font(AppFont.scaled(34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(36)
        }
        .frame(width: 360, height: 640)
    }

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    glassIcon("xmark", label: "Cancel") { dismiss() }
                    Spacer()
                    glassIcon("paintpalette.fill", label: "Change background") {
                        HapticFeedback.selection()
                        withAnimation(reduceMotion ? nil : .smooth) {
                            bgIndex = (bgIndex + 1) % Self.gradients.count
                        }
                    }
                }

                Spacer()

                TextField("", text: $text, axis: .vertical)
                    .font(AppFont.title)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .overlay(alignment: .center) {
                        if text.isEmpty {
                            Text("Type a status")
                                .font(AppFont.title)
                                .foregroundStyle(.white.opacity(0.5))
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xxl)

                Spacer()

                GlassWideButton(icon: "paperplane.fill", label: "Distribuie") { post() }
                    .disabled(isBlank)
                    .opacity(isBlank ? 0.45 : 1)
                    .padding(.bottom, AppSpacing.sm)
            }
            .padding(AppSpacing.xl)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }

    private func glassIcon(_ systemName: String, label: LocalizedStringKey,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .mediaGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    @MainActor private func post() {
        let renderer = ImageRenderer(content: renderCard)
        renderer.scale = 3
        if let img = renderer.uiImage { onPost(img) }
        dismiss()
    }
}

// MARK: - Full-screen story viewer (Instagram-style)

struct StoryViewer: View {
    let groups: [StatusGroup]
    let myName: String
    let members: [FamilyMember]
    var propertyId: UUID?

    private let status = StatusService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var groupIndex: Int
    @State private var itemIndex = 0
    /// 0…1 fill of the active segment (5s per story).
    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var isDragging = false
    @State private var isLoadingMedia = false
    @State private var dragOffset: CGFloat = 0
    @State private var mediaURL: URL?
    @State private var viewers: [String] = []
    @State private var showViewers = false
    @State private var showDeleteConfirm = false

    private static let storyDuration: Double = 5
    private static let tickInterval: Double = 1.0 / 30.0
    /// Progress clock. Pausing is a hard freeze: ticks are ignored while
    /// `isPaused`, so the bar cannot creep during a long-press or drag.
    private let tick = Timer.publish(every: StoryViewer.tickInterval, on: .main, in: .common).autoconnect()

    init(groups: [StatusGroup], startGroupId: UUID, myName: String,
         members: [FamilyMember], propertyId: UUID?) {
        self.groups = groups
        self.myName = myName
        self.members = members
        self.propertyId = propertyId
        _groupIndex = State(initialValue: groups.firstIndex(where: { $0.id == startGroupId }) ?? 0)
    }

    // MARK: Derived

    private var group: StatusGroup? {
        groups.indices.contains(groupIndex) ? groups[groupIndex] : nil
    }
    private var item: StatusUpdate? {
        guard let group, group.items.indices.contains(itemIndex) else { return nil }
        return group.items[itemIndex]
    }
    private var isMine: Bool { supabase.auth.currentSession?.user.id == group?.authorId }
    private var authorMember: FamilyMember? { members.first { $0.name == group?.authorName } }
    /// Frozen while pressing, dragging, showing a dialog, or resolving media.
    private var isPaused: Bool {
        isPressing || isDragging || showViewers || showDeleteConfirm || isLoadingMedia
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            tapZones

            VStack(spacing: AppSpacing.md) {
                progressBars
                header
                Spacer()
                footer
            }
        }
        .offset(y: dragOffset)
        .simultaneousGesture(dismissDrag)
        .onReceive(tick) { _ in advanceProgress() }
        .onAppear {
            guard group != nil else { dismiss(); return }
            itemIndex = firstUnseenIndex(in: groupIndex)
        }
        .task(id: item?.id) {
            guard let item else { return }
            if let media = item.mediaUrl {
                isLoadingMedia = true
                mediaURL = await ChatMedia.resolve(media)
                isLoadingMedia = false
            }
            if propertyId != nil { await status.markViewed(item, viewerName: myName) }
        }
        .confirmationDialog("Seen by", isPresented: $showViewers, titleVisibility: .visible) {
            // Viewer names are listed in the message below.
        } message: {
            if viewers.isEmpty {
                Text("No views yet")
            } else {
                Text(viewers.joined(separator: ", "))
            }
        }
        .confirmationDialog("Delete status", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let item, let pid = propertyId else { return }
                Task {
                    await status.delete(item, propertyId: pid)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This status will be deleted for everyone.")
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Content

    /// The story card — every status is media (text statuses are pre-rendered
    /// gradient cards), shown full-screen on black.
    @ViewBuilder private var content: some View {
        if item?.mediaUrl != nil {
            StorageImage(url: mediaURL) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(item?.id) // never flash the previous story's bitmap
        }
    }

    /// Invisible navigation zones: left third = previous, rest = next.
    /// Holding either zone pauses. Explicit accessibility traits/labels —
    /// VoiceOver has nothing else to read on transparent zones.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 0)
                .onTapGesture { previous() }
                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 60,
                                    perform: {}, onPressingChanged: { isPressing = $0 })
                .accessibilityLabel("Previous story")
                .accessibilityAddTraits(.isButton)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { next() }
                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 60,
                                    perform: {}, onPressingChanged: { isPressing = $0 })
                .accessibilityLabel("Next story")
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Chrome

    private var progressBars: some View {
        HStack(spacing: AppSpacing.xxs) {
            ForEach((group?.items ?? []).indices, id: \.self) { i in
                StorySegmentBar(fraction: i < itemIndex ? 1 : (i == itemIndex ? progress : 0))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            if let authorMember {
                MemberAvatar(member: authorMember, size: 34)
            } else {
                ZStack {
                    Circle().fill(.white.opacity(0.2))
                    Text(String((group?.authorName ?? "?").prefix(2)).uppercased())
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
            }

            VStack(alignment: .leading, spacing: 1) {
                (isMine ? Text("Povestea ta") : Text(group?.authorName ?? ""))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let date = item?.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(AppFont.caption2)
                        .foregroundStyle(.white.opacity(AppOpacity.emphasis))
                }
            }

            Spacer()

            if isMine {
                headerButton("trash", label: "Delete status") { showDeleteConfirm = true }
            }
            headerButton("xmark", label: "Close") { dismiss() }
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private func headerButton(_ systemName: String, label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppFont.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.md) {
            if let caption = item?.caption, !caption.isEmpty {
                Text(caption)
                    .font(AppFont.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(AppSpacing.md)
                    .background(.black.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .padding(.horizontal, AppSpacing.xl)
            }
            if isMine {
                Button {
                    guard let id = item?.id else { return }
                    Task {
                        viewers = await status.viewers(of: id)
                        showViewers = true
                    }
                } label: {
                    Label("Seen by", systemImage: "eye.fill")
                        .font(AppFont.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .mediaGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, AppSpacing.xxl)
    }

    // MARK: Gestures & progression

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                isDragging = true
                guard !reduceMotion else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                isDragging = false
                if value.translation.height > 110 {
                    dismiss()
                } else if reduceMotion {
                    dragOffset = 0
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    private func advanceProgress() {
        guard !isPaused, item != nil else { return }
        progress += Self.tickInterval / Self.storyDuration
        if progress >= 1 { next() }
    }

    private func next() {
        progress = 0
        mediaURL = nil
        if let group, itemIndex < group.items.count - 1 {
            itemIndex += 1
        } else {
            nextGroup()
        }
    }

    /// After a member's last story: the next member with unseen stories,
    /// or dismiss at the very end.
    private func nextGroup() {
        guard let nextIdx = ((groupIndex + 1) ..< groups.count)
            .first(where: { !status.allSeen(groups[$0]) }) else {
            dismiss()
            return
        }
        groupIndex = nextIdx
        itemIndex = firstUnseenIndex(in: nextIdx)
    }

    private func previous() {
        progress = 0
        mediaURL = nil
        if itemIndex > 0 {
            itemIndex -= 1
        } else if groupIndex > 0 {
            groupIndex -= 1
            itemIndex = max((group?.items.count ?? 1) - 1, 0)
        }
        // At the very first story a left tap just restarts it.
    }

    private func firstUnseenIndex(in index: Int) -> Int {
        guard groups.indices.contains(index) else { return 0 }
        return groups[index].items.firstIndex { !status.viewedIds.contains($0.id) } ?? 0
    }
}

/// One segment of the top progress bar. The fill scales instead of resizing
/// (no per-tick layout), and never renders a degenerate 0-width capsule.
private struct StorySegmentBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.3))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .scaleEffect(x: max(fraction, 0.001), y: 1, anchor: .leading)
                    .opacity(fraction > 0 ? 1 : 0)
            }
            .frame(height: 3)
            .clipShape(Capsule())
    }
}

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
            .font(.system(size: 20, weight: .semibold))
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .overlay(alignment: .center) {
                        if text.isEmpty {
                            Text("Type a status")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
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
                .font(.system(size: 17, weight: .semibold))
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

// MARK: - Communities (UI shell)
//
// Communities — multiple named chat groups per property (workers, family, …),
// backed by chat_groups / chat_group_members (migration 078). This screen lists
// and creates groups and manages their members.

struct CommunitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var service = ChatGroupService()

    var propertyId: UUID? = nil
    var members: [FamilyMember] = []
    var myName: String = "Me"

    @State private var showCreate = false
    /// Value-based path so a deep link (prvio://communities/<id>) can open a
    /// specific group programmatically, not just by tap.
    @State private var path: [ChatGroup] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    newGroupButton

                    if service.groups.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(service.groups) { group in
                                NavigationLink(value: group) {
                                    CommunityRow(group: group,
                                                 memberCount: service.members(for: group).count,
                                                 preview: service.previewLine(for: group),
                                                 avatarMembers: resolvedMembers(of: group))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, AppSpacing.sm)
            }
            .navigationDestination(for: ChatGroup.self) { group in
                GroupChatView(group: group,
                              propertyId: propertyId,
                              myName: myName,
                              members: members,
                              service: service)
            }
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showCreate) {
                CreateGroupSheet(members: members) { name, kind, selected in
                    showCreate = false
                    guard let pid = propertyId else { return }
                    Task {
                        if let created = await service.create(propertyId: pid, name: name, kind: kind,
                                                              selected: selected, myName: myName) {
                            // Land straight in the new conversation.
                            path = [created]
                        }
                    }
                }
            }
            .task {
                if let pid = propertyId { await service.load(propertyId: pid) }
                openDeepLinkedGroupIfNeeded()
            }
            // A second deep link while the sheet is already up re-targets the
            // path instead of relying on a fresh .task.
            .onChange(of: router.communitiesRequest) { _, _ in
                openDeepLinkedGroupIfNeeded()
            }
        }
        .presentationBackground(.thinMaterial)
    }

    /// Opens the group a deep link asked for, once, when it exists.
    private func openDeepLinkedGroupIfNeeded() {
        guard let gid = router.deepLinkCommunityGroupId else { return }
        router.deepLinkCommunityGroupId = nil
        if let group = service.groups.first(where: { $0.id == gid }) {
            path = [group]
        }
    }

    /// Group members resolved back to FamilyMembers (for real avatars).
    private func resolvedMembers(of group: ChatGroup) -> [FamilyMember] {
        service.members(for: group).compactMap { gm in
            members.first { $0.id.uuidString == gm.memberId }
        }
    }

    private var newGroupButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .glassRoundedRect(AppRadius.lg)
                Text("Grup nou").font(AppFont.headline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .padding(.horizontal, AppSpacing.lg)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.3.sequence.fill",
            title: "Organizează grupuri",
            message: "Creează grupuri separate pentru muncitori, familie sau orice altă echipă."
        )
    }
}

// Lean, self-contained group chat thread. Owns its own MessageService instance
// scoped to the group's group_id (so it never collides with the main chat) and
// takes everything as plain params — no @EnvironmentObject, so it can't crash on
// a missing ancestor when pushed from the Communities sheet.
private struct GroupChatView: View {
    let group: ChatGroup
    let propertyId: UUID?
    let myName: String
    let members: [FamilyMember]
    /// Passed by reference from CommunitiesView (not @EnvironmentObject) so this
    /// view stays crash-safe while still sharing live group/member state.
    /// @ObservedObject so a rename in the settings sheet updates the title live.
    var service: ChatGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var svc = MessageService()
    @State private var text = ""
    @State private var showSettings = false

    private var myId: UUID? { supabase.auth.currentSession?.user.id }
    private var currentGroup: ChatGroup { service.groups.first(where: { $0.id == group.id }) ?? group }

    /// Shown when the user has scrolled away from the latest message (WhatsApp-
    /// style jump-to-bottom button), mirroring ChatView/DirectMessageView.
    @State private var showJumpToLatest = false

    var body: some View {
        VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(svc.messages) { m in
                                MessageBubble(message: m,
                                              isOwn: m.senderId == myId,
                                              members: members)
                                    .id(m.id)
                            }
                            // Jump-button sentinel — visibility follows the marker
                            // entering/leaving the lazy render window (a Geometry-
                            // Reader preference reset to 0 once the marker was
                            // culled, hiding the button on deep scroll-back).
                            Color.clear.frame(height: 1).id("GROUP_CHAT_BOTTOM")
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = false }
                                }
                                .onDisappear {
                                    withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = true }
                                }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: svc.messages.count) { _, _ in
                        withAnimation { proxy.scrollTo("GROUP_CHAT_BOTTOM", anchor: .bottom) }
                    }
                    .overlay(alignment: .bottom) {
                        if showJumpToLatest {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    proxy.scrollTo("GROUP_CHAT_BOTTOM", anchor: .bottom)
                                }
                                HapticFeedback.impact(.light)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(AppFont.headline)
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .glassCircle()
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                            .padding(.bottom, AppSpacing.sm)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Jump to latest message")
                        }
                    }
                }
            composer
        }
        .background(appBackground.ignoresSafeArea())
        // iMessage-style header: no bar, the conversation slides under a
        // progressive blur and only glass controls float on top.
        .overlay(alignment: .top) { ChatTopBlur() }
        .navigationTitle(currentGroup.name.isEmpty ? currentGroup.kindLabel : currentGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatHeaderPill {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: currentGroup.kindIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(currentGroup.name.isEmpty ? currentGroup.kindLabel : currentGroup.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
                .accessibilityLabel("Group settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            GroupSettingsSheet(group: currentGroup, service: service, availableMembers: members) {
                dismiss()
            }
        }
        .task {
            guard let pid = propertyId else { return }
            svc.myName = myName
            await svc.load(propertyId: pid, groupId: group.id)
            // Live thread: messages from other members land without a reload.
            await svc.subscribeRealtime(propertyId: pid)
        }
        .onDisappear {
            let messageSvc = svc
            let groupSvc = service
            let pid = propertyId
            Task {
                await messageSvc.unsubscribeAll()
                // The list behind us shows each group's newest message —
                // refresh it so the row reflects this conversation.
                if let pid { await groupSvc.loadPreviews(propertyId: pid) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Mesaj", text: $text, axis: .vertical)
                .font(.system(size: 16))
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                .liquidGlass(cornerRadius: AppRadius.xl)
            Button {
                let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty, let pid = propertyId else { return }
                text = ""
                MessageSounds.sent()
                Task { try? await svc.send(propertyId: pid, senderName: myName, body: body) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
    }
}

private struct CommunityRow: View {
    let group: ChatGroup
    let memberCount: Int
    /// Newest message ("Ana: vin mâine") + its timestamp, when the group has one.
    let preview: (text: String, date: Date?)?
    /// Members resolved to FamilyMembers, for the overlapping avatar stack.
    let avatarMembers: [FamilyMember]

    private var fallbackLine: String {
        "\(group.kindLabel) · " + String(format: String(localized: "comm_member_count"), memberCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: group.kindIcon)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(group.kindTint)
                .frame(width: 48, height: 48)
                .glassCircle()

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name.isEmpty ? group.kindLabel : group.name)
                    .font(AppFont.headline).foregroundStyle(.primary)
                    .lineLimit(1)
                Text(preview?.text.isEmpty == false ? preview!.text : fallbackLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: 5) {
                if let date = preview?.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineLimit(1)
                }
                if !avatarMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(avatarMembers.prefix(3)) { m in
                            MemberAvatar(member: m, size: 20)
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.2))
                        }
                        if avatarMembers.count > 3 {
                            Text(verbatim: "+\(avatarMembers.count - 3)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.primary.opacity(0.08)))
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.2))
                        }
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityElement(children: .combine)
    }
}

// Group management: rename, add/remove members, delete group.
private struct GroupSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: ChatGroup
    var service: ChatGroupService
    let availableMembers: [FamilyMember]
    /// Called after the group is deleted, so the presenting chat screen pops.
    let onDeleted: () -> Void

    @State private var name: String
    @State private var showAddMembers = false
    @State private var showDeleteConfirm = false

    init(group: ChatGroup, service: ChatGroupService, availableMembers: [FamilyMember],
         onDeleted: @escaping () -> Void) {
        self.group = group
        self.service = service
        self.availableMembers = availableMembers
        self.onDeleted = onDeleted
        _name = State(initialValue: group.name)
    }

    private var currentGroup: ChatGroup { service.groups.first(where: { $0.id == group.id }) ?? group }
    private var currentMembers: [ChatGroupMember] { service.members(for: group) }
    /// Management (rename / members / delete) belongs to the creator only;
    /// everyone else gets a read-only view plus their own notification prefs.
    private var isAdmin: Bool {
        currentGroup.isAdmin(userId: supabase.auth.currentSession?.user.id)
    }
    /// Family members not already in this group, for the "add" picker.
    private var addableMembers: [FamilyMember] {
        let existingIds = Set(currentMembers.map { $0.memberId })
        return availableMembers.filter { !existingIds.contains($0.id.uuidString) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if isAdmin {
                        HStack(spacing: 10) {
                            TextField("Nume grup", text: $name)
                                .font(.system(size: 16))
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                                .liquidGlass(cornerRadius: 14)
                            Button("Salvează") {
                                Task { await service.rename(group, to: name) }
                            }
                            .font(AppFont.footnoteEmphasis)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                      || name == group.name)
                        }
                    }

                    // Every member controls their own alerts for this group —
                    // mute + tones keyed by the group id, the same key the
                    // incoming-message sound and disappearing timer use.
                    SettingsGroup(title: "Notificări") {
                        NavSettingsRow(icon: "bell.fill", color: .red, label: "Notificări chat") {
                            ConversationNotificationsView(
                                convId: group.id.uuidString,
                                subtitle: currentGroup.name.isEmpty ? currentGroup.kindLabel
                                                                    : currentGroup.name)
                        }
                    }

                    HStack {
                        Text("Membri").font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                        if isAdmin {
                            Button { showAddMembers = true } label: {
                                Label("Adaugă", systemImage: "person.badge.plus")
                                    .font(AppFont.captionEmphasis)
                            }
                            .disabled(addableMembers.isEmpty)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(currentMembers) { m in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                                    Text(String(m.memberName.prefix(1)).uppercased())
                                        .font(AppFont.headline).foregroundStyle(Color.accentColor)
                                }
                                Text(m.memberName).font(AppFont.body)
                                Spacer()
                                if m.role == "admin" {
                                    Text("Admin").font(AppFont.captionStrong)
                                        .foregroundStyle(Color.accentColor)
                                } else if isAdmin {
                                    Button {
                                        Task { await service.removeMember(m, from: group) }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red.opacity(0.85))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(m.memberName)")
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.sm)
                            .liquidGlass(cornerRadius: 14)
                        }
                    }

                    if isAdmin {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Șterge grupul", systemImage: "trash")
                                .font(AppFont.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(currentGroup.name.isEmpty ? currentGroup.kindLabel : currentGroup.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gata") { dismiss() } } }
            .sheet(isPresented: $showAddMembers) {
                AddGroupMembersSheet(members: addableMembers) { selected in
                    showAddMembers = false
                    Task { await service.addMembers(selected, to: group) }
                }
            }
            .confirmationDialog("Ștergi acest grup?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Șterge grupul", role: .destructive) {
                    Task {
                        await service.delete(group)
                        dismiss()
                        onDeleted()
                    }
                }
                Button("Anulează", role: .cancel) {}
            } message: {
                Text("Mesajele acestui grup vor fi șterse definitiv.")
            }
        }
    }
}

private struct AddGroupMembersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [FamilyMember]
    let onAdd: ([FamilyMember]) -> Void

    @State private var selectedIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(members) { m in
                        Button {
                            if selectedIds.contains(m.id) { selectedIds.remove(m.id) }
                            else { selectedIds.insert(m.id) }
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatar(member: m, size: 32)
                                Text(m.name).font(AppFont.body).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selectedIds.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(selectedIds.contains(m.id) ? Color.accentColor : Color.primary.opacity(0.25))
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                            .liquidGlass(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Adaugă membri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulează") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adaugă") { onAdd(members.filter { selectedIds.contains($0.id) }) }
                        .disabled(selectedIds.isEmpty)
                }
            }
        }
    }
}

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [FamilyMember]
    let onCreate: (String, String, [FamilyMember]) -> Void

    @State private var name = ""
    @State private var kind = "custom"
    @State private var selectedIds: Set<UUID> = []

    private let kinds: [(String, String, String)] = [
        ("family", "Familie", "house.fill"),
        ("work",   "Muncă",   "hammer.fill"),
        ("custom", "Custom",  "person.3.fill")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Nume grup", text: $name)
                        .font(.system(size: 16))
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                        .liquidGlass(cornerRadius: 14)

                    HStack(spacing: 10) {
                        ForEach(kinds, id: \.0) { k in
                            Button { kind = k.0 } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.2).font(.system(size: 20))
                                    Text(k.1).font(.system(size: 13, weight: .medium))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                                .background(kind == k.0 ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(kind == k.0 ? Color.accentColor : Color.primary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Membri").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    VStack(spacing: 8) {
                        ForEach(members) { m in
                            Button {
                                if selectedIds.contains(m.id) { selectedIds.remove(m.id) }
                                else { selectedIds.insert(m.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    MemberAvatar(member: m, size: 32)
                                    Text(m.name).font(AppFont.body).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedIds.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIds.contains(m.id) ? Color.accentColor : Color.primary.opacity(0.25))
                                }
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                                .liquidGlass(cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Grup nou")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulează") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Creează") {
                        let selected = members.filter { selectedIds.contains($0.id) }
                        onCreate(name.trimmingCharacters(in: .whitespaces), kind, selected)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

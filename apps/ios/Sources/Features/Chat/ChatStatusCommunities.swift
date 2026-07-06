import SwiftUI

// MARK: - Status / Stories
//
// Backed by the status_updates / status_views tables (24h expiry + per-viewer
// seen tracking) via StatusService. Posting uploads an image and inserts a row.

struct StatusView: View {
    var propertyId: UUID?
    let myName: String
    let members: [FamilyMember]
    var onAddStatus: () -> Void = {}

    private let status = StatusService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: StatusGroup?

    private var myId: UUID? { supabase.auth.currentSession?.user.id }
    private var myInitial: String { String(myName.prefix(1)).uppercased() }
    private var myGroup: StatusGroup? { status.myGroup(myId: myId) }
    private var others: [StatusGroup] { status.otherGroups(myId: myId) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    myStatusRow

                    if !others.isEmpty {
                        Text("Recent updates")
                            .font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl)

                        VStack(spacing: 0) {
                            ForEach(others) { g in
                                Button { viewing = g } label: { groupRow(g) }
                                    .buttonStyle(.plain)
                                if g.id != others.last?.id { Divider().padding(.leading, 82) }
                            }
                        }
                        .liquidGlass(cornerRadius: AppRadius.lg)
                        .padding(.horizontal, AppSpacing.lg)
                    } else {
                        Text("No recent updates")
                            .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
                            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.xxs)
                    }

                    Text("Status updates disappear after 24 hours.")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                        .padding(.horizontal, AppSpacing.xl)

                    Spacer(minLength: 20)
                }
                .padding(.top, AppSpacing.sm)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { if let pid = propertyId { await status.load(propertyId: pid) } }
            .fullScreenCover(item: $viewing) { g in
                StoryViewer(group: g, myName: myName, propertyId: propertyId)
            }
        }
    }

    private var myStatusRow: some View {
        Button {
            if let g = myGroup { viewing = g } else { onAddStatus() }
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .strokeBorder(myGroup != nil ? Color.accentColor : Color.clear, lineWidth: 2.5)
                        .background(Circle().fill(Color.accentColor.opacity(0.2)))
                        .overlay(Text(myInitial).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.accentColor))
                        .frame(width: 56, height: 56)
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(Color.accentColor, .white)
                        .offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("My status").font(AppFont.headline).foregroundStyle(.primary)
                    Text(myGroup == nil
                         ? "Tap to add status update"
                         : (myGroup!.items.count == 1 ? "1 update" : "\(myGroup!.items.count) updates"))
                        .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                Spacer()
                if myGroup != nil {
                    Button { onAddStatus() } label: {
                        Image(systemName: "plus").font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor).frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add status")
                }
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .padding(.horizontal, AppSpacing.lg)
        }
        .buttonStyle(.plain)
    }

    private func groupRow(_ g: StatusGroup) -> some View {
        let seen = status.allSeen(g)
        let member = members.first { $0.name == g.authorName }
        return HStack(spacing: 14) {
            Circle()
                .strokeBorder(seen ? Color.primary.opacity(0.2) : Color.accentColor, lineWidth: 2.5)
                .background(Circle().fill((member?.swiftColor ?? .gray).opacity(0.15)))
                .overlay(Text(member?.initials ?? String(g.authorName.prefix(2)).uppercased())
                    .font(AppFont.headline).foregroundStyle(member?.swiftColor ?? .gray))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.authorName).font(.system(size: 16)).foregroundStyle(.primary)
                Text(g.items.count == 1 ? "1 update" : "\(g.items.count) updates")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Text status composer (WhatsApp-style: text on a gradient)

struct TextStatusComposer: View {
    let onPost: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var bgIndex = 0
    @FocusState private var focused: Bool

    private let gradients: [[Color]] = [
        [Color(red: 0.16, green: 0.20, blue: 0.52), Color(red: 0.36, green: 0.20, blue: 0.68)],
        [Color(red: 0.90, green: 0.42, blue: 0.28), Color(red: 0.98, green: 0.70, blue: 0.52)],
        [Color(red: 0.00, green: 0.48, blue: 0.66), Color(red: 0.60, green: 0.79, blue: 0.88)],
        [Color(red: 0.13, green: 0.69, blue: 0.30), Color(red: 0.30, green: 0.85, blue: 0.45)],
        [Color(red: 0.82, green: 0.35, blue: 0.55), Color(red: 0.96, green: 0.66, blue: 0.72)],
        [Color(white: 0.05), Color(white: 0.18)],
    ]

    // The 9:16 card that gets rendered to the posted image.
    private var renderCard: some View {
        ZStack {
            LinearGradient(colors: gradients[bgIndex], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            LinearGradient(colors: gradients[bgIndex], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { bgIndex = (bgIndex + 1) % gradients.count } } label: {
                        Image(systemName: "paintpalette.fill").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    .accessibilityLabel("Change background")
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
                    .padding(.horizontal, 24)
                Spacer()
                Button { post() } label: {
                    HStack(spacing: 8) {
                        Text("Share").font(AppFont.headline)
                        Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.52))
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .padding(.bottom, 20)
            }
            .padding(AppSpacing.lg)
        }
        .onAppear { focused = true }
    }

    @MainActor private func post() {
        let renderer = ImageRenderer(content: renderCard)
        renderer.scale = 3
        if let img = renderer.uiImage { onPost(img) }
        dismiss()
    }
}

// MARK: - Full-screen story viewer

struct StoryViewer: View {
    let group: StatusGroup
    let myName: String
    var propertyId: UUID?

    private let status = StatusService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var viewers: [String] = []
    @State private var showViewers = false
    @State private var mediaURL: URL?

    private var item: StatusUpdate? { group.items.indices.contains(index) ? group.items[index] : nil }
    private var isMine: Bool { supabase.auth.currentSession?.user.id == group.authorId }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item?.mediaUrl != nil {
                StorageImage(url: mediaURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Tap zones (below the controls so the X / Seen-by buttons stay tappable):
            // left = previous, right = next. Invisible zones need explicit
            // accessibility traits/labels — VoiceOver has nothing else to read here.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { prev() }
                    .accessibilityLabel("Previous story")
                    .accessibilityAddTraits(.isButton)
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
                    .accessibilityLabel("Next story")
                    .accessibilityAddTraits(.isButton)
            }

            VStack {
                // Segmented progress bar
                HStack(spacing: 4) {
                    ForEach(group.items.indices, id: \.self) { i in
                        Capsule()
                            .fill(i <= index ? Color.white : Color.white.opacity(0.35))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 10).padding(.top, AppSpacing.sm)

                HStack(spacing: 10) {
                    Text(group.authorName).font(AppFont.subheadline).foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(AppFont.headline).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, AppSpacing.lg).padding(.top, AppSpacing.sm)

                Spacer()

                if let cap = item?.caption, !cap.isEmpty {
                    Text(cap).font(.system(size: 16)).foregroundStyle(.white)
                        .padding(AppSpacing.md).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.md))
                        .padding(.horizontal, AppSpacing.xl)
                }

                if isMine {
                    Button { Task { viewers = await status.viewers(of: item?.id ?? group.id); showViewers = true } } label: {
                        Label("Seen by", systemImage: "eye.fill")
                            .font(AppFont.footnote).foregroundStyle(.white)
                            .padding(.vertical, 10)
                    }
                }
                Spacer().frame(height: 24)
            }
        }
        .task(id: index) {
            if let item, propertyId != nil { await status.markViewed(item, viewerName: myName) }
            if let m = item?.mediaUrl { mediaURL = await ChatMedia.resolve(m) } else { mediaURL = nil }
        }
        .confirmationDialog("Seen by", isPresented: $showViewers, titleVisibility: .visible) {
            // listed in the message below
        } message: {
            Text(viewers.isEmpty ? "No views yet" : viewers.joined(separator: ", "))
        }
    }

    private func next() {
        if index < group.items.count - 1 { index += 1 } else { dismiss() }
    }
    private func prev() {
        if index > 0 { index -= 1 }
    }
}

// MARK: - Communities (UI shell)
//
// Communities — multiple named chat groups per property (workers, family, …),
// backed by chat_groups / chat_group_members (migration 078). This screen lists
// and creates groups and manages their members.

struct CommunitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = ChatGroupService()

    var propertyId: UUID? = nil
    var members: [FamilyMember] = []
    var myName: String = "Me"

    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    newGroupButton

                    if service.groups.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(service.groups) { group in
                                NavigationLink {
                                    GroupChatView(group: group,
                                                  propertyId: propertyId,
                                                  myName: myName,
                                                  members: members,
                                                  service: service)
                                } label: {
                                    CommunityRow(group: group, memberCount: service.members(for: group).count)
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
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showCreate) {
                CreateGroupSheet(members: members) { name, kind, selected in
                    showCreate = false
                    guard let pid = propertyId else { return }
                    Task { await service.create(propertyId: pid, name: name, kind: kind,
                                                selected: selected, myName: myName) }
                }
            }
            .task { if let pid = propertyId { await service.load(propertyId: pid) } }
        }
    }

    private var newGroupButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
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

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: group.kindIcon).font(.system(size: 20)).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name.isEmpty ? group.kindLabel : group.name)
                    .font(AppFont.headline).foregroundStyle(.primary)
                Text("\(group.kindLabel) · \(memberCount) membri")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer()
            Image(systemName: "chevron.right").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
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
    /// Family members not already in this group, for the "add" picker.
    private var addableMembers: [FamilyMember] {
        let existingIds = Set(currentMembers.map { $0.memberId })
        return availableMembers.filter { !existingIds.contains($0.id.uuidString) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
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

                    HStack {
                        Text("Membri").font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                        Button { showAddMembers = true } label: {
                            Label("Adaugă", systemImage: "person.badge.plus")
                                .font(AppFont.captionEmphasis)
                        }
                        .disabled(addableMembers.isEmpty)
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
                                } else {
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

import SwiftUI
import Supabase
import PhotosUI

// MARK: - Conversations list (WhatsApp-style main chat screen)

struct ConversationsView: View {
    @Environment(MessageService.self) private var messageService
    @Environment(DirectMessageService.self) private var directMessageService
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ProfileService.self) private var profileService
    @Environment(StickerService.self) private var stickerService
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(AppRouter.self) private var router

    @State private var showAddMember = false
    @State private var showNewConversation = false
    @State private var showAddContact = false
    @State private var showContactsPicker = false
    @State private var showStatus = false
    @State private var showCommunities = false
    // One presentation slot for the status composer covers (camera + text) —
    // two separate `.fullScreenCover(isPresented:)` on one view conflict.
    @State private var statusComposer: StatusComposerKind?
    @State private var showStatusOptions = false
    @State private var showStoryLibrary = false
    @State private var storyPickerItem: PhotosPickerItem?
    @State private var storyError: String?

    private enum StatusComposerKind: Int, Identifiable { case camera, text; var id: Int { rawValue } }
    @State private var filter: ConvFilter = .all
    @State private var archivedIds: Set<String> = []
    @State private var favoriteIds: Set<String> = []
    @State private var pinnedIds: Set<String> = []
    @State private var mutedIds: Set<String> = []
    @State private var manualUnreadIds: Set<String> = []
    @State private var lockedIds: Set<String> = []
    @State private var clearCandidate: ConversationEntry?
    @State private var deleteCandidate: ConversationEntry?
    @State private var showArchived = false
    @State private var lockedRevealed = false
    @State private var searchText = ""
    @State private var navTarget: String? = nil

    private var hasLockedChats: Bool { nonArchived.contains { ChatLockStore.isLocked($0.id) } }

    enum ConvFilter: CaseIterable {
        case all, unread, favorites, groups, family
        var label: String {
            switch self {
            case .all: return "Toate"
            case .unread: return "Necitite"
            case .favorites: return "Favorite"
            case .groups: return "Grupuri"
            case .family: return "Familie"
            }
        }
    }

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    private var nonArchived: [ConversationEntry] { sortedConversations.filter { !archivedIds.contains($0.id) } }
    private var archivedList: [ConversationEntry] { sortedConversations.filter { archivedIds.contains($0.id) } }

    private func isUnread(_ e: ConversationEntry) -> Bool { e.unread > 0 || manualUnreadIds.contains(e.id) }

    private var visibleConversations: [ConversationEntry] {
        let filtered = nonArchived.filter { e in
            // Secured conversations stay hidden until unlocked with Face ID.
            if ChatLockStore.isLocked(e.id) && !lockedRevealed { return false }
            switch filter {
            case .all:       return true
            case .unread:    return isUnread(e)
            case .favorites: return favoriteIds.contains(e.id)
            case .groups:    return e.isGroup
            case .family:    return !e.isGroup
            }
        }
        // pinned conversations float to the top, otherwise keep newest-first order
        return filtered.sorted { a, b in
            let pa = pinnedIds.contains(a.id), pb = pinnedIds.contains(b.id)
            if pa != pb { return pa }
            switch (a.date, b.date) {
            case (.some(let da), .some(let db)): return da > db
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
    }

    private var searchedConversations: [ConversationEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return visibleConversations }
        // Global search: match the conversation name, its last-message preview,
        // or the body of any loaded message in that conversation.
        return nonArchived.filter { entry in
            // Don't surface secured chats in search until unlocked.
            if ChatLockStore.isLocked(entry.id) && !lockedRevealed { return false }
            if entry.name.localizedCaseInsensitiveContains(q) { return true }
            if entry.preview.localizedCaseInsensitiveContains(q) { return true }
            if entry.isGroup {
                return messageService.messages.contains {
                    ($0.body ?? "").localizedCaseInsensitiveContains(q)
                }
            } else if let member = entry.member {
                return directMessageService.messages(with: member.name, myName: myName)
                    .contains { $0.body.localizedCaseInsensitiveContains(q) }
            }
            return false
        }
    }

    private func loadFlags() {
        archivedIds = Set(UserDefaults.standard.stringArray(forKey: "chat.archived") ?? [])
        favoriteIds = Set(UserDefaults.standard.stringArray(forKey: "chat.favorites") ?? [])
        pinnedIds = Set(UserDefaults.standard.stringArray(forKey: "chat.pinned") ?? [])
        mutedIds = Set(UserDefaults.standard.stringArray(forKey: "chat.muted") ?? [])
        manualUnreadIds = Set(UserDefaults.standard.stringArray(forKey: "chat.manualUnread") ?? [])
        lockedIds = ChatLockStore.locked()
    }

    /// Reconciles pin/mute/archive + block with Supabase so they sync across
    /// devices. Supabase is the source of truth; if it has no rows yet (first run
    /// for this user) the existing local prefs are migrated up instead of wiped.
    private func syncRemotePrefs() async {
        let pid = propertyService.primary?.id
        let prefs = await ChatPrefsSync.load()
        if prefs.isEmpty {
            let ids = pinnedIds.union(mutedIds).union(archivedIds)
            for id in ids {
                await ChatPrefsSync.upsert(convId: id,
                                           pinned: pinnedIds.contains(id),
                                           muted: mutedIds.contains(id),
                                           archived: archivedIds.contains(id),
                                           propertyId: pid)
            }
        } else {
            pinnedIds   = Set(prefs.filter { $0.pinned }.map { $0.convId })
            mutedIds    = Set(prefs.filter { $0.muted }.map { $0.convId })
            archivedIds = Set(prefs.filter { $0.archived }.map { $0.convId })
            UserDefaults.standard.set(Array(pinnedIds),   forKey: "chat.pinned")
            UserDefaults.standard.set(Array(mutedIds),    forKey: "chat.muted")
            UserDefaults.standard.set(Array(archivedIds), forKey: "chat.archived")
        }
        // Bring the "clear conversation" cutoff across from other devices.
        for r in prefs { ConversationClearStore.applyRemote(r.convId, iso: r.clearedAt) }
        // Disappearing-message TTLs are conversation state, not device state.
        if let pid { await ChatDisappearStore.syncFromServer(propertyId: pid, myName: myName) }

        // Reflect server-side blocks locally (chat_blocks is keyed by name).
        let blockedNames = await ChatBlockSync.load()
        for m in familyService.members {
            ChatBlockStore.setBlocked(m.id.uuidString, blockedNames.contains(m.name))
        }
    }
    private func toggleLocked(_ id: String) {
        let newVal = !lockedIds.contains(id)
        ChatLockStore.setLocked(id, newVal)
        if newVal { lockedIds.insert(id) } else { lockedIds.remove(id) }
        HapticFeedback.selection()
    }
    private func toggleBlock(_ member: FamilyMember) {
        let id = member.id.uuidString
        let willBlock = !ChatBlockStore.isBlocked(id)
        ChatBlockStore.setBlocked(id, willBlock)
        // Enforce server-side: chat_blocks is keyed by the blocked person's display
        // name (so the dm_insert policy can reject them by sender_name).
        let pid = propertyService.primary?.id
        Task {
            if willBlock { await ChatBlockSync.block(name: member.name, myName: myName, propertyId: pid) }
            else { await ChatBlockSync.unblock(name: member.name) }
        }
        HapticFeedback.warning()
    }
    private func toggle(_ id: String, in set: inout Set<String>, key: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        UserDefaults.standard.set(Array(set), forKey: key)
    }
    private func toggleArchived(_ id: String) { toggle(id, in: &archivedIds, key: "chat.archived"); syncPrefs(id) }
    private func toggleFavorite(_ id: String) { toggle(id, in: &favoriteIds, key: "chat.favorites") }
    private func togglePinned(_ id: String)   { toggle(id, in: &pinnedIds, key: "chat.pinned"); syncPrefs(id) }
    private func toggleMuted(_ id: String)    { toggle(id, in: &mutedIds, key: "chat.muted"); syncPrefs(id) }
    private func toggleUnread(_ id: String)   { toggle(id, in: &manualUnreadIds, key: "chat.manualUnread") }

    /// Pushes the current pin/mute/archive state of one conversation to Supabase.
    private func syncPrefs(_ id: String) {
        let pid = propertyService.primary?.id
        let pinned = pinnedIds.contains(id), muted = mutedIds.contains(id), archived = archivedIds.contains(id)
        Task { await ChatPrefsSync.upsert(convId: id, pinned: pinned, muted: muted, archived: archived, propertyId: pid) }
    }

    private func markAllRead() {
        manualUnreadIds.removeAll()
        UserDefaults.standard.set([String](), forKey: "chat.manualUnread")
        messageService.resetUnread()
        for m in familyService.members { directMessageService.markRead(partner: m.name) }
        if let pid = propertyService.primary?.id {
            Task { await messageService.markRead(propertyId: pid, readerName: myName) }
        }
        HapticFeedback.success()
    }

    @MainActor
    private func sendStory(_ image: UIImage) async {
        guard let pid = propertyService.primary?.id else { return }
        if let err = await StatusService.shared.post(propertyId: pid, authorName: myName, image: image, caption: nil) {
            storyError = err
            HapticFeedback.warning()
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                headerBar
                if sortedConversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await MemberDirectory.shared.loadIfNeeded() }
        .task {
            guard let pid = propertyService.primary?.id else { return }
            directMessageService.myName = myName
            await directMessageService.load(propertyId: pid, myName: myName)
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
            await syncRemotePrefs()
        }
        .task {
            // Keep the group conversation preview + unread badge live from the
            // list itself, so they're correct even when the group thread was
            // never opened this session (idempotent subscribe).
            guard let pid = propertyService.primary?.id else { return }
            messageService.myName = myName
            await propertyService.loadGroupChatName()
            await messageService.load(propertyId: pid)
            await messageService.subscribeRealtime(propertyId: pid)
        }
        .onAppear { loadFlags() }
        .navigationDestination(item: $navTarget) { id in
            if id == "group" {
                groupChatDestination
            } else if let member = familyService.members.first(where: { $0.id.uuidString == id }) {
                DirectMessageView(member: member)
            }
        }
        // NB: no unsubscribe here. Pushing a DM thread fires this view's
        // onDisappear, and tearing the channel down there left the open thread
        // silent until you popped back. The channel is property-scoped and
        // lightweight, so it stays live for the chat session (re-subscribing is
        // idempotent); it's cleaned up when the service is torn down.
        .alert("Story not posted", isPresented: Binding(
            get: { storyError != nil }, set: { if !$0 { storyError = nil } }
        )) {
            Button("OK", role: .cancel) { storyError = nil }
        } message: {
            Text(storyError ?? "")
        }
        .sheet(isPresented: $showAddMember) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id,
                                 propertyName: propertyService.primary?.name)
                .environment(familyService)
        }
        .sheet(isPresented: $showContactsPicker) {
            ContactsInviteView(
                onOpenMember: { member in
                    showContactsPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { navTarget = member.id.uuidString }
                },
                onManualEntry: {
                    showContactsPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showAddContact = true }
                }
            )
            .environment(familyService)
            .environment(propertyService)
        }
        .sheet(isPresented: $showAddContact) {
            AddContactView()
                .environment(familyService)
                .environment(propertyService)
        }
        .sheet(isPresented: $showStatus) {
            StatusView(propertyId: propertyService.primary?.id,
                       myName: myName,
                       members: familyService.members,
                       // Dismiss the sheet first, then present the composer — presenting
                       // a cover while the sheet is still dismissing swallows it.
                       onAddStatus: {
                           showStatus = false
                           DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showStatusOptions = true }
                       })
        }
        .confirmationDialog("Add to status", isPresented: $showStatusOptions, titleVisibility: .visible) {
            Button("Camera") { statusComposer = .camera }
            Button("Photo Library") { showStoryLibrary = true }
            Button("Write text") { statusComposer = .text }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showStoryLibrary, selection: $storyPickerItem, matching: .images)
        .onChange(of: storyPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await sendStory(img)
                }
                storyPickerItem = nil
            }
        }
        .sheet(isPresented: $showCommunities) {
            CommunitiesView(propertyId: propertyService.primary?.id,
                            members: familyService.members,
                            myName: myName)
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationSheet(members: familyService.members,
                                 groupName: propertyService.groupChatDisplayName) { id in
                showNewConversation = false
                navTarget = id
            } onAddMember: {
                showNewConversation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showContactsPicker = true }
            }
        }
        .fullScreenCover(item: $statusComposer) { kind in
            switch kind {
            case .camera:
                CameraPickerView { img in Task { await sendStory(img) } }
                    .ignoresSafeArea()
                    .background(Color.black.ignoresSafeArea())
            case .text:
                TextStatusComposer { image in Task { await sendStory(image) } }
            }
        }
        .modifier(ConversationDestructiveDialogs(
            clearCandidate: $clearCandidate,
            deleteCandidate: $deleteCandidate,
            onClear: { e in
                ConversationClearStore.clear(e.id); markConversationRead(e); HapticFeedback.success()
            },
            onDelete: { e in
                ConversationClearStore.clear(e.id)
                if !archivedIds.contains(e.id) { toggleArchived(e.id) }
                markConversationRead(e); HapticFeedback.success()
            }))
    }

    // MARK: - Custom header (independent round buttons + title + search)

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Menu {
                    Button { showStatus = true } label: { Label("Status", systemImage: "circle.dashed") }
                    Button { showCommunities = true } label: { Label("Communities", systemImage: "person.3") }
                    Button { showContactsPicker = true } label: { Label("Add contact", systemImage: "person.crop.circle.badge.plus") }
                    Button { markAllRead() } label: { Label("Mark all as read", systemImage: "checkmark.message") }
                    if !archivedList.isEmpty {
                        Button { withAnimation { showArchived = true } } label: { Label("Archived", systemImage: "archivebox") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .glassCircle()
                }
                .accessibilityLabel("More options")
                Spacer()
                Button { statusComposer = .camera } label: {
                    Image(systemName: "camera.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share a moment")
                Button { showNewConversation = true } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 40, height: 40)
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New conversation")
            }

            Text("Chat")
                .font(.system(size: 32, weight: .bold))

            searchField
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Conversation list

    private var conversationList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if showArchived {
                    archivedTopBar
                } else {
                    filterChips
                }

                let entries = showArchived ? archivedList : searchedConversations
                LazyVStack(spacing: 8) {
                    if !showArchived && searchText.isEmpty && filter == .all {
                        Button { HapticFeedback.impact(.light); router.navigate(to: .aria) } label: { ariaRow }
                            .buttonStyle(.plain)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    }

                    if hasLockedChats && !showArchived && searchText.isEmpty {
                        Button {
                            if lockedRevealed {
                                withAnimation { lockedRevealed = false }
                            } else {
                                Task {
                                    if await BiometricAuth.authenticate(reason: "Unlock secured chats") {
                                        withAnimation { lockedRevealed = true }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: lockedRevealed ? "lock.open.fill" : "lock.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                    .frame(width: 40)
                                Text(lockedRevealed ? "Locked chats (visible)" : "Locked chats")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(AppFont.captionEmphasis)
                                    .foregroundStyle(Color.primary.opacity(0.25))
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(cornerRadius: AppRadius.lg)
                    }

                    ForEach(entries) { entry in
                        SwipeableRow(
                            leading: leadingActions(entry),
                            trailing: trailingActions(entry)
                        ) {
                            Button { navTarget = entry.id } label: {
                                ConversationRowView(
                                    entry: entry,
                                    myName: myName,
                                    members: familyService.members,
                                    propertyPhotoUrl: propertyService.primary?.photoUrl,
                                    muted: mutedIds.contains(entry.id),
                                    pinned: pinnedIds.contains(entry.id),
                                    forceUnread: manualUnreadIds.contains(entry.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu { conversationMenu(entry) }
                        }
                    }

                    if !showArchived && searchText.isEmpty && !archivedList.isEmpty {
                        Button { withAnimation { showArchived = true } } label: { archivedRow }
                            .buttonStyle(.plain)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xxl)
        }
    }

    @ViewBuilder
    private func conversationMenu(_ entry: ConversationEntry) -> some View {
        let unread = isUnread(entry)
        Button {
            if unread { markConversationRead(entry) } else { markConversationUnread(entry) }
        } label: {
            Label(unread ? "Marchează citit" : "Marchează necitit",
                  systemImage: unread ? "checkmark.message" : "message.badge")
        }
        Button { togglePinned(entry.id) } label: {
            Label(pinnedIds.contains(entry.id) ? "Detașează" : "Fixează", systemImage: "pin")
        }
        Button { toggleMuted(entry.id) } label: {
            Label(mutedIds.contains(entry.id) ? "Pornește sunetul" : "Oprește sunetul",
                  systemImage: mutedIds.contains(entry.id) ? "bell" : "bell.slash")
        }
        Button { toggleLocked(entry.id) } label: {
            Label(lockedIds.contains(entry.id) ? "Anulează secretizarea" : "Secretizează conversația",
                  systemImage: lockedIds.contains(entry.id) ? "lock.open" : "lock")
        }
        Button { toggleFavorite(entry.id) } label: {
            Label(favoriteIds.contains(entry.id) ? "Scoate din listă" : "Adaugă în listă",
                  systemImage: favoriteIds.contains(entry.id) ? "star.slash" : "star")
        }
        Button { toggleArchived(entry.id) } label: {
            Label(archivedIds.contains(entry.id) ? "Dezarhivează" : "Arhivează", systemImage: "archivebox")
        }
        Divider()
        conversationDestructiveItems(entry)
    }

    @ViewBuilder
    private func conversationDestructiveItems(_ entry: ConversationEntry) -> some View {
        if !entry.isGroup, let m = entry.member {
            let blocked = ChatBlockStore.isBlocked(m.id.uuidString)
            Button(role: .destructive) { toggleBlock(m) } label: {
                Label(blocked ? "Deblochează pe \(m.name)" : "Blochează pe \(m.name)",
                      systemImage: blocked ? "hand.raised.slash" : "hand.raised")
            }
        }
        Button(role: .destructive) { clearCandidate = entry } label: {
            Label("Golește conversația", systemImage: "xmark.circle")
        }
        if !entry.isGroup {
            Button(role: .destructive) { deleteCandidate = entry } label: {
                Label("Șterge conversația", systemImage: "trash")
            }
        }
    }

    private func leadingActions(_ entry: ConversationEntry) -> [ConvSwipeAction] {
        let unread = isUnread(entry)
        return [
            unread
                ? ConvSwipeAction(label: "Citit", icon: "checkmark.message.fill", color: .gray) { markConversationRead(entry) }
                : ConvSwipeAction(label: "Necitit", icon: "message.badge.fill", color: .blue) { markConversationUnread(entry) },
            ConvSwipeAction(label: pinnedIds.contains(entry.id) ? "Detașează" : "Fixează",
                            icon: pinnedIds.contains(entry.id) ? "pin.slash.fill" : "pin.fill",
                            color: .green) { togglePinned(entry.id) }
        ]
    }

    private func trailingActions(_ entry: ConversationEntry) -> [ConvSwipeAction] {
        let muted = mutedIds.contains(entry.id)
        return [
            ConvSwipeAction(label: muted ? "Activează" : "Oprește",
                            icon: muted ? "bell.fill" : "bell.slash.fill",
                            color: .orange) { toggleMuted(entry.id) },
            ConvSwipeAction(label: archivedIds.contains(entry.id) ? "Dezarhivează" : "Arhivează",
                            icon: "archivebox.fill", color: .gray) { toggleArchived(entry.id) }
        ]
    }

    private func markConversationRead(_ entry: ConversationEntry) {
        manualUnreadIds.remove(entry.id)
        UserDefaults.standard.set(Array(manualUnreadIds), forKey: "chat.manualUnread")
        if entry.isGroup {
            messageService.resetUnread()
            if let pid = propertyService.primary?.id {
                Task { await messageService.markRead(propertyId: pid, readerName: myName) }
            }
        } else if let m = entry.member {
            directMessageService.markRead(partner: m.name)
        }
    }

    private func markConversationUnread(_ entry: ConversationEntry) {
        manualUnreadIds.insert(entry.id)
        UserDefaults.standard.set(Array(manualUnreadIds), forKey: "chat.manualUnread")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Caută grupuri, persoane…", text: $searchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, 10)
        .background(Color.primary.opacity(AppOpacity.hairline), in: Capsule())
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConvFilter.allCases, id: \.self) { f in
                    Button { filter = f } label: {
                        Text(f.label)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(filter == f ? Color.accentColor : Color.primary.opacity(0.6))
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, 7)
                            .background(filter == f ? Color.accentColor.opacity(0.15) : Color.primary.opacity(AppOpacity.hairline),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private var archivedTopBar: some View {
        HStack(spacing: 10) {
            Button { withAnimation { showArchived = false } } label: {
                Image(systemName: "chevron.left")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel(Text("Back"))
            Text("Conversații arhivate")
                .font(.system(size: 17, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private var archivedRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08))
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            .frame(width: 52, height: 52)
            Text("Conversații arhivate")
                .font(AppFont.headline)
            Spacer()
            Text("\(archivedList.count)")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            Image(systemName: "chevron.right")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var ariaRow: some View {
        HStack(spacing: 12) {
            ARIAAvatar(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(UserDefaults.standard.string(forKey: "prvio.aria.customName") ?? "ARIA")
                    .font(AppFont.headline)
                Text("AI Assistant").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Image(systemName: "chevron.right").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // Injects all environment objects ChatView needs (already in env chain, but explicit for clarity)
    @ViewBuilder
    private var groupChatDestination: some View {
        ChatView()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Nicio conversație",
                message: "Adaugă membri familiei pentru a începe."
            )
            Spacer()
        }
    }

    // MARK: - Data

    var sortedConversations: [ConversationEntry] {
        var items: [ConversationEntry] = []

        // Group chat entry
        let lastGroupMsg = messageService.messages.last
        let groupPreview: String = {
            guard let m = lastGroupMsg else { return "Nicio activitate" }
            let isOwn = m.senderId == supabase.auth.currentSession?.user.id
            let prefix = isOwn ? "Tu: " : (m.senderName.components(separatedBy: " ").first.map { "\($0): " } ?? "")
            if m.deletedForAll == true { return prefix + "🚫 Mesaj șters" }
            if let body = m.body, !body.isEmpty { return prefix + body }
            switch m.attachmentType {
            case "image":    return prefix + "📷 Imagine"
            case "video":    return prefix + "🎥 Videoclip"
            case "audio":    return prefix + "🎤 Mesaj vocal"
            case "location": return prefix + "📍 Locație"
            case "file":     return prefix + "📎 Fișier"
            case "sticker":  return prefix + "😀 Sticker"
            case "poll":     return prefix + "📊 Sondaj"
            case "event":    return prefix + "📅 Eveniment"
            default:         return prefix + "Mesaj"
            }
        }()

        items.append(ConversationEntry(
            id: "group",
            name: propertyService.groupChatDisplayName,
            preview: groupPreview,
            date: lastGroupMsg.flatMap { parseISODate($0.createdAt) },
            unread: propertyService.primary.map {
                messageService.groupUnread(propertyId: $0.id, myId: supabase.auth.currentSession?.user.id)
            } ?? 0,
            isGroup: true,
            member: nil
        ))

        // DM entries — WhatsApp-style: a person appears in the list only once
        // the conversation has at least one message (either direction). Newly
        // added members stay reachable via the "+" new-conversation flow.
        for member in familyService.members {
            guard let last = directMessageService.lastMessage(with: member.name, myName: myName) else {
                continue
            }
            let preview: String = {
                if last.deletedForAll == true { return "🚫 Mesaj șters" }
                let prefix = last.senderName == myName ? "Tu: " : ""
                return prefix + last.body
            }()
            items.append(ConversationEntry(
                id: member.id.uuidString,
                name: member.name,
                preview: preview,
                date: parseISODate(last.createdAt),
                unread: directMessageService.unreadCount(from: member.name, myName: myName),
                isGroup: false,
                member: member
            ))
        }

        return items.sorted { a, b in
            switch (a.date, b.date) {
            case (.some(let da), .some(let db)): return da > db
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.isGroup && !b.isGroup
            }
        }
    }

    private func parseISODate(_ s: String) -> Date? { ISODate.date(from: s) }
}

// MARK: - Destructive conversation dialogs (kept off the main body chain)

private struct ConversationDestructiveDialogs: ViewModifier {
    @Binding var clearCandidate: ConversationEntry?
    @Binding var deleteCandidate: ConversationEntry?
    let onClear: (ConversationEntry) -> Void
    let onDelete: (ConversationEntry) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Golești conversația?",
                                isPresented: Binding(get: { clearCandidate != nil },
                                                     set: { if !$0 { clearCandidate = nil } }),
                                titleVisibility: .visible) {
                Button("Golește", role: .destructive) {
                    if let e = clearCandidate { onClear(e) }
                    clearCandidate = nil
                }
                Button("Anulează", role: .cancel) { clearCandidate = nil }
            } message: {
                Text("Mesajele vor fi ascunse de pe acest dispozitiv.")
            }
            .confirmationDialog("Ștergi conversația?",
                                isPresented: Binding(get: { deleteCandidate != nil },
                                                     set: { if !$0 { deleteCandidate = nil } }),
                                titleVisibility: .visible) {
                Button("Șterge", role: .destructive) {
                    if let e = deleteCandidate { onDelete(e) }
                    deleteCandidate = nil
                }
                Button("Anulează", role: .cancel) { deleteCandidate = nil }
            } message: {
                Text("Conversația va fi golită și arhivată pe acest dispozitiv.")
            }
    }
}

// MARK: - ConversationEntry

struct ConversationEntry: Identifiable {
    let id: String
    let name: String
    let preview: String
    let date: Date?
    let unread: Int
    let isGroup: Bool
    let member: FamilyMember?

    var formattedTime: String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Ieri"
        } else if cal.dateComponents([.day], from: date, to: Date()).day ?? 0 < 7 {
            let f = DateFormatter(); f.dateFormat = "EEEE"; f.locale = .current
            return f.string(from: date)
        } else {
            let f = DateFormatter(); f.dateFormat = "dd.MM.yy"
            return f.string(from: date)
        }
    }
}

// MARK: - Conversation Row

private struct ConversationRowView: View {
    let entry: ConversationEntry
    let myName: String
    let members: [FamilyMember]
    var propertyPhotoUrl: String? = nil
    var muted: Bool = false
    var pinned: Bool = false
    var forceUnread: Bool = false

    private var isUnread: Bool { entry.unread > 0 || forceUnread }

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: isUnread ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    Spacer()
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    Text(entry.formattedTime)
                        .font(.system(size: 12))
                        .foregroundStyle(isUnread ? Color.accentColor : Color.primary.opacity(AppOpacity.disabled))
                }
                HStack {
                    Text(entry.preview)
                        .font(.system(size: 14))
                        .foregroundStyle(isUnread ? Color.primary.opacity(0.65) : Color.primary.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if entry.unread > 0 {
                        Text("\(entry.unread)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(muted ? Color.primary.opacity(AppOpacity.disabled) : Color.accentColor, in: Capsule())
                            .fixedSize()
                    } else if forceUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if entry.isGroup {
            GroupChatAvatar(members: members, photoUrl: propertyPhotoUrl)
        } else if let member = entry.member {
            MemberCircleAvatar(member: member, size: 52)
        }
    }
}

// MARK: - Member circle avatar

private struct MemberCircleAvatar: View {
    let member: FamilyMember
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(member.swiftColor.opacity(0.18))
            Text(member.initials)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(member.swiftColor)
        }
    }
}

// MARK: - Group Chat Avatar (stacked initials)

private struct GroupChatAvatar: View {
    let members: [FamilyMember]
    var photoUrl: String? = nil

    var body: some View {
        ZStack {
            if let urlStr = photoUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 52, height: 52)
    }

    @ViewBuilder
    private var fallbackAvatar: some View {
        if members.count >= 2 {
            MemberCircleAvatar(member: members[1 % members.count], size: 34)
                .frame(width: 34, height: 34)
                .offset(x: 8, y: 8)
            MemberCircleAvatar(member: members[0], size: 34)
                .frame(width: 34, height: 34)
                .offset(x: -8, y: -8)
        } else if members.count == 1 {
            MemberCircleAvatar(member: members[0], size: 52)
        } else {
            Circle()
                .foregroundStyle(Color.accentColor.opacity(0.15))
            Image(systemName: "person.2.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - New conversation sheet

private struct NewConversationSheet: View {
    let members: [FamilyMember]
    var groupName: String?
    let onPick: (String) -> Void
    let onAddMember: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [FamilyMember] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return members }
        return members.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                List {
                    Section {
                        Button { onPick("group"); dismiss() } label: {
                            Label(groupName?.isEmpty == false ? groupName! : "Group chat",
                                  systemImage: "person.2.fill")
                        }
                        Button { onAddMember() } label: {
                            Label("New contact", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    if !filtered.isEmpty {
                        Section("Contacts") {
                            ForEach(filtered) { m in
                                Button { onPick(m.id.uuidString); dismiss() } label: {
                                    HStack(spacing: 12) {
                                        MemberCircleAvatar(member: m, size: 38)
                                            .frame(width: 38, height: 38)
                                        Text(m.name).foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $search, prompt: "Caută un nume sau un număr")
            }
            .navigationTitle("Conversație nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

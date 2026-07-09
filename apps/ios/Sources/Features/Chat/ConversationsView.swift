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
    @Environment(PresenceService.self) private var presenceService
    @Environment(AppSettings.self) private var appSettings
    @Environment(TabBarVisibility.self) private var tabBarVis
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reachability only — drives the "waiting for network" banner. The chat
    /// surfaces own the actual send/retry queues; this instance is observed
    /// solely for `isOnline` (its own filename keeps it from loading either
    /// send queue).
    @State private var outbox = OfflineOutbox(filename: "chat_reachability.json")

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
    // Conversation ids whose FULL history (server-side) matches the query —
    // the in-memory scan below only sees the loaded page.
    @State private var serverHits: Set<String> = []
    @State private var serverSearchTask: Task<Void, Never>?

    private var hasLockedChats: Bool { nonArchived.contains { ChatLockStore.isLocked($0.id) } }

    enum ConvFilter: CaseIterable {
        case all, unread, favorites, groups, family
        var label: LocalizedStringKey {
            switch self {
            case .all: return "convo_filter_all"
            case .unread: return "convo_filter_unread"
            case .favorites: return "convo_filter_favorites"
            case .groups: return "convo_filter_groups"
            case .family: return "convo_filter_family"
            }
        }
    }

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    /// The assistant bar's luminous edge: neutral white light by default,
    /// the user's accent colour once they've turned one on — the bar wears
    /// the identity they chose for the app.
    private var ariaEdgeTint: Color {
        appSettings.accentEnabled ? avatarRingColor(for: appSettings.accentColor) : .white
    }

    /// The bloom behind the bar follows the same rule (reference indigo by
    /// default) so the edge and its glow never clash.
    private var ariaBloomTint: Color {
        appSettings.accentEnabled ? avatarRingColor(for: appSettings.accentColor) : .brandIndigo
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
        // Match the conversation name, its last-message preview, the loaded
        // messages, or — via `serverHits` — the full server-side history.
        return nonArchived.filter { entry in
            // Don't surface secured chats in search until unlocked.
            if ChatLockStore.isLocked(entry.id) && !lockedRevealed { return false }
            if serverHits.contains(entry.id) { return true }
            if entry.name.localizedCaseInsensitiveContains(q) { return true }
            if entry.preview.localizedCaseInsensitiveContains(q) { return true }
            if entry.isGroup {
                return messageService.messages.contains {
                    ($0.body ?? "").localizedCaseInsensitiveContains(q)
                }
            } else if let member = entry.member {
                return directMessageService.messages(with: member, myName: myName)
                    .contains { $0.body.localizedCaseInsensitiveContains(q) }
            }
            return false
        }
    }

    /// Debounced server search: after a pause in typing, asks Postgres which
    /// conversations match anywhere in their history and folds the ids into
    /// the visible results.
    private func scheduleServerSearch(_ raw: String) {
        serverSearchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let pid = propertyService.primary?.id else {
            serverHits = []
            return
        }
        serverSearchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            async let groupHit = messageService.groupHasMatch(propertyId: pid, query: q)
            async let partners = directMessageService.partnersMatching(
                propertyId: pid, myName: myName, query: q)
            var hits = Set<String>()
            if await groupHit { hits.insert("group") }
            let names = await partners
            for member in familyService.members where names.contains(member.name) {
                hits.insert(member.id.uuidString)
            }
            guard !Task.isCancelled else { return }
            serverHits = hits
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
            let ids = pinnedIds.union(mutedIds).union(archivedIds).union(manualUnreadIds)
            for id in ids {
                await ChatPrefsSync.upsert(convId: id,
                                           pinned: pinnedIds.contains(id),
                                           muted: mutedIds.contains(id),
                                           archived: archivedIds.contains(id),
                                           manualUnread: manualUnreadIds.contains(id),
                                           propertyId: pid)
            }
        } else {
            pinnedIds       = Set(prefs.filter { $0.pinned }.map { $0.convId })
            mutedIds        = Set(prefs.filter { $0.muted }.map { $0.convId })
            archivedIds     = Set(prefs.filter { $0.archived }.map { $0.convId })
            manualUnreadIds = Set(prefs.filter { $0.manualUnread == true }.map { $0.convId })
            UserDefaults.standard.set(Array(pinnedIds),       forKey: "chat.pinned")
            UserDefaults.standard.set(Array(mutedIds),        forKey: "chat.muted")
            UserDefaults.standard.set(Array(archivedIds),     forKey: "chat.archived")
            UserDefaults.standard.set(Array(manualUnreadIds), forKey: "chat.manualUnread")
        }
        // Bring the "clear conversation" cutoff across from other devices.
        for r in prefs { ConversationClearStore.applyRemote(r.convId, iso: r.clearedAt) }
        // Disappearing-message TTLs are conversation state, not device state.
        if let pid { await ChatDisappearStore.syncFromServer(propertyId: pid, myName: myName) }

        // Reflect server-side blocks locally — by member id first (survives
        // renames), by name only for legacy rows.
        let blocked = await ChatBlockSync.load()
        for m in familyService.members {
            ChatBlockStore.setBlocked(m.id.uuidString,
                                      blocked.memberIds.contains(m.id) || blocked.names.contains(m.name))
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
        // member id (dm_insert enforces via dm_blocked(); names cover legacy rows).
        let pid = propertyService.primary?.id
        Task {
            if willBlock { await ChatBlockSync.block(member: member, myName: myName, propertyId: pid) }
            else { await ChatBlockSync.unblock(member: member) }
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
    private func toggleUnread(_ id: String)   { toggle(id, in: &manualUnreadIds, key: "chat.manualUnread"); syncPrefs(id) }

    /// Pushes the current pin/mute/archive/manual-unread state of one
    /// conversation to Supabase.
    private func syncPrefs(_ id: String) {
        let pid = propertyService.primary?.id
        let pinned = pinnedIds.contains(id), muted = mutedIds.contains(id), archived = archivedIds.contains(id)
        let unread = manualUnreadIds.contains(id)
        Task { await ChatPrefsSync.upsert(convId: id, pinned: pinned, muted: muted, archived: archived, manualUnread: unread, propertyId: pid) }
    }

    private func markAllRead() {
        let wasUnread = manualUnreadIds
        manualUnreadIds.removeAll()
        UserDefaults.standard.set([String](), forKey: "chat.manualUnread")
        for id in wasUnread { syncPrefs(id) }
        messageService.resetUnread()
        for m in familyService.members { directMessageService.markRead(member: m) }
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
                if !outbox.isOnline {
                    offlineBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if sortedConversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: outbox.isOnline)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await MemberDirectory.shared.loadIfNeeded() }
        .task {
            guard let pid = propertyService.primary?.id else { return }
            directMessageService.myName = myName
            await directMessageService.load(propertyId: pid, myName: myName)
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
            await syncRemotePrefs()
            // Fresh presence for the online dots (MainTabView keeps it live;
            // this just avoids showing stale state for the first ~45s).
            await presenceService.load(propertyId: pid)
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
        .onChange(of: searchText) { _, text in scheduleServerSearch(text) }
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
        .sheet(isPresented: $showCommunities, onDismiss: { router.drainPending() }) {
            CommunitiesView(propertyId: propertyService.primary?.id,
                            members: familyService.members,
                            myName: myName)
        }
        // Deep link prvio://communities[/<groupId>] — the router lands on the
        // chat tab and bumps this counter; the sheet opens here and
        // CommunitiesView auto-opens the requested group.
        .onChange(of: router.communitiesRequest) { _, _ in
            showCommunities = true
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

    // MARK: - Custom header (identity block + round actions + search)
    //
    // The reference layout: my avatar + inbox title on the left, two round
    // actions on the right. Everything the old ellipsis menu offered lives
    // in the avatar's menu, so no feature was lost to the redesign.

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Menu {
                    Button { router.navigate(to: .profile) } label: { Label("Profile", systemImage: "person.crop.circle") }
                    // Stories/status are a family surface — RLS returns nothing
                    // for outsiders, so the entry points disappear with the data.
                    if propertyService.isFamilyMember {
                        Button { showStatus = true } label: { Label("Status", systemImage: "circle.dashed") }
                        Button { statusComposer = .camera } label: { Label("Share a moment", systemImage: "camera") }
                    }
                    Button { showCommunities = true } label: { Label("Communities", systemImage: "person.3") }
                    Button { showContactsPicker = true } label: { Label("Add contact", systemImage: "person.crop.circle.badge.plus") }
                    Button { markAllRead() } label: { Label("Mark all as read", systemImage: "checkmark.message") }
                    if !archivedList.isEmpty {
                        Button { withAnimation { showArchived = true } } label: { Label("Archived", systemImage: "archivebox") }
                    }
                } label: {
                    myAvatar
                }
                .accessibilityLabel("Profile and options")

                VStack(alignment: .leading, spacing: 2) {
                    Text("convo_inbox_title")
                        .font(AppFont.scaled(24, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(myName)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button { showNewConversation = true } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New conversation")

                Button { router.navigate(to: .notificationsChat) } label: {
                    Image(systemName: "bell")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            }

            searchField
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.xs)
    }

    /// My avatar: the profile photo when one is set, initials otherwise.
    private var myAvatar: some View {
        ZStack {
            if let url = profileService.profile?.avatarUrl.flatMap(URL.init) {
                StorageImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    default:
                        myInitialsAvatar
                    }
                }
            } else {
                myInitialsAvatar
            }
        }
        .frame(width: 48, height: 48)
        // Reference: my own avatar wears the online dot — honest, this device
        // is by definition online while the list is on screen.
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.brandSuccess)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
        }
    }

    private var myInitialsAvatar: some View {
        ZStack {
            Circle().fill(Color.brandIndigo.opacity(0.18))
            Text(String(myName.prefix(1)).uppercased())
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(Color.brandIndigo)
        }
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
                            .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
                            // Reference (IMG_8066): the assistant bar carries a
                            // luminous top edge — a hairline that is bright at
                            // the top and dissolves down the sides — plus a
                            // soft bloom radiating from behind it. Both inherit
                            // the user's accent colour when one is active;
                            // otherwise the edge stays neutral white light over
                            // the reference's indigo bloom.
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(stops: [
                                            .init(color: ariaEdgeTint.opacity(0.65), location: 0),
                                            .init(color: ariaEdgeTint.opacity(0.12), location: 0.4),
                                            .init(color: .clear, location: 1),
                                        ], startPoint: .top, endPoint: .bottom),
                                        lineWidth: 1
                                    )
                                    .allowsHitTesting(false)
                            )
                            .background(
                                // The bloom: a blurred slab tucked behind the
                                // bar's top edge, so the glow reads as light
                                // spilling out from above it.
                                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                                    .fill(ariaBloomTint.opacity(0.45))
                                    .blur(radius: 18)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .offset(y: -6)
                            )
                            .padding(.bottom, AppSpacing.xs)
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
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                    .frame(width: 40)
                                Text(lockedRevealed ? "Locked chats (visible)" : "Locked chats")
                                    .font(AppFont.scaled(16, weight: .medium))
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

                    if !showArchived && !searchText.isEmpty && entries.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
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
                                    forceUnread: manualUnreadIds.contains(entry.id),
                                    online: entry.member.map { presenceService.status(for: $0.name) == .online } ?? false
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
        let wasManual = manualUnreadIds.remove(entry.id) != nil
        UserDefaults.standard.set(Array(manualUnreadIds), forKey: "chat.manualUnread")
        if wasManual { syncPrefs(entry.id) }
        if entry.isGroup {
            messageService.resetUnread()
            if let pid = propertyService.primary?.id {
                Task { await messageService.markRead(propertyId: pid, readerName: myName) }
            }
        } else if let m = entry.member {
            directMessageService.markRead(member: m)
        }
    }

    private func markConversationUnread(_ entry: ConversationEntry) {
        manualUnreadIds.insert(entry.id)
        UserDefaults.standard.set(Array(manualUnreadIds), forKey: "chat.manualUnread")
        syncPrefs(entry.id)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.scaled(16))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField(String(localized: "convo_search_ph"), text: $searchText)
                .font(AppFont.scaled(16))
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 14)
        .background(Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        // Hairline rim — the reference field reads recessed, not painted on.
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.7)
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Selected chip stays a solid pill (the reference's white
                // "All" — maximum contrast); the resting chips are Liquid
                // Glass like every other floating control on this screen.
                ForEach(ConvFilter.allCases, id: \.self) { f in
                    if filter == f {
                        Button {
                            HapticFeedback.selection()
                            withAnimation(.snappy(duration: 0.25)) { filter = f }
                        } label: {
                            Text(f.label)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 9)
                                .background(Color.primary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            HapticFeedback.selection()
                            withAnimation(.snappy(duration: 0.25)) { filter = f }
                        } label: {
                            Text(f.label)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(Color.primary.opacity(0.65))
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .glassCapsule()
                    }
                }
                // Action chip, not a filter: jumps straight to ARIA — glass
                // with an indigo wash so it reads as the AI entry point.
                Button {
                    HapticFeedback.impact(.light)
                    router.navigate(to: .aria)
                } label: {
                    Text(verbatim: "AI")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.brandIndigo)
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 9)
                        .background(Color.brandIndigo.opacity(AppOpacity.tintedFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .glassCapsule()
                .accessibilityLabel("AI Assistant")
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
                .font(AppFont.scaled(17, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private var archivedRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08))
                Image(systemName: "archivebox.fill")
                    .font(AppFont.scaled(18))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            .frame(width: 52, height: 52)
            Text("Conversații arhivate")
                .font(AppFont.headline)
            Spacer()
            Text("\(archivedList.count)")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(0.4))
            Image(systemName: "chevron.right")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // The assistant card under the chips (reference layout): gradient wand
    // tile + an honest promise — ARIA answers questions about your home.
    private var ariaRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Color.brandIndigo, Color.brandPurple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    // The wand tile glows in the reference — a tight purple
                    // halo, not a drop shadow.
                    .shadow(color: Color.brandPurple.opacity(0.55), radius: 8)
                Image(systemName: "wand.and.stars")
                    .font(AppFont.scaled(19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: String(localized: "convo_aria_title"),
                            UserDefaults.standard.string(forKey: "prvio.aria.customName") ?? "ARIA"))
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Text("convo_aria_subtitle")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    // Injects all environment objects ChatView needs (already in env chain, but explicit for clarity)
    @ViewBuilder
    private var groupChatDestination: some View {
        ChatView()
    }

    // MARK: - Offline banner
    //
    // Unobtrusive, glassy, and honest: it reflects the OS reachability state
    // (OfflineOutbox.isOnline) and simply informs — the send/retry queues on the
    // chat surfaces do the actual recovery. Reduce Motion removes its animation.
    private var offlineBanner: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(AppFont.caption)
            Text("chat_offline_waiting")
                .font(AppFont.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
        .padding(.horizontal, AppSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("chat_offline_waiting"))
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
            guard let m = lastGroupMsg else { return String(localized: "convo_prev_none") }
            let isOwn = m.senderId == supabase.auth.currentSession?.user.id
            let prefix = isOwn ? String(localized: "convo_prev_you") : (m.senderName.components(separatedBy: " ").first.map { "\($0): " } ?? "")
            if m.deletedForAll == true { return prefix + String(localized: "convo_prev_deleted") }
            if m.isContactShare { return prefix + String(localized: "convo_prev_contact") }
            if let body = m.body, !body.isEmpty { return prefix + body }
            switch m.attachmentType {
            case "image":    return prefix + String(localized: "convo_prev_image")
            case "video":    return prefix + String(localized: "convo_prev_video")
            case "audio":    return prefix + String(localized: "convo_prev_audio")
            case "location": return prefix + String(localized: "convo_prev_location")
            case "file":     return prefix + String(localized: "convo_prev_file")
            case "sticker":  return prefix + String(localized: "convo_prev_sticker")
            case "poll":     return prefix + String(localized: "convo_prev_poll")
            case "event":    return prefix + String(localized: "convo_prev_event")
            default:         return prefix + String(localized: "convo_prev_message")
            }
        }()

        // The main family chat (group_id null) is family-only under RLS —
        // outsiders never see the row, instead of seeing it permanently empty.
        if propertyService.isFamilyMember {
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
        }

        // DM entries — WhatsApp-style: a person appears in the list only once
        // the conversation has at least one message (either direction). Newly
        // added members stay reachable via the "+" new-conversation flow.
        // One pass over the DM store builds every thread's preview state —
        // the per-member lastMessage/unreadCount scans were O(members × dms)
        // and ran several times per render.
        let summaries = directMessageService.conversationSummaries(myName: myName,
                                                                   members: familyService.members)
        for member in familyService.members {
            guard let last = summaries[member.id]?.last else {
                continue
            }
            let preview: String = {
                if last.deletedForAll == true { return String(localized: "convo_prev_deleted") }
                let prefix = last.isMine(myUserId: directMessageService.myUserId, myName: myName) ? String(localized: "convo_prev_you") : ""
                if let rich = DMRich.snippet(for: last.body) { return prefix + rich }
                if last.isContactShare { return prefix + String(localized: "convo_prev_contact") }
                switch ChatMedia.dmBodyKind(last.body) {
                case .audio: return prefix + String(localized: "convo_prev_audio")
                case .image: return prefix + String(localized: "convo_prev_image")
                case .video: return prefix + String(localized: "convo_prev_video")
                case .text:  return prefix + last.body
                }
            }()
            items.append(ConversationEntry(
                id: member.id.uuidString,
                name: member.name,
                preview: preview,
                date: parseISODate(last.createdAt),
                unread: summaries[member.id]?.unread ?? 0,
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

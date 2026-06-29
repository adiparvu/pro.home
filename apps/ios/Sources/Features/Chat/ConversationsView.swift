import SwiftUI
import Supabase

// MARK: - Conversations list (WhatsApp-style main chat screen)

struct ConversationsView: View {
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var directMessageService: DirectMessageService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var stickerService: StickerService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @EnvironmentObject private var router: AppRouter

    @State private var showAddMember = false
    @State private var showNewConversation = false
    @State private var showAddContact = false
    @State private var showStatus = false
    @State private var showCommunities = false
    @State private var showStoryCamera = false
    @State private var filter: ConvFilter = .all
    @State private var archivedIds: Set<String> = []
    @State private var favoriteIds: Set<String> = []
    @State private var pinnedIds: Set<String> = []
    @State private var mutedIds: Set<String> = []
    @State private var manualUnreadIds: Set<String> = []
    @State private var lockedIds: Set<String> = []
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
    private func toggleLocked(_ id: String) {
        let newVal = !lockedIds.contains(id)
        ChatLockStore.setLocked(id, newVal)
        if newVal { lockedIds.insert(id) } else { lockedIds.remove(id) }
        HapticFeedback.selection()
    }
    private func toggleBlock(_ member: FamilyMember) {
        let id = member.id.uuidString
        ChatBlockStore.setBlocked(id, !ChatBlockStore.isBlocked(id))
        HapticFeedback.warning()
    }
    private func toggle(_ id: String, in set: inout Set<String>, key: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        UserDefaults.standard.set(Array(set), forKey: key)
    }
    private func toggleArchived(_ id: String) { toggle(id, in: &archivedIds, key: "chat.archived") }
    private func toggleFavorite(_ id: String) { toggle(id, in: &favoriteIds, key: "chat.favorites") }
    private func togglePinned(_ id: String)   { toggle(id, in: &pinnedIds, key: "chat.pinned") }
    private func toggleMuted(_ id: String)    { toggle(id, in: &mutedIds, key: "chat.muted") }
    private func toggleUnread(_ id: String)   { toggle(id, in: &manualUnreadIds, key: "chat.manualUnread") }

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
        guard let pid = propertyService.primary?.id,
              let data = image.jpegData(compressionQuality: 0.85) else { return }
        let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/\(UUID().uuidString).jpg"
        try? await supabase.storage.from("documents")
            .upload(filePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        let url = try? supabase.storage.from("documents").getPublicURL(path: filePath)
        try? await messageService.send(
            propertyId: pid, senderName: myName, body: nil,
            attachmentUrl: url?.absoluteString, attachmentType: "image"
        )
        HapticFeedback.success()
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
        .task {
            guard let pid = propertyService.primary?.id else { return }
            directMessageService.myName = myName
            await directMessageService.load(propertyId: pid, myName: myName)
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
        }
        .onAppear { loadFlags() }
        .navigationDestination(item: $navTarget) { id in
            if id == "group" {
                groupChatDestination
            } else if let member = familyService.members.first(where: { $0.id.uuidString == id }) {
                DirectMessageView(member: member)
            }
        }
        .onDisappear {
            Task { await directMessageService.unsubscribe() }
        }
        .sheet(isPresented: $showAddMember) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id,
                                 propertyName: propertyService.primary?.name)
                .environmentObject(familyService)
        }
        .sheet(isPresented: $showAddContact) {
            AddContactView()
                .environmentObject(familyService)
                .environmentObject(propertyService)
        }
        .sheet(isPresented: $showStatus) {
            StatusView(members: familyService.members,
                       myInitial: String(myName.prefix(1)).uppercased(),
                       onAddStatus: { showStatus = false; showStoryCamera = true })
        }
        .sheet(isPresented: $showCommunities) {
            CommunitiesView()
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationSheet(members: familyService.members,
                                 groupName: propertyService.primary?.name) { id in
                showNewConversation = false
                navTarget = id
            } onAddMember: {
                showNewConversation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showAddContact = true }
            }
        }
        .fullScreenCover(isPresented: $showStoryCamera) {
            CameraPickerView { img in Task { await sendStory(img) } }
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
        }
    }

    // MARK: - Custom header (independent round buttons + title + search)

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Menu {
                    Button { showStatus = true } label: { Label("Status", systemImage: "circle.dashed") }
                    Button { showCommunities = true } label: { Label("Communities", systemImage: "person.3") }
                    Button { showAddContact = true } label: { Label("Add contact", systemImage: "person.crop.circle.badge.plus") }
                    Button { markAllRead() } label: { Label("Mark all as read", systemImage: "checkmark.message") }
                    if !archivedList.isEmpty {
                        Button { withAnimation { showArchived = true } } label: { Label("Archived", systemImage: "archivebox") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .glassCircle()
                }
                .accessibilityLabel("More options")
                Spacer()
                Button { showStoryCamera = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
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
        .padding(.horizontal, 16)
        .padding(.top, 6)
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
                        Button { HapticFeedback.impact(.light); router.showARIA = true } label: { ariaRow }
                            .buttonStyle(.plain)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.25))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(cornerRadius: 16)
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
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
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
        if !entry.isGroup, let m = entry.member {
            Divider()
            let blocked = ChatBlockStore.isBlocked(m.id.uuidString)
            Button(role: .destructive) { toggleBlock(m) } label: {
                Label(blocked ? "Deblochează pe \(m.name)" : "Blochează pe \(m.name)",
                      systemImage: blocked ? "hand.raised.slash" : "hand.raised")
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
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConvFilter.allCases, id: \.self) { f in
                    Button { filter = f } label: {
                        Text(f.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(filter == f ? Color.accentColor : Color.primary.opacity(0.6))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(filter == f ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var archivedTopBar: some View {
        HStack(spacing: 10) {
            Button { withAnimation { showArchived = false } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text("Conversații arhivate")
                .font(.system(size: 17, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var archivedRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08))
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
            .frame(width: 52, height: 52)
            Text("Conversații arhivate")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Text("\(archivedList.count)")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var ariaRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [Color(red: 0.6, green: 0.35, blue: 0.95), Color(red: 0.29, green: 0.56, blue: 0.89)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("ARIA").font(.system(size: 16, weight: .semibold))
                Text("Asistent AI").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // Injects all environment objects ChatView needs (already in env chain, but explicit for clarity)
    @ViewBuilder
    private var groupChatDestination: some View {
        ChatView()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }
            Text("Nicio conversație")
                .font(.system(size: 18, weight: .semibold))
            Text("Adaugă membri familiei pentru a începe.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
            name: (propertyService.primary?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Chat Grup",
            preview: groupPreview,
            date: lastGroupMsg.flatMap { parseISODate($0.createdAt) },
            unread: messageService.unreadCount,
            isGroup: true,
            member: nil
        ))

        // DM entries
        for member in familyService.members {
            let last = directMessageService.lastMessage(with: member.name, myName: myName)
            let preview: String = {
                guard let last else { return "Niciun mesaj" }
                if last.deletedForAll == true { return "🚫 Mesaj șters" }
                let prefix = last.senderName == myName ? "Tu: " : ""
                return prefix + last.body
            }()
            items.append(ConversationEntry(
                id: member.id.uuidString,
                name: member.name,
                preview: preview,
                date: last.flatMap { parseISODate($0.createdAt) },
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

    private func parseISODate(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: s) ?? f2.date(from: s)
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
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                    Spacer()
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                    Text(entry.formattedTime)
                        .font(.system(size: 12))
                        .foregroundStyle(isUnread ? Color.accentColor : Color.primary.opacity(0.35))
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
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(muted ? Color.primary.opacity(0.35) : Color.accentColor, in: Capsule())
                            .fixedSize()
                    } else if forceUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
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
                AsyncImage(url: url) { phase in
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

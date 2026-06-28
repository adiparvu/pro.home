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
    @State private var filter: ConvFilter = .all
    @State private var archivedIds: Set<String> = []
    @State private var favoriteIds: Set<String> = []
    @State private var showArchived = false

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

    private var visibleConversations: [ConversationEntry] {
        nonArchived.filter { e in
            switch filter {
            case .all:       return true
            case .unread:    return e.unread > 0
            case .favorites: return favoriteIds.contains(e.id)
            case .groups:    return e.isGroup
            case .family:    return !e.isGroup
            }
        }
    }

    private func loadFlags() {
        archivedIds = Set(UserDefaults.standard.stringArray(forKey: "chat.archived") ?? [])
        favoriteIds = Set(UserDefaults.standard.stringArray(forKey: "chat.favorites") ?? [])
    }
    private func toggleArchived(_ id: String) {
        if archivedIds.contains(id) { archivedIds.remove(id) } else { archivedIds.insert(id) }
        UserDefaults.standard.set(Array(archivedIds), forKey: "chat.archived")
    }
    private func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) { favoriteIds.remove(id) } else { favoriteIds.insert(id) }
        UserDefaults.standard.set(Array(favoriteIds), forKey: "chat.favorites")
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if sortedConversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddMember = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            guard let pid = propertyService.primary?.id else { return }
            directMessageService.myName = myName
            await directMessageService.load(propertyId: pid, myName: myName)
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
        }
        .onAppear { loadFlags() }
        .onDisappear {
            Task { await directMessageService.unsubscribe() }
        }
        .sheet(isPresented: $showAddMember) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id,
                                 propertyName: propertyService.primary?.name)
                .environmentObject(familyService)
        }
    }

    // MARK: - Conversation list

    private var conversationList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if showArchived { archivedTopBar } else { filterChips }

                let entries = showArchived ? archivedList : visibleConversations
                LazyVStack(spacing: 0) {
                    if !showArchived {
                        if filter == .all {
                            Button { HapticFeedback.impact(.light); router.showARIA = true } label: { ariaRow }
                                .buttonStyle(.plain)
                            Divider().padding(.leading, 78).opacity(0.4)
                        }
                        if !archivedList.isEmpty {
                            Button { withAnimation { showArchived = true } } label: { archivedRow }
                                .buttonStyle(.plain)
                            Divider().padding(.leading, 78).opacity(0.4)
                        }
                    }

                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        NavigationLink {
                            if entry.isGroup {
                                groupChatDestination
                            } else if let member = entry.member {
                                DirectMessageView(member: member)
                            }
                        } label: {
                            ConversationRowView(
                                entry: entry,
                                myName: myName,
                                members: familyService.members,
                                propertyPhotoUrl: propertyService.primary?.photoUrl
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { toggleFavorite(entry.id) } label: {
                                Label(favoriteIds.contains(entry.id) ? "Unfavorite" : "Favorite",
                                      systemImage: favoriteIds.contains(entry.id) ? "star.slash" : "star")
                            }
                            Button { toggleArchived(entry.id) } label: {
                                Label(archivedIds.contains(entry.id) ? "Unarchive" : "Archive",
                                      systemImage: "archivebox")
                            }
                        }

                        if idx < entries.count - 1 {
                            Divider().padding(.leading, 78).opacity(0.4)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConvFilter.allCases, id: \.self) { f in
                    Button { withAnimation { filter = f } } label: {
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
            case (.none, .none): return a.isGroup
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

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.name)
                        .font(.system(size: 16, weight: entry.unread > 0 ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.formattedTime)
                        .font(.system(size: 12))
                        .foregroundStyle(entry.unread > 0
                            ? Color.accentColor
                            : Color.primary.opacity(0.35))
                }
                HStack {
                    Text(entry.preview)
                        .font(.system(size: 14))
                        .foregroundStyle(entry.unread > 0
                            ? Color.primary.opacity(0.65)
                            : Color.primary.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if entry.unread > 0 {
                        Text("\(entry.unread)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .fixedSize()
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

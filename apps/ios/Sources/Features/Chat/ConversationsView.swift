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

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
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
            await directMessageService.load(propertyId: pid, myName: myName)
            await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
        }
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
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedConversations.enumerated()), id: \.element.id) { idx, entry in
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

                    if idx < sortedConversations.count - 1 {
                        Divider()
                            .padding(.leading, 78)
                            .opacity(0.4)
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
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
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
            if let body = m.body, !body.isEmpty { return prefix + body }
            switch m.attachmentType {
            case "image":    return prefix + "📷 Imagine"
            case "audio":    return prefix + "🎤 Mesaj vocal"
            case "location": return prefix + "📍 Locație"
            case "file":     return prefix + "📎 Fișier"
            case "sticker":  return prefix + "😀 Sticker"
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

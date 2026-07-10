import SwiftUI

// MARK: - Conversations list building blocks
//
// The row, avatars, destructive-action dialogs and the new-conversation
// sheet extracted from ConversationsView (chat split 4) - same types,
// internal instead of private so the list file can keep composing them.

// MARK: - Destructive conversation dialogs (kept off the main body chain)

struct ConversationDestructiveDialogs: ViewModifier {
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
    /// The peer's durable identity + display data. Set for every DM row whose
    /// counterpart holds an account — including peers with NO roster row
    /// (the property owner on a non-owner device).
    var peer: ChatPeer? = nil

    /// The addressable 1:1 thread behind a DM row; nil for the group entry.
    var dmThread: DMThread? {
        if let member { return DMThread(member: member) }
        if let peer { return DMThread(peer: peer) }
        return nil
    }

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

    /// "now / 3 hr. ago / yesterday / last week" — the row's relative
    /// timestamp. Falls back to the short date past a month, where relative
    /// phrasing stops being helpful.
    var relativeTime: String {
        guard let date else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "convo_time_now") }
        if interval > 30 * 24 * 3600 {
            let f = DateFormatter(); f.dateFormat = "dd.MM.yy"
            return f.string(from: date)
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Conversation Row

struct ConversationRowView: View {
    let entry: ConversationEntry
    let myName: String
    let members: [FamilyMember]
    var propertyPhotoUrl: String? = nil
    var muted: Bool = false
    var pinned: Bool = false
    var forceUnread: Bool = false
    /// Live presence from PresenceService — only ever true for DM rows.
    var online: Bool = false

    private var isUnread: Bool { entry.unread > 0 || forceUnread }

    // Reference layout: name + preview on the left; a right-aligned column
    // with the relative time on top and the indigo unread dot underneath.
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar
                .frame(width: 54, height: 54)
                .overlay(alignment: .bottomTrailing) {
                    if online {
                        Circle()
                            .fill(Color.brandSuccess)
                            .frame(width: 13, height: 13)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                            .accessibilityLabel(Text("convo_online"))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if muted {
                        Image(systemName: "bell.slash.fill")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                }
                Text(entry.preview)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(isUnread ? Color.primary.opacity(0.65) : Color.primary.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: 8) {
                // iMessage-style trailing stamp: the TIME the last message was
                // written today ("12:24"), "Ieri", the weekday inside a week,
                // then the short date — not a drifting "acum X min".
                Text(entry.formattedTime)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
                if isUnread {
                    Circle()
                        .fill(muted ? Color.primary.opacity(AppOpacity.disabled) : Color.brandIndigo)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(entry.unread > 0
                                            ? Text("convo_unread_count \(entry.unread)")
                                            : Text("convo_unread"))
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, AppSpacing.xxs)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if entry.isGroup {
            GroupChatAvatar(members: members, photoUrl: propertyPhotoUrl)
        } else {
            // Identity first: the ChatPeer carries the live profile photo
            // (this is what used to leave DM rows on initials — the roster
            // snapshot rarely holds the account's real avatar).
            PeerCircleAvatar(
                name: entry.peer?.displayName ?? entry.member?.name ?? entry.name,
                color: entry.member?.swiftColor ?? entry.peer?.swiftColor ?? .blue,
                avatarUrl: entry.peer?.avatarUrl ?? entry.member?.avatarUrl,
                size: 54)
        }
    }
}

// MARK: - Peer circle avatar (identity-based rows)

/// Renders any DM counterpart from plain display data (name/colour/URL) — no
/// FamilyMember required, so a peer missing from the roster (the property
/// owner!) gets a real avatar too. The photo wins; coloured initials are the
/// fallback. `MemberCircleAvatar` below stays as the roster-typed convenience.
struct PeerCircleAvatar: View {
    let name: String
    let color: Color
    var avatarUrl: String? = nil
    let size: CGFloat

    private var initialsString: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(color.opacity(0.18))
            if let urlStr = avatarUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        initials
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
    }

    private var initials: some View {
        Text(initialsString)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(color)
    }
}

// MARK: - Member circle avatar

struct MemberCircleAvatar: View {
    let member: FamilyMember
    let size: CGFloat

    var body: some View {
        // Account holders resolve their LIVE profile photo through the
        // directory; contacts fall back to whatever snapshot the row carries.
        PeerCircleAvatar(
            name: member.name,
            color: member.swiftColor,
            avatarUrl: MemberDirectory.shared.avatarString(userId: member.userId,
                                                           fallback: member.avatarUrl),
            size: size)
    }
}

// MARK: - Group Chat Avatar (stacked initials)

struct GroupChatAvatar: View {
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
                .font(AppFont.scaled(22))
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - New conversation sheet

struct NewConversationSheet: View {
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
                    if !search.isEmpty && filtered.isEmpty {
                        Section {
                            EmptyStateView(icon: "magnifyingglass", title: "No results")
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if !filtered.isEmpty {
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

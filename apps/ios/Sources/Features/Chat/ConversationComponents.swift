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

struct ConversationRowView: View {
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
                        .font(AppFont.scaled(16, weight: isUnread ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if muted {
                        Image(systemName: "bell.slash.fill")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    Spacer()
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    Text(entry.formattedTime)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(isUnread ? Color.accentColor : Color.primary.opacity(AppOpacity.disabled))
                }
                HStack {
                    Text(entry.preview)
                        .font(AppFont.scaled(14))
                        .foregroundStyle(isUnread ? Color.primary.opacity(0.65) : Color.primary.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if entry.unread > 0 {
                        Text("\(entry.unread)")
                            .font(AppFont.scaled(12, weight: .bold))
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

struct MemberCircleAvatar: View {
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

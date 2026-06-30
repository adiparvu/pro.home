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

    @ObservedObject private var status = StatusService.shared
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
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            ForEach(others) { g in
                                Button { viewing = g } label: { groupRow(g) }
                                    .buttonStyle(.plain)
                                if g.id != others.last?.id { Divider().padding(.leading, 82) }
                            }
                        }
                        .liquidGlass(cornerRadius: 16)
                        .padding(.horizontal, 16)
                    } else {
                        Text("No recent updates")
                            .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
                            .padding(.horizontal, 20).padding(.top, 4)
                    }

                    Text("Status updates disappear after 24 hours.")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                        .padding(.horizontal, 20)

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
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
                    Text("My status").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    Text(myGroup == nil
                         ? "Tap to add status update"
                         : (myGroup!.items.count == 1 ? "1 update" : "\(myGroup!.items.count) updates"))
                        .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                }
                Spacer()
                if myGroup != nil {
                    Button { onAddStatus() } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor).frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 16)
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
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(member?.swiftColor ?? .gray))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.authorName).font(.system(size: 16)).foregroundStyle(.primary)
                Text(g.items.count == 1 ? "1 update" : "\(g.items.count) updates")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Full-screen story viewer

struct StoryViewer: View {
    let group: StatusGroup
    let myName: String
    var propertyId: UUID?

    @ObservedObject private var status = StatusService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var viewers: [String] = []
    @State private var showViewers = false

    private var item: StatusUpdate? { group.items.indices.contains(index) ? group.items[index] : nil }
    private var isMine: Bool { supabase.auth.currentSession?.user.id == group.authorId }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item, let urlStr = item.mediaUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Tap zones (below the controls so the X / Seen-by buttons stay tappable):
            // left = previous, right = next.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { prev() }
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
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
                .padding(.horizontal, 10).padding(.top, 8)

                HStack(spacing: 10) {
                    Text(group.authorName).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)

                Spacer()

                if let cap = item?.caption, !cap.isEmpty {
                    Text(cap).font(.system(size: 16)).foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                }

                if isMine {
                    Button { Task { viewers = await status.viewers(of: item?.id ?? group.id); showViewers = true } } label: {
                        Label("Seen by", systemImage: "eye.fill")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            .padding(.vertical, 10)
                    }
                }
                Spacer().frame(height: 24)
            }
        }
        .task(id: index) {
            if let item, propertyId != nil { await status.markViewed(item, viewerName: myName) }
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
    @StateObject private var service = ChatGroupService()

    var propertyId: UUID? = nil
    var members: [FamilyMember] = []
    var myName: String = "Me"

    @State private var showCreate = false
    @State private var detailGroup: ChatGroup?

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
                                Button { detailGroup = group } label: {
                                    CommunityRow(group: group, memberCount: service.members(for: group).count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
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
            .sheet(item: $detailGroup) { group in
                GroupMembersSheet(group: group, members: service.members(for: group))
            }
            .task { if let pid = propertyId { await service.load(propertyId: pid) } }
        }
    }

    private var newGroupButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
                Text("Grup nou").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 44)).foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Organizează grupuri")
                .font(.system(size: 17, weight: .semibold))
            Text("Creează grupuri separate pentru muncitori, familie sau orice altă echipă.")
                .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
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
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                Text("\(group.kindLabel) · \(memberCount) membri")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 16)
    }
}

private struct GroupMembersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: ChatGroup
    let members: [ChatGroupMember]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(members) { m in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                                Text(String(m.memberName.prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.accentColor)
                            }
                            Text(m.memberName).font(.system(size: 15, weight: .medium))
                            Spacer()
                            if m.role == "admin" {
                                Text("Admin").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 14)
                    }
                }
                .padding(16)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(group.name.isEmpty ? group.kindLabel : group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .liquidGlass(cornerRadius: 14)

                    HStack(spacing: 10) {
                        ForEach(kinds, id: \.0) { k in
                            Button { kind = k.0 } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.2).font(.system(size: 20))
                                    Text(k.1).font(.system(size: 13, weight: .medium))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(kind == k.0 ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(kind == k.0 ? Color.accentColor : Color.primary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Membri").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                    VStack(spacing: 8) {
                        ForEach(members) { m in
                            Button {
                                if selectedIds.contains(m.id) { selectedIds.remove(m.id) }
                                else { selectedIds.insert(m.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(m.name).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedIds.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIds.contains(m.id) ? Color.accentColor : Color.primary.opacity(0.25))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .liquidGlass(cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
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

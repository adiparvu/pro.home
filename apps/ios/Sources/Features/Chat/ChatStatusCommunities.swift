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
// Visual shell only. A real Communities feature needs a backend: a
// `communities` table, community↔group membership, an announcement group,
// and admin roles.

struct CommunitiesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Button {} label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15)).frame(width: 56, height: 56)
                                Image(systemName: "person.3.fill").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                            }
                            Text("New community").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.25))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 16)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 12) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 44)).foregroundStyle(Color.accentColor.opacity(0.6))
                        Text("Organize related groups")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Communities bring members together in topic groups, with one place for announcements.")
                            .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 30)

                    Text("Creating and joining communities is coming soon.")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                        .padding(.top, 8)

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

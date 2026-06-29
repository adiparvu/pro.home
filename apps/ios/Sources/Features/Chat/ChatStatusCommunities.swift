import SwiftUI

// MARK: - Status / Stories (UI shell)
//
// Visual shell only. A real Status feature needs a backend: a `status_updates`
// table (media URL, caption, created_at), 24h expiry, per-viewer seen tracking,
// and media upload — none of which exist yet.

struct StatusView: View {
    let members: [FamilyMember]
    let myInitial: String
    var onAddStatus: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // My status
                    Button(action: onAddStatus) {
                        HStack(spacing: 14) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle().fill(Color.accentColor.opacity(0.2))
                                    .overlay(Text(myInitial).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.accentColor))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18)).foregroundStyle(Color.accentColor, .white)
                                    .offset(x: 3, y: 3)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My status").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                                Text("Tap to add status update").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 16)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    Text("Recent updates")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                        .padding(.horizontal, 20)

                    VStack(spacing: 0) {
                        ForEach(members) { m in
                            HStack(spacing: 14) {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 2)
                                    .background(Circle().fill(m.swiftColor.opacity(0.15)))
                                    .overlay(Text(m.initials).font(.system(size: 16, weight: .semibold)).foregroundStyle(m.swiftColor))
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.system(size: 16)).foregroundStyle(.primary)
                                    Text("No updates").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            if m.id != members.last?.id { Divider().padding(.leading, 82) }
                        }
                    }
                    .liquidGlass(cornerRadius: 16)
                    .padding(.horizontal, 16)

                    Text("Status updates disappear after 24 hours. Posting and viewing media is coming soon.")
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
        }
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

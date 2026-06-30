import SwiftUI
import UIKit
import PhotosUI
import LocalAuthentication
import CoreImage.CIFilterBuiltins
import AudioToolbox

// MARK: - Group description + member labels (local cache + Supabase sync)

enum GroupDescriptionStore {
    static func text() -> String { UserDefaults.standard.string(forKey: "group.description") ?? "" }
    static func set(_ t: String, propertyId: UUID? = nil) {
        UserDefaults.standard.set(t, forKey: "group.description")
        guard let pid = propertyId else { return }
        Task {
            struct P: Encodable { let property_id: String; let description: String }
            _ = try? await supabase.from("chat_group_settings")
                .upsert(P(property_id: pid.uuidString, description: t), onConflict: "property_id")
                .execute()
        }
    }
    /// Pull the shared description into the local cache.
    static func loadRemote(_ propertyId: UUID) async {
        struct Row: Decodable { let description: String? }
        guard let rows: [Row] = try? await supabase.from("chat_group_settings")
            .select("description").eq("property_id", value: propertyId.uuidString)
            .execute().value else { return }
        if let desc = rows.first?.description {
            UserDefaults.standard.set(desc, forKey: "group.description")
        }
    }
}

enum MemberLabelStore {
    static func label(_ memberId: String) -> String { UserDefaults.standard.string(forKey: "member.label.\(memberId)") ?? "" }
    static func set(_ memberId: String, _ t: String, propertyId: UUID? = nil) {
        UserDefaults.standard.set(t, forKey: "member.label.\(memberId)")
        guard let pid = propertyId else { return }
        Task {
            struct R: Encodable { let property_id: String; let member_id: String; let label: String }
            _ = try? await supabase.from("chat_member_labels")
                .upsert(R(property_id: pid.uuidString, member_id: memberId, label: t),
                        onConflict: "property_id,member_id")
                .execute()
        }
    }
    /// Pull all shared member labels for the property into the local cache.
    static func loadRemote(_ propertyId: UUID) async {
        struct Row: Decodable { let member_id: String; let label: String? }
        guard let rows: [Row] = try? await supabase.from("chat_member_labels")
            .select("member_id,label").eq("property_id", value: propertyId.uuidString)
            .execute().value else { return }
        for r in rows {
            UserDefaults.standard.set(r.label ?? "", forKey: "member.label.\(r.member_id)")
        }
    }
}

/// Reusable editor sheet for short text (group description, member label, …).
struct EditTextSheet: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                appBackground.ignoresSafeArea()
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(16)
            }
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Group permissions

enum GroupPermissionStore {
    // Each key stores the toggle value: true = members allowed, false = only admins.
    // Defaults: members can send (true); edit info / add members are admins-only
    // (false); approve new members on (true).
    static func value(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: "group.perm.\(key)") as? Bool ?? def
    }
    static func set(_ key: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: "group.perm.\(key)") }
}

struct GroupPermissionsView: View {
    var adminNames: [String] = []

    @State private var editInfo = false
    @State private var sendMessages = true
    @State private var addMembers = false
    @State private var approveNew = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Member permissions")
                    .font(.system(size: 20, weight: .bold)).padding(.horizontal, 20).padding(.top, 6)

                VStack(spacing: 0) {
                    toggleRow("pencil", "Edit group settings",
                              "Includes the group name, icon and description, the disappearing-messages timer, and the options to pin and keep or unkeep messages.",
                              $editInfo)
                    Divider().padding(.leading, 56)
                    toggleRow("megaphone.fill", "Send messages", nil, $sendMessages)
                    Divider().padding(.leading, 56)
                    toggleRow("person.badge.plus", "Add other members", nil, $addMembers)
                }
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)

                Text("Turning these settings off means only group admins can do this.")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.horizontal, 20)

                Text("Admin permissions")
                    .font(.system(size: 20, weight: .bold)).padding(.horizontal, 20).padding(.top, 12)

                VStack(spacing: 0) {
                    toggleRow("person.badge.clock.fill", "Approve new members", nil, $approveNew)
                }
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)

                Text("When on, any request to join the group must be approved by an admin.")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.horizontal, 20)

                if !adminNames.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Group admins").font(.system(size: 16))
                                Text(adminNames.joined(separator: ", "))
                                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.45)).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.25))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .liquidGlass(cornerRadius: 16)
                    .padding(.horizontal, 16).padding(.top, 8)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Group permissions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editInfo = GroupPermissionStore.value("editInfo", default: false)
            sendMessages = GroupPermissionStore.value("sendMessages", default: true)
            addMembers = GroupPermissionStore.value("addMembers", default: false)
            approveNew = GroupPermissionStore.value("approveNew", default: true)
        }
        .onChange(of: editInfo) { _, v in GroupPermissionStore.set("editInfo", v) }
        .onChange(of: sendMessages) { _, v in GroupPermissionStore.set("sendMessages", v) }
        .onChange(of: addMembers) { _, v in GroupPermissionStore.set("addMembers", v) }
        .onChange(of: approveNew) { _, v in GroupPermissionStore.set("approveNew", v) }
    }

    private func toggleRow(_ icon: String, _ title: String, _ subtitle: String?, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 28)
                .padding(.top, subtitle == nil ? 0 : 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).font(.system(size: 16))
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                }
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Member list changes (history shell)

struct MemberChangesView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("See changes from the last 60 days, such as members who left or were removed.")
                .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.5))
                .padding(20)
            Spacer()
            Text("No changes")
                .font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Member list changes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Invite via link / QR

struct InviteLinkView: View {
    let title: String
    let link: String
    @Environment(\.dismiss) private var dismiss

    private func qrImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text("Anyone with this link or QR code can join \(title).")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.top, 8)

                if let qr = qrImage() {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .liquidGlass(cornerRadius: 20)
                }

                Text(link)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = link; HapticFeedback.success()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .liquidGlass(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: link) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Invite via link")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Media gallery (images shared in a conversation)

struct MediaGalleryView: View {
    let urls: [URL]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    @State private var viewer: ImageViewerItem?

    var body: some View {
        Group {
            if urls.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("No media yet").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(urls, id: \.self) { url in
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(Color.primary.opacity(0.06))
                                }
                            }
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .onTapGesture { viewer = ImageViewerItem(url: url) }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewer) { item in FullScreenImageViewer(url: item.url) }
    }
}

// MARK: - Shared info bits

private struct InfoActionCard: View {
    let label: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(LocalizedStringKey(label))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

/// Small pill shown on settings rows that only group admins can change.
struct AdminBadge: View {
    var body: some View {
        Text("Admin")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    var value: String? = nil
    var tint: Color = .primary
    var showChevron: Bool = true
    var adminBadge: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(tint == .primary ? Color.primary.opacity(0.7) : tint)
                    .frame(width: 26)
                Text(LocalizedStringKey(label))
                    .foregroundStyle(tint)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(Color.primary.opacity(0.4))
                }
                if adminBadge { AdminBadge() }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The visual content of an InfoRow without the Button — for use inside a NavigationLink.
struct InfoRowLabel: View {
    let icon: String
    let label: String
    var value: String? = nil
    var adminBadge: Bool = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: 26)
            Text(LocalizedStringKey(label))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value).foregroundStyle(Color.primary.opacity(0.4))
            }
            if adminBadge { AdminBadge() }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private func infoCardBackground<V: View>(_ content: V) -> some View {
    content.liquidGlass(cornerRadius: 14)
        .padding(.horizontal, 16)
}

// MARK: - Contact details (DM)

struct ContactDetailsView: View {
    let member: FamilyMember
    var onAudio: () -> Void
    var onVideo: () -> Void
    var onSearch: () -> Void
    var onStarred: () -> Void
    var onTheme: () -> Void
    var mediaURLs: [URL] = []
    var exportText: String = ""
    var propertyId: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var blocked = false
    @State private var showReport = false
    @State private var reported = false
    @State private var showEditLabel = false
    @State private var showClearConfirm = false
    @State private var memberLabel = ""

    private var convId: String { member.id.uuidString }

    var body: some View {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        MemberCircleAvatarLarge(member: member)
                            .frame(width: 110, height: 110)
                        Text(member.name)
                            .font(.system(size: 24, weight: .bold))
                        Text(member.roleLabel)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.5))
                        if let phone = member.phone, !phone.isEmpty {
                            Text(phone).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.4))
                        }
                        Button { showEditLabel = true } label: {
                            if memberLabel.isEmpty {
                                Label("Add a member label", systemImage: "tag")
                                    .font(.system(size: 14)).foregroundStyle(Color.accentColor)
                            } else {
                                Label(memberLabel, systemImage: "tag.fill")
                                    .font(.system(size: 14)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        InfoActionCard(label: "Audio", icon: "phone.fill") { dismiss(); onAudio() }
                        InfoActionCard(label: "Video", icon: "video.fill") { dismiss(); onVideo() }
                        InfoActionCard(label: "Search", icon: "magnifyingglass") { dismiss(); onSearch() }
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        NavigationLink {
                            MediaGalleryView(urls: mediaURLs)
                        } label: {
                            InfoRowLabel(icon: "photo.on.rectangle", label: "Media, links, docs",
                                         value: mediaURLs.isEmpty ? nil : "\(mediaURLs.count)")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        InfoRow(icon: "star", label: "Starred") { dismiss(); onStarred() }
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        NavigationLink {
                            ConversationNotificationsView(convId: convId, subtitle: member.name)
                        } label: {
                            InfoRowLabel(icon: muted ? "bell.slash.fill" : "bell.fill",
                                         label: "Notifications",
                                         value: muted ? "Off" : nil)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            DisappearingMessagesView(convId: convId)
                        } label: {
                            InfoRowLabel(icon: "timer", label: "Disappearing messages",
                                         value: ChatDisappearStore.label(convId))
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            AdvancedPrivacyView(convId: convId)
                        } label: {
                            InfoRowLabel(icon: "shield.lefthalf.filled", label: "Advanced privacy",
                                         value: ChatPrivacyStore.label(convId))
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        InfoRow(icon: "paintpalette", label: "Conversation theme") { dismiss(); onTheme() }
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        SecureChatToggle(convId: convId)
                        Divider().padding(.leading, 52)
                        NavigationLink { EncryptionInfoView() } label: {
                            InfoRowLabel(icon: "lock.fill", label: "Encryption",
                                         value: "Encrypted")
                        }
                        .buttonStyle(.plain)
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        Button {
                            blocked.toggle()
                            ChatBlockStore.setBlocked(convId, blocked)
                            HapticFeedback.warning()
                        } label: {
                            destructiveRow(icon: blocked ? "hand.raised.slash.fill" : "hand.raised.fill",
                                           label: blocked ? "Unblock \(member.name)" : "Block \(member.name)")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        Button { showReport = true } label: {
                            destructiveRow(icon: "exclamationmark.bubble.fill",
                                           label: reported ? "Reported" : "Report \(member.name)")
                        }
                        .buttonStyle(.plain)
                        .disabled(reported)
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 30)
                }
            }
            .background(appBackground.ignoresSafeArea())
            .confirmationDialog("Report \(member.name)?", isPresented: $showReport, titleVisibility: .visible) {
                Button("Report", role: .destructive) {
                    ChatBlockStore.report(convId); reported = true; HapticFeedback.success()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The last messages from this contact will be forwarded for review.")
            }
            .onAppear { blocked = ChatBlockStore.isBlocked(convId) }
            .navigationTitle("Contact details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { infoToolbar }
            .confirmationDialog("Golești conversația?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Golește", role: .destructive) {
                    ConversationClearStore.clear(convId); HapticFeedback.success(); dismiss()
                }
                Button("Anulează", role: .cancel) {}
            } message: {
                Text("Mesajele vor fi ascunse de pe acest dispozitiv.")
            }
            .onAppear {
                muted = ChatMuteStore.isMuted(convId)
                memberLabel = MemberLabelStore.label(convId)
                if let pid = propertyId {
                    Task { await MemberLabelStore.loadRemote(pid); memberLabel = MemberLabelStore.label(convId) }
                }
            }
            .onChange(of: muted) { _, m in ChatMuteStore.setMuted(convId, m) }
            .sheet(isPresented: $showEditLabel) {
                EditTextSheet(title: "Member label", text: memberLabel) { newText in
                    memberLabel = newText
                    MemberLabelStore.set(convId, newText, propertyId: propertyId)
                }
            }
    }

    @ToolbarContentBuilder
    private var infoToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showEditLabel = true } label: {
                    Label("Editează eticheta", systemImage: "tag")
                }
                if !exportText.isEmpty {
                    ShareLink(item: exportText) {
                        Label("Exportă conversația", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Golește conversația", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
            }
        }
    }

    private func destructiveRow(icon: String, label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.red).frame(width: 26)
            Text(label).font(.system(size: 16)).foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Group details

struct GroupDetailsView: View {
    let groupName: String
    let members: [FamilyMember]
    let photoUrl: String?
    var onAudio: () -> Void
    var onVideo: () -> Void
    var onAddMember: () -> Void
    var onSearch: () -> Void
    var onStarred: () -> Void
    var onTheme: () -> Void
    var mediaURLs: [URL] = []
    var inviteLink: String = ""
    var propertyId: UUID? = nil
    var exportText: String = ""
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var photoItem: PhotosPickerItem?
    @State private var description = ""
    @State private var showEditDescription = false
    @State private var showEditDetails = false
    @State private var editingLabelId: String?
    @State private var labelRefresh = false

    var body: some View {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                GroupChatAvatarLarge(members: members, photoUrl: photoUrl)
                                    .frame(width: 110, height: 110)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13)).foregroundStyle(.white)
                                    .padding(8).background(Circle().fill(Color.accentColor))
                            }
                        }
                        .buttonStyle(.plain)
                        Text(groupName)
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)

                        Button { showEditDescription = true } label: {
                            if description.isEmpty {
                                Label("Add group description", systemImage: "pencil")
                                    .font(.system(size: 14)).foregroundStyle(Color.accentColor)
                            } else {
                                Text(description)
                                    .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)

                        Text("Group · \(members.count + 1) members")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        InfoActionCard(label: "Audio", icon: "phone.fill") { dismiss(); onAudio() }
                        InfoActionCard(label: "Video", icon: "video.fill") { dismiss(); onVideo() }
                        InfoActionCard(label: "Add", icon: "person.badge.plus") { dismiss(); onAddMember() }
                        InfoActionCard(label: "Search", icon: "magnifyingglass") { dismiss(); onSearch() }
                    }
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(members.count + 1) members")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            memberRow(name: "You", member: nil, admin: true)
                            ForEach(members) { m in
                                Divider().padding(.leading, 64)
                                memberRow(name: m.name, member: m, admin: m.role == "owner" || m.role == "partner")
                            }
                        }
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            NavigationLink { MemberChangesView() } label: {
                                InfoRowLabel(icon: "person.2.badge.gearshape", label: "See member list changes", adminBadge: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, 16)
                    }

                    VStack(spacing: 0) {
                        NavigationLink {
                            MediaGalleryView(urls: mediaURLs)
                        } label: {
                            InfoRowLabel(icon: "photo.on.rectangle", label: "Media, links, docs",
                                         value: mediaURLs.isEmpty ? nil : "\(mediaURLs.count)")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        if !inviteLink.isEmpty {
                            NavigationLink {
                                InviteLinkView(title: groupName, link: inviteLink)
                            } label: {
                                InfoRowLabel(icon: "link", label: "Invite via link or QR")
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                        }
                        InfoRow(icon: "star", label: "Starred") { dismiss(); onStarred() }
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            GroupPermissionsView(
                                adminNames: ["You"] + members.filter { $0.role == "owner" || $0.role == "partner" }.map { $0.name }
                            )
                        } label: {
                            InfoRowLabel(icon: "person.2.badge.gearshape.fill", label: "Group permissions", adminBadge: true)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            ConversationNotificationsView(convId: "group", subtitle: groupName)
                        } label: {
                            InfoRowLabel(icon: muted ? "bell.slash.fill" : "bell.fill",
                                         label: "Notifications",
                                         value: muted ? "Off" : nil)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            DisappearingMessagesView(convId: "group")
                        } label: {
                            InfoRowLabel(icon: "timer", label: "Disappearing messages",
                                         value: ChatDisappearStore.label("group"), adminBadge: true)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            AdvancedPrivacyView(convId: "group")
                        } label: {
                            InfoRowLabel(icon: "shield.lefthalf.filled", label: "Advanced privacy",
                                         value: ChatPrivacyStore.label("group"), adminBadge: true)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        InfoRow(icon: "paintpalette", label: "Conversation theme") { dismiss(); onTheme() }
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        SecureChatToggle(convId: "group")
                        Divider().padding(.leading, 52)
                        NavigationLink { EncryptionInfoView() } label: {
                            InfoRowLabel(icon: "lock.fill", label: "Encryption",
                                         value: "Encrypted")
                        }
                        .buttonStyle(.plain)
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 30)
                }
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Group info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if !inviteLink.isEmpty {
                            NavigationLink {
                                InviteLinkView(title: groupName, link: inviteLink)
                            } label: {
                                Image(systemName: "qrcode").font(.system(size: 16, weight: .semibold))
                            }
                        }
                        Menu {
                            Button { showEditDetails = true } label: {
                                Label("Editează numele și imaginea", systemImage: "pencil")
                            }
                            Button { showEditDescription = true } label: {
                                Label("Editează descrierea", systemImage: "square.and.pencil")
                            }
                            if !exportText.isEmpty {
                                ShareLink(item: exportText) {
                                    Label("Exportă conversația", systemImage: "square.and.arrow.up")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditDetails) {
                EditGroupDetailsSheet(currentName: groupName, photoUrl: photoUrl,
                                      members: members, propertyId: propertyId)
                    .environmentObject(propertyService)
            }
            .onAppear {
                muted = ChatMuteStore.isMuted("group")
                description = GroupDescriptionStore.text()
                if let pid = propertyId {
                    Task {
                        await GroupDescriptionStore.loadRemote(pid)
                        await MemberLabelStore.loadRemote(pid)
                        description = GroupDescriptionStore.text()
                        labelRefresh.toggle()
                    }
                }
            }
            .onChange(of: muted) { _, m in ChatMuteStore.setMuted("group", m) }
            .onChange(of: photoItem) { _, item in
                guard let item, let pid = propertyId else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await propertyService.uploadPhoto(propertyId: pid, image: img)
                    }
                }
            }
            .sheet(isPresented: $showEditDescription) {
                EditTextSheet(title: "Group description", text: description) { newText in
                    description = newText
                    GroupDescriptionStore.set(newText, propertyId: propertyId)
                }
            }
    }

    @ViewBuilder
    private func memberRow(name: String, member: FamilyMember?, admin: Bool) -> some View {
        let labelId = member?.id.uuidString ?? "you"
        let label = MemberLabelStore.label(labelId)
        Button { editingLabelId = labelId } label: {
            HStack(spacing: 12) {
                if let m = member {
                    MemberCircleAvatarLarge(member: m).frame(width: 44, height: 44)
                } else {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.18))
                        Image(systemName: "person.fill").foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                    if label.isEmpty {
                        Text("Add a member label")
                            .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                    } else {
                        Text(label).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                Spacer()
                if admin {
                    Text("Admin").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(labelRefresh)
        .sheet(isPresented: Binding(get: { editingLabelId == labelId }, set: { if !$0 { editingLabelId = nil } })) {
            EditTextSheet(title: "Member label", text: label) { newText in
                MemberLabelStore.set(labelId, newText, propertyId: propertyId); labelRefresh.toggle()
            }
        }
    }
}

// MARK: - Edit group name + image (WhatsApp "Editează numele și imaginea")

struct EditGroupDetailsSheet: View {
    let currentName: String
    let photoUrl: String?
    let members: [FamilyMember]
    var propertyId: UUID?
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var saving = false
    @FocusState private var focused: Bool

    init(currentName: String, photoUrl: String?, members: [FamilyMember], propertyId: UUID?) {
        self.currentName = currentName
        self.photoUrl = photoUrl
        self.members = members
        self.propertyId = propertyId
        _name = State(initialValue: currentName)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let pickedImage {
                                    Image(uiImage: pickedImage).resizable().scaledToFill()
                                } else {
                                    GroupChatAvatarLarge(members: members, photoUrl: photoUrl)
                                }
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13)).foregroundStyle(.white)
                                .padding(8).background(Circle().fill(Color.accentColor))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("Editează").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        TextField("Numele grupului", text: $name)
                            .font(.system(size: 17))
                            .focused($focused)
                        if !name.isEmpty {
                            Button { name = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.primary.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Editează detaliile grupului")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() }
                        else { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) { pickedImage = img }
                }
            }
        }
    }

    private func save() async {
        saving = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var p = propertyService.primary, !trimmed.isEmpty, trimmed != p.name {
            p.name = trimmed
            await propertyService.update(p)
        }
        if let img = pickedImage, let pid = propertyId {
            await propertyService.uploadPhoto(propertyId: pid, image: img)
        }
        saving = false
        dismiss()
    }
}

// MARK: - Clear conversation (local "Golește conversația")
//
// Stores a per-conversation cutoff timestamp; messages at/before it are hidden
// from that device's view (WhatsApp "clear chat" semantics — local only).

enum ConversationClearStore {
    private static func key(_ id: String) -> String { "chat.clearedAt.\(id)" }
    static func clearedAt(_ id: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: key(id))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static func clear(_ id: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key(id))
    }
    static func reset(_ id: String) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }
    /// Keeps only items strictly newer than the cutoff. Items without a date
    /// (date closure returns nil) are kept.
    static func filter<T>(_ items: [T], convId: String, date: (T) -> Date?) -> [T] {
        guard let cutoff = clearedAt(convId) else { return items }
        return items.filter { item in
            guard let d = date(item) else { return true }
            return d > cutoff
        }
    }
}

// MARK: - Mute store (shared with conversation list)

enum ChatMuteStore {
    static func muted() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "chat.muted") ?? []) }
    static func isMuted(_ id: String) -> Bool { muted().contains(id) }
    static func setMuted(_ id: String, _ on: Bool) {
        var s = muted()
        if on { s.insert(id) } else { s.remove(id) }
        UserDefaults.standard.set(Array(s), forKey: "chat.muted")
    }
}

// MARK: - Per-conversation notification tones (stored preference)

enum ChatToneStore {
    static let alertTones = ["Default", "Note", "Chime", "Glass", "Bamboo", "None"]
    static let callTones  = ["Default", "Classic", "Reflection", "Radar", "None"]

    static func alertTone(_ id: String) -> String {
        UserDefaults.standard.string(forKey: "chat.alerttone.\(id)") ?? "Default"
    }
    static func setAlertTone(_ id: String, _ tone: String) {
        UserDefaults.standard.set(tone, forKey: "chat.alerttone.\(id)")
    }
    static func callTone(_ id: String) -> String {
        UserDefaults.standard.string(forKey: "chat.calltone.\(id)") ?? "Default"
    }
    static func setCallTone(_ id: String, _ tone: String) {
        UserDefaults.standard.set(tone, forKey: "chat.calltone.\(id)")
    }
}

// MARK: - Block / report

enum ChatBlockStore {
    static func blocked() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "chat.blocked") ?? []) }
    static func isBlocked(_ id: String) -> Bool { blocked().contains(id) }
    static func setBlocked(_ id: String, _ on: Bool) {
        var s = blocked()
        if on { s.insert(id) } else { s.remove(id) }
        UserDefaults.standard.set(Array(s), forKey: "chat.blocked")
    }
    static func report(_ id: String) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "chat.reported") ?? [])
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: "chat.reported")
    }
}

/// Builds a plain-text transcript of a conversation for export/share.
enum ChatExport {
    static func transcript(title: String, lines: [(sender: String, time: String, body: String)]) -> String {
        var out = "Chat export — \(title)\n\n"
        for l in lines {
            out += "[\(l.time)] \(l.sender): \(l.body)\n"
        }
        return out
    }
}

// MARK: - Secured (locked + hidden) conversations

enum ChatLockStore {
    static func locked() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "chat.locked") ?? []) }
    static func isLocked(_ id: String) -> Bool { locked().contains(id) }
    static func setLocked(_ id: String, _ on: Bool) {
        var s = locked()
        if on { s.insert(id) } else { s.remove(id) }
        UserDefaults.standard.set(Array(s), forKey: "chat.locked")
    }
}

enum BiometricAuth {
    /// Prompts Face ID / Touch ID (passcode fallback). Returns true on success.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Toggle row that locks + hides a conversation on this device (WhatsApp-style).
struct SecureChatToggle: View {
    let convId: String
    @State private var secured = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Secure conversation").font(.system(size: 16))
                Text("Lock and hide this chat on this device.")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
            }
            Spacer()
            Toggle("", isOn: $secured).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .onAppear { secured = ChatLockStore.isLocked(convId) }
        .onChange(of: secured) { _, on in ChatLockStore.setLocked(convId, on) }
    }
}

// MARK: - Add contact

struct AddContactView: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var colorHex = "#3B82F6"
    @State private var saving = false
    @State private var error: String?

    private let swatches = ["#3B82F6", "#22C55E", "#A855F7", "#EF4444",
                            "#F59E0B", "#14B8A6", "#EC4899", "#6366F1"]

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill((Color(hex: colorHex) ?? .blue).opacity(0.2))
                        Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color(hex: colorHex) ?? .blue)
                    }
                    .frame(width: 96, height: 96)
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        field("Name", text: $name, icon: "person.fill")
                        Divider().padding(.leading, 52)
                        field("Phone", text: $phone, icon: "phone.fill", keyboard: .phonePad)
                        Divider().padding(.leading, 52)
                        field("Email", text: $email, icon: "envelope.fill", keyboard: .emailAddress)
                    }
                    .liquidGlass(cornerRadius: 16)
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        ForEach(swatches, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray)
                                .frame(width: 30, height: 30)
                                .overlay { if colorHex == hex { Circle().strokeBorder(Color.primary, lineWidth: 3) } }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.horizontal, 16)

                    if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(.red)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, icon: String,
                       keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.6)).frame(width: 26)
            TextField(LocalizedStringKey(label), text: text)
                .font(.system(size: 16))
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await familyService.add(
                name: name.trimmingCharacters(in: .whitespaces),
                role: "member",
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                color: colorHex,
                propertyId: propertyService.primary?.id,
                birthday: nil,
                socialLinks: []
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Encryption info

struct EncryptionInfoView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)

                Text("Your messages are encrypted")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    encRow("network", "Encrypted in transit",
                           "Messages, calls and media travel over TLS between your device and the servers.")
                    encRow("externaldrive.fill.badge.checkmark", "Protected at rest",
                           "Stored data is encrypted on the server and protected by per-user access rules.")
                    encRow("hand.raised.fill", "Private by access control",
                           "Only the people in a conversation can read its messages.")
                }
                .padding(16)
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)

                Text("End-to-end encryption is on our roadmap. Until then, conversations are secured in transit and by strict access control.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer(minLength: 20)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Encryption")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func encRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold))
                Text(LocalizedStringKey(body)).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.55))
            }
        }
    }
}

// MARK: - Advanced chat privacy (per-conversation)

enum ChatPrivacyStore {
    static func isOn(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: "chat.advprivacy.\(id)") }
    static func setOn(_ id: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: "chat.advprivacy.\(id)") }
    static func label(_ id: String) -> String { isOn(id) ? "On" : "Off" }
}

struct AdvancedPrivacyView: View {
    let convId: String
    @State private var on = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 26)
                        Text("Advanced chat privacy").font(.system(size: 16))
                        Spacer()
                        Toggle("", isOn: $on).labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)

                Text("When on, others are blocked from exporting this chat, auto-saving its media, and using its messages for AI features. Best for sensitive conversations.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Advanced privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { on = ChatPrivacyStore.isOn(convId) }
        .onChange(of: on) { _, v in ChatPrivacyStore.setOn(convId, v) }
    }
}

// MARK: - Disappearing messages (per-conversation TTL)

enum ChatDisappearStore {
    /// Duration options in seconds (0 = Off), matching WhatsApp.
    static let options: [(label: String, seconds: TimeInterval)] = [
        ("Off", 0),
        ("24 hours", 86_400),
        ("7 days", 604_800),
        ("90 days", 7_776_000),
    ]

    static func ttl(_ id: String) -> TimeInterval {
        UserDefaults.standard.double(forKey: "chat.disappear.\(id)")
    }
    static func setTTL(_ id: String, _ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: "chat.disappear.\(id)")
    }
    static func label(_ id: String) -> String {
        let t = ttl(id)
        return options.first { $0.seconds == t }?.label ?? "Off"
    }

    /// Filters out messages older than the conversation's TTL (view-level
    /// disappearing). `date` extracts each item's timestamp.
    static func filter<T>(_ items: [T], convId: String, date: (T) -> Date?) -> [T] {
        let t = ttl(convId)
        guard t > 0 else { return items }
        let cutoff = Date().addingTimeInterval(-t)
        return items.filter { (date($0) ?? .distantFuture) >= cutoff }
    }
}

struct DisappearingMessagesView: View {
    let convId: String
    @State private var ttl: TimeInterval = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("New messages in this chat will disappear after the selected duration. This only affects messages from now on.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Array(ChatDisappearStore.options.enumerated()), id: \.offset) { idx, opt in
                        Button {
                            ttl = opt.seconds
                            ChatDisappearStore.setTTL(convId, opt.seconds)
                            HapticFeedback.impact(.light)
                        } label: {
                            HStack(spacing: 14) {
                                Text(LocalizedStringKey(opt.label))
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if ttl == opt.seconds {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < ChatDisappearStore.options.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Disappearing messages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ttl = ChatDisappearStore.ttl(convId) }
    }
}

// MARK: - Per-conversation notifications screen (WhatsApp-style)

struct ConversationNotificationsView: View {
    let convId: String
    let subtitle: String

    @State private var muted = false
    @State private var alertTone = "Default"
    @State private var callTone = "Default"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                section("Messages") {
                    HStack(spacing: 14) {
                        Image(systemName: muted ? "bell.slash.fill" : "bell.fill")
                            .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 26)
                        Toggle("Mute notifications", isOn: $muted).font(.system(size: 16))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().padding(.leading, 52)
                    tonePicker(icon: "bell.badge", label: "Alert tone",
                               options: ChatToneStore.alertTones, selection: $alertTone, isCall: false)
                }

                section("Calls") {
                    tonePicker(icon: "phone.badge.waveform", label: "Ringtone",
                               options: ChatToneStore.callTones, selection: $callTone, isCall: true)
                }
            }
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            muted = ChatMuteStore.isMuted(convId)
            alertTone = ChatToneStore.alertTone(convId)
            callTone = ChatToneStore.callTone(convId)
        }
        .onChange(of: muted)     { _, v in ChatMuteStore.setMuted(convId, v) }
        .onChange(of: alertTone) { _, v in ChatToneStore.setAlertTone(convId, v) }
        .onChange(of: callTone)  { _, v in ChatToneStore.setCallTone(convId, v) }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 20)
            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)
        }
    }

    private func tonePicker(icon: String, label: String, options: [String], selection: Binding<String>, isCall: Bool) -> some View {
        NavigationLink {
            TonePickerView(title: label, options: options, selection: selection, isCall: isCall)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 26)
                Text(LocalizedStringKey(label)).font(.system(size: 16)).foregroundStyle(.primary)
                Spacer()
                Text(selection.wrappedValue).foregroundStyle(Color.primary.opacity(0.45)).font(.system(size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tone preview + picker

enum ChatTonePreview {
    // Short iOS system sounds used as previews. Each id is a distinct built-in
    // alert so the user can tell the options apart before saving.
    private static let alertIDs: [String: SystemSoundID] = [
        "Default": 1007, "Note": 1005, "Chime": 1008, "Glass": 1009, "Bamboo": 1013
    ]
    private static let callIDs: [String: SystemSoundID] = [
        "Default": 1151, "Classic": 1152, "Reflection": 1153, "Radar": 1154
    ]
    static func play(_ name: String, isCall: Bool) {
        guard name != "None" else { return }
        let id = (isCall ? callIDs[name] : alertIDs[name]) ?? 1007
        AudioServicesPlaySystemSound(id)
    }
}

/// Tone list where tapping a row plays a preview and selects it. The selection
/// binding is persisted by the parent's onChange, so there is no separate save.
struct TonePickerView: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    var isCall: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(options, id: \.self) { opt in
                    Button {
                        selection = opt
                        ChatTonePreview.play(opt, isCall: isCall)
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: opt == "None" ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(opt == "None" ? Color.primary.opacity(0.4) : Color.accentColor)
                                .frame(width: 24)
                            Text(LocalizedStringKey(opt)).font(.system(size: 16)).foregroundStyle(.primary)
                            Spacer()
                            if selection == opt {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if opt != options.last { Divider().padding(.leading, 52) }
                }
            }
            .liquidGlass(cornerRadius: 16)
            .padding(16)

            Text("Atinge un ton ca să-l asculți. Selecția se salvează automat.")
                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Large avatars

struct MemberCircleAvatarLarge: View {
    let member: FamilyMember
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(member.swiftColor.opacity(0.18))
                Text(member.initials)
                    .font(.system(size: geo.size.width * 0.38, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
        }
    }
}

struct GroupChatAvatarLarge: View {
    let members: [FamilyMember]
    var photoUrl: String?
    var body: some View {
        ZStack {
            if let urlStr = photoUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill().clipShape(Circle())
                    } else { placeholder }
                }
            } else { placeholder }
        }
        .clipShape(Circle())
    }
    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
        }
    }
}

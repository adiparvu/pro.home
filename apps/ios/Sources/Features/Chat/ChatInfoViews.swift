import SwiftUI
import UIKit
import LocalAuthentication
import CoreImage.CIFilterBuiltins

// MARK: - Group permissions

enum GroupPermissionStore {
    // Each key stores true = "Only admins", false = "All members".
    static func onlyAdmins(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: "group.perm.\(key)") }
    static func set(_ key: String, _ onlyAdmins: Bool) { UserDefaults.standard.set(onlyAdmins, forKey: "group.perm.\(key)") }
}

struct GroupPermissionsView: View {
    @State private var editInfo = false
    @State private var sendMessages = false
    @State private var addMembers = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose who can manage and participate in this group.")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.horizontal, 20).padding(.top, 8)

                VStack(spacing: 0) {
                    permRow("Edit group info", "Name, icon and description", $editInfo)
                    Divider().padding(.leading, 16)
                    permRow("Send messages", "Who can post in this group", $sendMessages)
                    Divider().padding(.leading, 16)
                    permRow("Add other members", nil, $addMembers)
                }
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Group permissions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editInfo = GroupPermissionStore.onlyAdmins("editInfo")
            sendMessages = GroupPermissionStore.onlyAdmins("sendMessages")
            addMembers = GroupPermissionStore.onlyAdmins("addMembers")
        }
        .onChange(of: editInfo) { _, v in GroupPermissionStore.set("editInfo", v) }
        .onChange(of: sendMessages) { _, v in GroupPermissionStore.set("sendMessages", v) }
        .onChange(of: addMembers) { _, v in GroupPermissionStore.set("addMembers", v) }
    }

    private func permRow(_ title: String, _ subtitle: String?, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.system(size: 16))
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                }
            }
            Spacer()
            Menu {
                Button("All members") { binding.wrappedValue = false }
                Button("Only admins") { binding.wrappedValue = true }
            } label: {
                HStack(spacing: 4) {
                    Text(binding.wrappedValue ? "Only admins" : "All members")
                        .foregroundStyle(Color.primary.opacity(0.45))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.3))
                }
                .font(.system(size: 14))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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

private struct InfoRow: View {
    let icon: String
    let label: String
    var value: String? = nil
    var tint: Color = .primary
    var showChevron: Bool = true
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
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var blocked = false
    @State private var showReport = false
    @State private var reported = false

    private var convId: String { member.id.uuidString }

    var body: some View {
        NavigationStack {
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { muted = ChatMuteStore.isMuted(convId) }
            .onChange(of: muted) { _, m in ChatMuteStore.setMuted(convId, m) }
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
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        GroupChatAvatarLarge(members: members, photoUrl: photoUrl)
                            .frame(width: 110, height: 110)
                        Text(groupName)
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)
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
                                memberRow(name: m.name, member: m, admin: false)
                            }
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
                            GroupPermissionsView()
                        } label: {
                            InfoRowLabel(icon: "person.2.badge.gearshape.fill", label: "Group permissions")
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
                                         value: ChatDisappearStore.label("group"))
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            AdvancedPrivacyView(convId: "group")
                        } label: {
                            InfoRowLabel(icon: "shield.lefthalf.filled", label: "Advanced privacy",
                                         value: ChatPrivacyStore.label("group"))
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { muted = ChatMuteStore.isMuted("group") }
            .onChange(of: muted) { _, m in ChatMuteStore.setMuted("group", m) }
        }
    }

    @ViewBuilder
    private func memberRow(name: String, member: FamilyMember?, admin: Bool) -> some View {
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
            Text(name).font(.system(size: 16, weight: .medium))
            Spacer()
            if admin {
                Text("Admin").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
                               options: ChatToneStore.alertTones, selection: $alertTone)
                }

                section("Calls") {
                    tonePicker(icon: "phone.badge.waveform", label: "Ringtone",
                               options: ChatToneStore.callTones, selection: $callTone)
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

    private func tonePicker(icon: String, label: String, options: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 26)
            Text(LocalizedStringKey(label)).font(.system(size: 16))
            Spacer()
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selection.wrappedValue = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue).foregroundStyle(Color.primary.opacity(0.45))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .font(.system(size: 15))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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

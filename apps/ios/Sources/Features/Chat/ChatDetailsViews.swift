// Contact / group details screens (split from ChatInfoViews).
import SwiftUI
import UIKit
import PhotosUI
import LocalAuthentication
import AudioToolbox
import AVFoundation

/// The best available photo URL for a family contact: the member directory
/// (real account profiles) first, the contact's own avatar URL second —
/// the same resolution order the chat thread uses for sender avatars.
@MainActor
private func memberAvatarURL(_ member: FamilyMember) -> URL? {
    MemberDirectory.shared.avatarURL(for: member.id)
        ?? member.avatarUrl.flatMap { URL(string: $0) }
}

/// Current disappearing-messages duration for a conversation key, formatted
/// the iOS-Settings way ("24 hr", "7 days") — "Off" when the timer is 0.
private func disappearingDurationLabel(_ convKey: String) -> String {
    let ttl = ChatDisappearStore.ttl(convKey)
    guard ttl > 0 else { return String(localized: "Off") }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = ttl >= 86_400 ? [.day] : (ttl >= 3_600 ? [.hour] : [.minute])
    formatter.unitsStyle = .short
    return formatter.string(from: ttl) ?? String(localized: "Off")
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
    @Environment(FamilyService.self) private var familyService
    @Environment(ProfileService.self) private var profileService
    @Environment(PresenceService.self) private var presenceService
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var blocked = false
    @State private var showReport = false
    @State private var reported = false
    @State private var showEditLabel = false
    @State private var showEditContact = false
    @State private var showClearConfirm = false
    @State private var memberLabel = ""

    private var convId: String { member.id.uuidString }
    private var myDisplayName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    var body: some View {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    hero

                    HStack(spacing: 12) {
                        InfoActionCard(label: "Audio", icon: "phone.fill") { dismiss(); onAudio() }
                        InfoActionCard(label: "Video", icon: "video.fill") { dismiss(); onVideo() }
                        InfoActionCard(label: "Search", icon: "magnifyingglass") { dismiss(); onSearch() }
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    InfoSection(title: "General") {
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

                    InfoSection(title: "Settings") {
                        NavigationLink {
                            ConversationNotificationsView(convId: convId, subtitle: member.name)
                        } label: {
                            InfoRowLabel(icon: muted ? "bell.slash.fill" : "bell.fill",
                                         label: "Notifications",
                                         value: muted ? String(localized: "Off") : nil)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            // Keyed by peer NAME (matching the send-path stamp),
                            // and synced so the peer's client applies it too.
                            DisappearingMessagesView(
                                convId: member.name,
                                serverKey: ChatDisappearStore.dmServerKey(myDisplayName, member.name))
                        } label: {
                            InfoRowLabel(icon: "timer", label: "Disappearing messages",
                                         value: disappearingDurationLabel(member.name))
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
                        // Theme scope matches DirectMessageView.themeScope (member id).
                        ThemeInfoRow(scope: member.id.uuidString) { dismiss(); onTheme() }
                    }

                    InfoSection(title: "Securitate") {
                        SecureChatToggle(convId: convId)
                        Divider().padding(.leading, 52)
                        NavigationLink { EncryptionInfoView() } label: {
                            InfoRowLabel(icon: "lock.fill", label: "Encryption",
                                         value: String(localized: "Encrypted"))
                        }
                        .buttonStyle(.plain)
                    }

                    InfoSection {
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

                    Spacer(minLength: 30)
                }
                // Enough headroom that the hero avatar clears the floating
                // header controls and never sits under the top progressive blur.
                .padding(.top, AppSpacing.xxl + AppSpacing.md)
            }
            .task { await MemberDirectory.shared.loadIfNeeded() }
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
            .sheet(isPresented: $showEditContact) {
                EditFamilyMemberSheet(member: member)
                    .environment(familyService)
            }
            .sheet(isPresented: $showEditLabel) {
                EditTextSheet(title: "Member label", text: memberLabel) { newText in
                    memberLabel = newText
                    MemberLabelStore.set(convId, newText, propertyId: propertyId)
                }
            }
    }

    // MARK: - Hero (photo, name, role + presence, label affordance)

    private var hero: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                MemberPhotoAvatar(color: member.swiftColor,
                                  initials: member.initials,
                                  avatarURL: memberAvatarURL(member),
                                  size: 96)
                Text(member.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                heroSubtitle
                if let phone = member.phone, !phone.isEmpty {
                    Text(phone)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.38))
                }
            }
            .accessibilityElement(children: .combine)

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
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// Role label, joined with live presence (online / last seen) when the
    /// partner shares it — the same source the thread header uses.
    private var heroSubtitle: some View {
        HStack(spacing: 6) {
            Text(member.roleLabel)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            switch presenceService.status(for: member.name) {
            case .online:
                Text("·").foregroundStyle(Color.primary.opacity(0.25))
                Text("online").foregroundStyle(Color.brandSuccess)
            case .lastSeen(let date):
                Text("·").foregroundStyle(Color.primary.opacity(0.25))
                Text("last seen \(date, format: .relative(presentation: .named))")
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            case .hidden:
                EmptyView()
            }
        }
        .font(.system(size: 15))
    }

    @ToolbarContentBuilder
    private var infoToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showEditContact = true } label: {
                    Label("Editează contactul", systemImage: "person.crop.circle")
                }
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
                Image(systemName: "ellipsis").font(AppFont.headline)
            }
        }
    }

    private func destructiveRow(icon: String, label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.red).frame(width: 26)
            Text(label).font(.system(size: 16)).foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
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
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var photoItem: PhotosPickerItem?
    @State private var description = ""
    @State private var showEditDescription = false
    @State private var showDescriptionView = false
    @State private var showEditDetails = false
    @State private var editingLabelId: String?
    @State private var labelRefresh = false

    var body: some View {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    hero

                    HStack(spacing: 12) {
                        InfoActionCard(label: "Audio", icon: "phone.fill") { dismiss(); onAudio() }
                        InfoActionCard(label: "Video", icon: "video.fill") { dismiss(); onVideo() }
                        InfoActionCard(label: "Add", icon: "person.badge.plus") { dismiss(); onAddMember() }
                        InfoActionCard(label: "Search", icon: "magnifyingglass") { dismiss(); onSearch() }
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    InfoSection(title: "\(members.count + 1) members") {
                        memberRow(name: String(localized: "You"), member: nil, admin: true)
                        ForEach(members) { m in
                            Divider().padding(.leading, 64)
                            memberRow(name: m.name, member: m, admin: m.role == "owner" || m.role == "partner")
                        }
                        Divider().padding(.leading, 52)
                        NavigationLink { MemberChangesView() } label: {
                            InfoRowLabel(icon: "person.2.badge.gearshape", label: "See member list changes", adminBadge: true)
                        }
                        .buttonStyle(.plain)
                    }

                    InfoSection(title: "General") {
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
                    }

                    InfoSection(title: "Settings") {
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
                                         value: muted ? String(localized: "Off") : nil)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 52)
                        NavigationLink {
                            DisappearingMessagesView(convId: "group", serverKey: "group")
                        } label: {
                            InfoRowLabel(icon: "timer", label: "Disappearing messages",
                                         value: disappearingDurationLabel("group"), adminBadge: true)
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
                        // Theme scope matches ChatView.themeScope ("group").
                        ThemeInfoRow(scope: "group") { dismiss(); onTheme() }
                    }

                    InfoSection(title: "Securitate") {
                        SecureChatToggle(convId: "group")
                        Divider().padding(.leading, 52)
                        NavigationLink { EncryptionInfoView() } label: {
                            InfoRowLabel(icon: "lock.fill", label: "Encryption",
                                         value: String(localized: "Encrypted"))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 30)
                }
                // Enough headroom that the hero avatar clears the floating
                // header controls and never sits under the top progressive blur.
                .padding(.top, AppSpacing.xxl + AppSpacing.md)
            }
            .task { await MemberDirectory.shared.loadIfNeeded() }
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
                                Image(systemName: "qrcode").font(AppFont.headline)
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
                            Image(systemName: "ellipsis").font(AppFont.headline)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditDetails) {
                EditGroupDetailsSheet(currentName: groupName, photoUrl: photoUrl,
                                      members: members, propertyId: propertyId)
                    .environment(propertyService)
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
                EditTextSheet(title: "Descrierea grupului", text: description,
                              note: "Descrierea grupului poate fi văzută de membrii acestuia și de persoanele invitate în grup.") { newText in
                    description = newText
                    GroupDescriptionStore.set(newText, propertyId: propertyId)
                }
            }
            .sheet(isPresented: $showDescriptionView) {
                GroupDescriptionSheet(text: description) {
                    showDescriptionView = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showEditDescription = true }
                }
            }
    }

    // MARK: - Hero (group photo, name, member count, description)

    private var hero: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                GroupChatAvatarLarge(members: members, photoUrl: photoUrl)
                    .frame(width: 96, height: 96)
                Text(groupName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Group · \(members.count + 1) members")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            .accessibilityElement(children: .combine)

            Button { if description.isEmpty { showEditDescription = true } else { showDescriptionView = true } } label: {
                if description.isEmpty {
                    Label("Add group description", systemImage: "pencil")
                        .font(.system(size: 14)).foregroundStyle(Color.accentColor)
                } else {
                    (Text(description).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                     + Text("  Afișează mai mult").foregroundStyle(Color.accentColor))
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xxl)
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func memberRow(name: String, member: FamilyMember?, admin: Bool) -> some View {
        let labelId = member?.id.uuidString ?? "you"
        let label = MemberLabelStore.label(labelId)
        Button { editingLabelId = labelId } label: {
            HStack(spacing: 12) {
                if let m = member {
                    MemberPhotoAvatar(color: m.swiftColor,
                                      initials: m.initials,
                                      avatarURL: memberAvatarURL(m),
                                      size: 44)
                } else if let myURL = MemberDirectory.shared.avatarURL(for: supabase.auth.currentSession?.user.id) {
                    MemberPhotoAvatar(color: .accentColor, initials: "", avatarURL: myURL, size: 44)
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
                        Text(label).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
                Spacer()
                if admin { AdminBadge() }
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
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
    @Environment(PropertyService.self) private var propertyService
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
                                .padding(AppSpacing.sm).background(Circle().fill(Color.accentColor))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.lg)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("Editează").font(AppFont.body).foregroundStyle(Color.accentColor)
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
                            .accessibilityLabel("Clear name")
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                    .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, AppSpacing.lg)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Editează detaliile grupului")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
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
        .presentationBackground(.thinMaterial)
    }

    private func save() async {
        saving = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Rename the group chat only — never the property. The name lives in
        // chat_group_settings via PropertyService.groupChatName.
        if !trimmed.isEmpty, trimmed != propertyService.groupChatDisplayName {
            await propertyService.updateGroupChatName(trimmed)
        }
        if let img = pickedImage, let pid = propertyId {
            await propertyService.uploadPhoto(propertyId: pid, image: img)
        }
        saving = false
        dismiss()
    }
}

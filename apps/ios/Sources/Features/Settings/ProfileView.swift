import SwiftUI
import PhotosUI
import CoreLocation

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ProfileService.self) private var profileService
    @Environment(NotificationScheduler.self) private var notificationScheduler
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(PropertyService.self) private var propertyService
    @Environment(MessageService.self) private var messageService
    @Environment(DirectMessageService.self) private var directMessageService
    @Environment(PresenceService.self) private var presenceService

    @State private var showEdit = false
    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var showDeleteConfirm = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showAvatarOptions = false
    @State private var showCamera = false
    @State private var toast: String?
    @State private var toastIsError = false
    @State private var copiedAccountId = false
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    /// Geofenced home presence (moved here from the chat hub, IMG_8591) —
    /// the toggle mirrors the service's stored opt-in; side effects (auth
    /// ladder, region arming, row erase on opt-out) run through setSharing.
    @AppStorage(HomePresenceService.shareKey) private var homePresenceShare = false
    /// Bumped on every appearance so the chat card re-reads the (non-observable,
    /// UserDefaults-backed) global chat theme after it was changed inside the hub.
    @State private var themeTick = 0

    private var ringColor: Color { avatarRingColor(for: avatarRingColorName) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                avatarSection
                infoCard
                socialCard
                chatCard
                presenceSection
                accountSection
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xl)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            EditProfileView().environment(profileService)
        }
        .sheet(isPresented: $showChangeEmail) {
            ChangeEmailSheet { newEmail in
                Task { await changeEmail(newEmail) }
            }
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet { newPassword in
                Task { await changePassword(newPassword) }
            }
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                Task { try? await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be permanently deleted. This cannot be undone.")
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhotoPick(newItem) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .sheet(isPresented: $showCamera) {
            CameraCapture { img in
                Task {
                    do {
                        try await profileService.uploadAvatar(img)
                        showToast("Avatar updated")
                    } catch {
                        showToast(error.localizedDescription, isError: true)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Change avatar", isPresented: $showAvatarOptions, titleVisibility: .visible) {
            Button("Take a photo") { showCamera = true }
            Button("Choose from Gallery") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let msg = toast {
                toastView(msg, isError: toastIsError)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 100)
            }
        }
        .task {
            if profileService.profile == nil, let uid = auth.session?.user.id {
                await profileService.load(userId: uid)
            }
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                avatarImage
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .shadow(color: ringColor.opacity(0.45), radius: 16, y: 6)
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: 2.5))

                Button { showAvatarOptions = true } label: {
                    ZStack {
                        Circle().fill(.black.opacity(0.55)).frame(width: 30, height: 30)
                        if profileService.isUploadingAvatar {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Change photo"))
                .disabled(profileService.isUploadingAvatar)
                .offset(x: 4, y: 4)
            }

            Text(preferredName)
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(.primary)
            Text(auth.session?.user.email ?? "")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))

            ringColorPicker
        }
    }

    private var ringColorPicker: some View {
        HStack(spacing: 8) {
            ForEach(["blue", "purple", "green", "orange", "pink", "gold", "red", "teal"], id: \.self) { name in
                let c = avatarRingColor(for: name)
                Button { withAnimation(.spring(response: 0.3)) { avatarRingColorName = name } } label: {
                    ZStack {
                        Circle().fill(c).frame(width: 22, height: 22)
                        if avatarRingColorName == name {
                            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 22, height: 22)
                            Circle().strokeBorder(c, lineWidth: 1).frame(width: 26, height: 26)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Custom ring color picker
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                        center: .center
                    ))
                    .frame(width: 22, height: 22)
                if avatarRingColorName.hasPrefix("#") {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 22, height: 22)
                    Circle().strokeBorder(ringColor, lineWidth: 1).frame(width: 26, height: 26)
                }
                ColorPicker("", selection: Binding(
                    get: { Color(hex: avatarRingColorName) ?? .blue },
                    set: { newColor in
                        withAnimation(.spring(response: 0.3)) {
                            avatarRingColorName = newColor.hexString()
                        }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)
                .frame(width: 44, height: 44)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlStr = profileService.profile?.avatarUrl,
           let url = URL(string: urlStr) {
            StorageImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    gradientInitial
                default:
                    gradientInitial.overlay(ProgressView().tint(.white))
                }
            }
        } else {
            gradientInitial
        }
    }

    private var gradientInitial: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(preferredInitial)
                .font(AppFont.scaled(38, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                infoRow("Email", auth.session?.user.email ?? "—")
                div
                infoRow("Display Name", profileService.profile?.preferredName ?? "—")
                div
                if let fullName = profileService.profile?.fullName, !fullName.isEmpty {
                    infoRow("Full Name", fullName)
                    div
                }
                if let phone = profileService.profile?.phone, !phone.isEmpty {
                    infoRow("Phone", phone)
                    div
                }
                accountIdRow
                div
                infoRow("Member since", memberSince)
            }
        }
    }

    /// The account ID is an identity, not decoration: PRVIO-prefixed, derived
    /// from the account UUID, and copyable with one tap so it can be pasted
    /// into search or shared for support.
    private var accountIdRow: some View {
        Button {
            guard let uid = auth.session?.user.id else { return }
            UIPasteboard.general.string = AccountID.display(for: uid)
            HapticFeedback.success()
            withAnimation(.snappy(duration: 0.2)) { copiedAccountId = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.smooth(duration: 0.25)) { copiedAccountId = false }
            }
        } label: {
            HStack {
                Text("Account ID")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Spacer()
                Text(copiedAccountId ? String(localized: "account_id_copied") : shortId)
                    .font(AppFont.footnote)
                    .foregroundStyle(copiedAccountId ? Color.brandSuccess : .primary)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                Image(systemName: copiedAccountId ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(copiedAccountId ? Color.brandSuccess : Color.primary.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Account ID"))
        .accessibilityValue(Text(shortId))
        .accessibilityHint(Text("account_id_copy_hint"))
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
            Text(value).font(AppFont.footnote).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.5).padding(.leading, AppSpacing.lg)
    }

    // MARK: - Social profiles
    //
    // The user's own saved networks, previewed exactly as contacts see them:
    // tappable platform icons. Managed from Edit profile — this card never
    // grows a second editor.

    @ViewBuilder
    private var socialCard: some View {
        let links = SocialLinksRow.displayable(profileService.profile?.socialLinks)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("soc_section_title")
                    .textCase(.uppercase)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppSpacing.sm)
                GlassCard(padding: 14) {
                    SocialLinksRow(links: links)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Live chat card
    //
    // The chat hub moved here from Settings. This is not a navigation row —
    // it's a living preview: the ACTUAL wallpaper + outgoing-bubble colour,
    // and the inbox's real numbers, updating with the same observable
    // services the chat itself renders from. Tap = open the full hub.

    private var chatCard: some View {
        let theme: ChatTheme = {
            _ = themeTick
            return .effective(scope: nil)
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Chat")
                .textCase(.uppercase)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            NavigationLink {
                ChatSettingsView()
            } label: {
                ZStack {
                    // previewBackground, NOT background: the anchored
                    // variant is screen-sized and would inflate this card
                    // past the page margins (IMG_8592).
                    theme.previewBackground
                    VStack(spacing: 8) {
                        HStack {
                            Capsule()
                                .fill(theme.isDark ? Color.white.opacity(0.92) : Color(.systemBackground).opacity(0.92))
                                .frame(width: 110, height: 26)
                            Spacer(minLength: 90)
                        }
                        HStack {
                            Spacer(minLength: 90)
                            Capsule()
                                .fill(theme.id == "appDefault" ? Color.accentColor : theme.outgoingBubble)
                                .frame(width: 84, height: 26)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, 34)
                    .padding(.top, AppSpacing.md)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                }
                .frame(height: 128)
                .overlay(alignment: .bottom) { chatCardStats }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Chat"))
        }
        .onAppear { themeTick += 1 }
        .task {
            if let pid = propertyService.primary?.id {
                await directMessageService.refreshHeads(propertyId: pid)
            }
        }
    }

    /// The inbox's numbers, told with icons so the strip needs no words.
    private var chatCardStats: some View {
        let conversations = directMessageService.conversationHeads.count + 1
        let unread = directMessageService.conversationHeads.reduce(0) { $0 + $1.unreadCount }
            + messageService.unreadCount
        var online = presenceService.onlineUserIds
        if let me = auth.session?.user.id { online.remove(me) }

        return HStack(spacing: AppSpacing.lg) {
            statChip(icon: "bubble.left.and.bubble.right.fill", color: .blue,
                     value: conversations, label: "Conversații")
            statChip(icon: "envelope.badge.fill", color: .orange,
                     value: unread, label: "Necitite")
            statChip(icon: "circle.fill", color: Color.brandSuccess,
                     value: online.count, label: "Online acum")
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppFont.caption)
                .foregroundStyle(.primary.opacity(0.5))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func statChip(icon: String, color: Color, value: Int, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppFont.scaled(11))
                .foregroundStyle(color)
            Text("\(value)")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value)"))
    }

    // MARK: - Home presence
    //
    // "Who's home" sharing is an identity-level choice, so it lives on the
    // profile page (IMG_8591), not in the chat hub. The opt-in has real side
    // effects (the Always-auth ladder, region arming, erasing the member's
    // row on opt-out) — they run through the service, not raw AppStorage.

    private var presenceSection: some View {
        SettingsGroup(title: "Confidențialitate") {
            ToggleSettingsRow(icon: "location.fill.viewfinder", color: Color.brandSkyBlue,
                              label: "homepresence_toggle", value: $homePresenceShare)
            if homePresenceShare, !HomePresenceService.shared.hasCoordinates {
                Text("homepresence_needs_coords")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.bottom, AppSpacing.xs)
            } else if homePresenceShare, HomePresenceService.shared.authorization != .authorizedAlways {
                Text("homepresence_needs_always")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.bottom, AppSpacing.xs)
            }
        }
        .onChange(of: homePresenceShare) { _, on in
            HomePresenceService.shared.setSharing(on)
        }
    }

    // MARK: - Account actions

    private var accountSection: some View {
        SettingsGroup(title: "Account") {
            // FormScaffold forms carry their own NavigationStack, so this must
            // present as a sheet — pushing it nests stacks and pops the page.
            TapSettingsRow(icon: "pencil.circle.fill", color: .blue, label: "Edit profile") {
                showEdit = true
            }
            TapSettingsRow(icon: "envelope.fill", color: .orange, label: "Change email") {
                showChangeEmail = true
            }
            TapSettingsRow(icon: "key.fill", color: Color.brandSuccess, label: "Change password") {
                showChangePassword = true
            }
            NavSettingsRow(icon: "shield.fill", color: .purple, label: "Safety and security") {
                SecurityView().environment(auth)
            }
            NavSettingsRow(icon: "person.badge.shield.checkmark.fill", color: Color.brandSkyBlue, label: "Trusted contact") {
                TrustedContactView().environment(auth)
            }
            NavSettingsRow(icon: "bell.fill", color: .red, label: "Notifications") {
                NotificationsSettingsView()
                    .environment(notificationScheduler)
                    .environment(taskService)
                    .environment(documentService)
            }
        }
    }

    // MARK: - Actions

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        do {
            try await profileService.uploadAvatar(image)
            showToast("Avatar updated")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func changeEmail(_ newEmail: String) async {
        do {
            try await profileService.updateEmail(newEmail)
            showToast("Check your inbox — a verification email was sent to \(newEmail)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func changePassword(_ newPassword: String) async {
        do {
            try await profileService.updatePassword(newPassword)
            showToast("Password updated successfully")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func showToast(_ message: String, isError: Bool = false) {
        toastIsError = isError
        withAnimation(AppMotion.state) { toast = message }
        Task { try? await Task.sleep(for: .milliseconds(3500)); withAnimation(AppMotion.state) { toast = nil } }
    }

    private func toastView(_ message: String, isError: Bool) -> some View {
        Text(LocalizedStringKey(message))
            .font(AppFont.scaled(13, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .background(isError ? .red.opacity(0.85) : Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.95),
                        in: Capsule())
            .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Helpers

    private var preferredName: String {
        profileService.profile?.preferredName ?? fallbackName
    }
    private var preferredInitial: String {
        profileService.profile?.initial ?? String(fallbackName.prefix(1)).uppercased()
    }
    private var fallbackName: String {
        auth.session?.user.email?.components(separatedBy: "@").first?.capitalized ?? "User"
    }
    private var shortId: String {
        auth.session.map { AccountID.display(for: $0.user.id) } ?? "—"
    }
    private var memberSince: String {
        guard let user = auth.session?.user else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: user.createdAt)
    }
}

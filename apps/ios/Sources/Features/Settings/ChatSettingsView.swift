import SwiftUI

// MARK: - Chat hub (Profil › Chat)
//
// Rebuilt from scratch when it moved out of Settings: this page is a live
// mirror of the household chat, not a list of doors. The hero renders the
// ACTUAL wallpaper and outgoing-bubble colour (animated presets included),
// the snapshot tiles read the same observable services the inbox reads — so
// every number here moves the moment the chat does — and every row below
// controls something real. No dead controls, no mockups.

struct ChatSettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(ProfileService.self) private var profileService
    @Environment(MessageService.self) private var messageService
    @Environment(DirectMessageService.self) private var directMessageService
    @Environment(PresenceService.self) private var presenceService
    @Environment(AppRouter.self) private var router

    @AppStorage("presence.shareStatus") private var shareStatus = true
    @State private var showTheme = false
    @State private var showStarred = false
    @State private var showCommunities = false
    @State private var themeRefresh = 0

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }
    private var marked: [Message] { messageService.messages.filter { $0.isMarked == true } }
    private var groupName: String {
        (propertyService.primary?.name).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Chat Grup")
    }

    // Live snapshot — the same sources the inbox renders from.
    private var conversationCount: Int {
        directMessageService.conversationHeads.count + 1   // DMs + the household chat
    }
    private var unreadTotal: Int {
        directMessageService.conversationHeads.reduce(0) { $0 + $1.unreadCount }
            + messageService.unreadCount
    }
    private var onlineCount: Int {
        var ids = presenceService.onlineUserIds
        if let me = auth.session?.user.id { ids.remove(me) }
        return ids.count
    }

    /// The global chat theme (per-conversation overrides don't apply here).
    private var globalTheme: ChatTheme {
        _ = themeRefresh
        return .effective(scope: nil)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {

                themeHero

                liveSnapshot

                SettingsGroup(title: "Confidențialitate") {
                    ToggleSettingsRow(icon: "eye.fill", color: .blue,
                                      label: "Arată online și văzut ultima dată", value: $shareStatus)
                    NavSettingsRow(icon: "shield.lefthalf.filled", color: .indigo, label: "Confidențialitate avansată") {
                        AdvancedPrivacyView(convId: "group")
                    }
                    NavSettingsRow(icon: "lock.fill", color: Color.brandSuccess, label: "Criptare") {
                        EncryptionInfoView()
                    }
                }

                SettingsGroup(title: "Notificări") {
                    NavSettingsRow(icon: "bell.fill", color: .red, label: "Notificări chat") {
                        ConversationNotificationsView(convId: "group", subtitle: groupName)
                    }
                    InfoSettingsRow(icon: "bubble.left.and.bubble.right.fill", color: .red,
                                    label: "Conversație", value: groupName)
                }

                SettingsGroup(title: "Funcții") {
                    TapSettingsRow(icon: "person.3.fill", color: .purple, label: "chat_groups_title") { showCommunities = true }
                    NavSettingsRow(icon: "arrow.left.arrow.right.circle.fill", color: Color.brandSuccess, label: "Cross-app messaging") {
                        InterAppChatView()
                    }
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showTheme, onDismiss: { themeRefresh += 1 }) { ChatThemePicker() }
        .sheet(isPresented: $showStarred) {
            StarredMessagesView(messages: marked, members: familyService.members) { _ in showStarred = false }
        }
        .sheet(isPresented: $showCommunities, onDismiss: { router.drainPending() }) {
            CommunitiesView(propertyId: propertyService.primary?.id,
                            members: familyService.members,
                            myName: myName)
        }
        .task {
            // The inbox keeps these fresh while it's open; refresh here too so
            // the snapshot is truthful even when the page is reached directly.
            if let pid = propertyService.primary?.id {
                await directMessageService.refreshHeads(propertyId: pid)
            }
        }
    }

    // MARK: - Live theme hero
    //
    // The actual global theme — wallpaper (animated presets render live) and
    // the real outgoing-bubble colour — with sample bubbles. Tapping opens
    // the theme picker; the card refreshes on return.

    private var themeHero: some View {
        let theme = globalTheme
        return Button {
            HapticFeedback.selection()
            showTheme = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Teme și fundal")
                    .textCase(.uppercase)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppSpacing.sm)

                ZStack {
                    theme.background
                    VStack(spacing: 8) {
                        HStack {
                            Capsule()
                                .fill(theme.isDark ? Color.white.opacity(0.92) : Color(.systemBackground).opacity(0.92))
                                .frame(width: 128, height: 30)
                            Spacer(minLength: 80)
                        }
                        HStack {
                            Spacer(minLength: 80)
                            Capsule()
                                .fill(theme.id == "appDefault" ? Color.accentColor : theme.outgoingBubble)
                                .frame(width: 96, height: 30)
                        }
                    }
                    .padding(AppSpacing.lg)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                }
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 5) {
                        Image(systemName: "paintbrush.fill")
                            .font(AppFont.label)
                        Text("Personalizează")
                            .font(AppFont.captionStrong)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 6)
                    .glassCapsule()
                    .padding(AppSpacing.sm)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Teme și fundal"))
        .accessibilityHint(Text("Personalizează"))
    }

    // MARK: - Live snapshot (the chat, in numbers, right now)

    private var liveSnapshot: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chatul tău acum")
                .textCase(.uppercase)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            GlassCard {
                HStack(spacing: 0) {
                    statTile(value: conversationCount, label: "Conversații",
                             icon: "bubble.left.and.bubble.right.fill", color: .blue)
                    tileDivider
                    statTile(value: unreadTotal, label: "Necitite",
                             icon: "envelope.badge.fill", color: .orange)
                    tileDivider
                    statTile(value: onlineCount, label: "Online acum",
                             icon: "circle.fill", color: Color.brandSuccess)
                    tileDivider
                    Button {
                        HapticFeedback.selection()
                        showStarred = true
                    } label: {
                        statTileContent(value: marked.count, label: "Mesaje marcate",
                                        icon: "star.fill", color: .yellow)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Mesaje marcate"))
                    .accessibilityValue(Text("\(marked.count)"))
                }
                .padding(.vertical, AppSpacing.md)
            }
        }
    }

    private var tileDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(width: 0.5)
            .padding(.vertical, AppSpacing.sm)
    }

    private func statTile(value: Int, label: LocalizedStringKey,
                          icon: String, color: Color) -> some View {
        statTileContent(value: value, label: label, icon: icon, color: color)
            .accessibilityElement(children: .combine)
    }

    private func statTileContent(value: Int, label: LocalizedStringKey,
                                 icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.caption)
                .foregroundStyle(color)
            Text("\(value)")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.scaled(10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

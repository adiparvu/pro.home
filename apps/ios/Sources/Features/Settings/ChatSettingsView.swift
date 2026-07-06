import SwiftUI

// MARK: - Chat settings hub (Settings › Familie & Chat › Chat)
//
// Not a list of doors — a control surface. The page opens with a LIVE
// preview of the current chat theme (the actual wallpaper and bubble
// colour, animated presets included), and every row states its current
// value the way iOS Settings does: starred count, disappearing-message
// duration, encryption state, the group the notifications apply to.

struct ChatSettingsView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(ProfileService.self) private var profileService
    @Environment(MessageService.self) private var messageService

    @AppStorage("presence.shareStatus") private var shareStatus = true
    @State private var showTheme = false
    @State private var showStarred = false
    @State private var showStatus = false
    @State private var showCommunities = false
    @State private var themeRefresh = 0

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }
    private var marked: [Message] { messageService.messages.filter { $0.isMarked == true } }
    private var groupName: String {
        (propertyService.primary?.name).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Chat Grup")
    }

    /// The global chat theme (per-conversation overrides don't apply here).
    private var globalTheme: ChatTheme {
        _ = themeRefresh
        return .effective(scope: nil)
    }

    /// Human label for the group conversation's disappearing-message timer.
    private var disappearingLabel: String {
        let ttl = ChatDisappearStore.ttl("group")
        guard ttl > 0 else { return String(localized: "Off") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = ttl >= 86_400 ? [.day] : (ttl >= 3_600 ? [.hour] : [.minute])
        formatter.unitsStyle = .short
        return formatter.string(from: ttl) ?? String(localized: "Off")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "Chat")

                themeHero

                SettingsGroup(title: "Conversații") {
                    valueTapRow(icon: "star.fill", label: "Mesaje marcate",
                                value: marked.isEmpty ? nil : "\(marked.count)") { showStarred = true }
                    NavSettingsRow(icon: "timer", color: .teal, label: "Mesaje care dispar") {
                        DisappearingMessagesView(convId: "group", serverKey: "group")
                    }
                    InfoSettingsRow(icon: "timer", color: .teal, label: "Durată curentă", value: disappearingLabel)
                }

                SettingsGroup(title: "Confidențialitate") {
                    ToggleSettingsRow(icon: "eye.fill", color: .blue,
                                      label: "Arată online și văzut ultima dată", value: $shareStatus)
                    NavSettingsRow(icon: "shield.lefthalf.filled", color: .indigo, label: "Confidențialitate avansată") {
                        AdvancedPrivacyView(convId: "group")
                    }
                    NavSettingsRow(icon: "lock.fill", color: Color(red: 0.3, green: 0.8, blue: 0.5), label: "Criptare") {
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
                    TapSettingsRow(icon: "circle.dashed", color: .blue, label: "Status") { showStatus = true }
                    TapSettingsRow(icon: "person.3.fill", color: .purple, label: "Communities") { showCommunities = true }
                    NavSettingsRow(icon: "arrow.left.arrow.right.circle.fill", color: Color(red: 0.2, green: 0.75, blue: 0.45), label: "Cross-app messaging") {
                        InterAppChatView()
                    }
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTheme, onDismiss: { themeRefresh += 1 }) { ChatThemePicker() }
        .sheet(isPresented: $showStarred) {
            StarredMessagesView(messages: marked, members: familyService.members) { _ in showStarred = false }
        }
        .sheet(isPresented: $showStatus) {
            StatusView(propertyId: propertyService.primary?.id,
                       myName: myName,
                       members: familyService.members,
                       onAddStatus: { showStatus = false })
        }
        .sheet(isPresented: $showCommunities) {
            CommunitiesView(propertyId: propertyService.primary?.id,
                            members: familyService.members,
                            myName: myName)
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
                            .font(.system(size: 11, weight: .semibold))
                        Text("Personalizează")
                            .font(.system(size: 12, weight: .semibold))
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

    // MARK: - Row with a trailing value + tap action (iOS-Settings style)

    @ViewBuilder
    private func valueTapRow(icon: String, label: LocalizedStringKey,
                             value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon, color: .yellow)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.38))
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

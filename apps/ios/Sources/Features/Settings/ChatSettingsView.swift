import SwiftUI

// MARK: - Chat settings hub (Settings › Familie & Chat › Chat)
//
// WhatsApp-style "Chats" settings: everything chat-related in one place.
// Composes the existing chat sub-screens. The actual conversation list lives
// on the Chat tab; this screen is for settings/features.

struct ChatSettingsView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(ProfileService.self) private var profileService
    @Environment(MessageService.self) private var messageService

    @State private var showTheme = false
    @State private var showStarred = false
    @State private var showStatus = false
    @State private var showCommunities = false
    @State private var showStoryCamera = false

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }
    private var marked: [Message] { messageService.messages.filter { $0.isMarked == true } }
    private var groupName: String {
        (propertyService.primary?.name).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Chat Grup")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "Chat")

                SettingsGroup(title: "Conversații") {
                    TapSettingsRow(icon: "star.fill", color: .yellow, label: "Mesaje marcate") { showStarred = true }
                    TapSettingsRow(icon: "paintpalette.fill", color: .pink, label: "Teme și fundal") { showTheme = true }
                    NavSettingsRow(icon: "timer", color: .teal, label: "Mesaje care dispar") {
                        DisappearingMessagesView(convId: "group")
                    }
                }

                SettingsGroup(title: "Confidențialitate") {
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
        .sheet(isPresented: $showTheme) { ChatThemePicker() }
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
}

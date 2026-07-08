import SwiftUI
import UIKit
import PhotosUI
import LocalAuthentication
import AudioToolbox
import AVFoundation

// MARK: - Read-only group description viewer (WhatsApp-style)

struct GroupDescriptionSheet: View {
    let text: String
    var onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.xl)
            }
            .navigationTitle("Descrierea grupului")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onEdit() } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Edit description")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }
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
                    .font(AppFont.scaled(20, weight: .bold)).padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.xs)

                VStack(spacing: 0) {
                    toggleRow("pencil", "Edit group settings",
                              "Includes the group name, icon and description, the disappearing-messages timer, and the options to pin and keep or unkeep messages.",
                              $editInfo)
                    Divider().padding(.leading, 56)
                    toggleRow("megaphone.fill", "Send messages", nil, $sendMessages)
                    Divider().padding(.leading, 56)
                    toggleRow("person.badge.plus", "Add other members", nil, $addMembers)
                }
                .liquidGlass(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.lg)

                Text("Turning these settings off means only group admins can do this.")
                    .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.horizontal, AppSpacing.xl)

                Text("Admin permissions")
                    .font(AppFont.scaled(20, weight: .bold)).padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.md)

                VStack(spacing: 0) {
                    toggleRow("person.badge.clock.fill", "Approve new members", nil, $approveNew)
                }
                .liquidGlass(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.lg)

                Text("When on, any request to join the group must be approved by an admin.")
                    .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.horizontal, AppSpacing.xl)

                if !adminNames.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Group admins").font(AppFont.scaled(16))
                                Text(adminNames.joined(separator: ", "))
                                    .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText)).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
                        }
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                    }
                    .liquidGlass(cornerRadius: AppRadius.lg)
                    .padding(.horizontal, AppSpacing.lg).padding(.top, AppSpacing.sm)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, AppSpacing.sm)
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
                .font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 28)
                .padding(.top, subtitle == nil ? 0 : 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).font(AppFont.scaled(16))
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
    }
}

// MARK: - Member list changes (history shell)

struct MemberChangesView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("See changes from the last 60 days, such as members who left or were removed.")
                .font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .padding(AppSpacing.xl)
            Spacer()
            Text("No changes")
                .font(AppFont.scaled(16)).foregroundStyle(Color.primary.opacity(0.4))
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text("Anyone with this link or QR code can join \(title).")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl).padding(.top, AppSpacing.sm)

                QRCodeImage(content: link, size: 220)
                    .padding(.top, AppSpacing.xs)

                Text(link)
                    .font(AppFont.scaled(13, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = link; HapticFeedback.success()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(AppFont.body)
                            .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                            .liquidGlass(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: link) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                            .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

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
                    Image(systemName: "photo.on.rectangle.angled").font(AppFont.scaled(34)).foregroundStyle(.secondary)
                    Text("No media yet").font(AppFont.scaled(14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(urls, id: \.self) { url in
                            StorageImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(Color.primary.opacity(AppOpacity.hairline))
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

// MARK: - Add contact

struct AddContactView: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var colorHex = "#3B82F6"
    @State private var saving = false
    @State private var error: String?
    // The contact is added before the invite is sent. If the invite fails we keep
    // the sheet open to show why — this guards against re-adding on a retry.
    @State private var contactAdded = false

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
                            .font(AppFont.scaled(34, weight: .bold))
                            .foregroundStyle(Color(hex: colorHex) ?? .blue)
                    }
                    .frame(width: 96, height: 96)
                    .padding(.top, AppSpacing.sm)

                    VStack(spacing: 0) {
                        field("Name", text: $name, icon: "person.fill")
                        Divider().padding(.leading, 52)
                        field("Phone", text: $phone, icon: "phone.fill", keyboard: .phonePad)
                        Divider().padding(.leading, 52)
                        field("Email", text: $email, icon: "envelope.fill", keyboard: .emailAddress)
                    }
                    .liquidGlass(cornerRadius: AppRadius.lg)
                    .padding(.horizontal, AppSpacing.lg)

                    HStack(spacing: 12) {
                        ForEach(swatches, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray)
                                .frame(width: 30, height: 30)
                                .overlay { if colorHex == hex { Circle().strokeBorder(Color.primary, lineWidth: 3) } }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    if let error {
                        Text(error).font(AppFont.scaled(13)).foregroundStyle(.red)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.top, AppSpacing.sm)
            }
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func field(_ label: String, text: Binding<String>, icon: String,
                       keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFont.scaled(16)).foregroundStyle(Color.primary.opacity(0.6)).frame(width: 26)
            TextField(LocalizedStringKey(label), text: text)
                .font(AppFont.scaled(16))
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        error = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        do {
            // Contacts added from chat default to chat-only (guest). Elevate to a
            // fuller role from Family settings if they should see more of the home.
            // Guard so a retry (after an invite failure) doesn't add them twice.
            if !contactAdded {
                try await familyService.add(
                    name: trimmedName,
                    role: "guest",
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                    phone: phone.isEmpty ? nil : phone,
                    color: colorHex,
                    propertyId: propertyService.primary?.id,
                    birthday: nil,
                    socialLinks: []
                )
                contactAdded = true
            }
        } catch {
            self.error = error.localizedDescription
            return
        }
        // WhatsApp-style: adding a contact with an email invites them. Surface a
        // delivery failure instead of dismissing as if it worked.
        if !trimmedEmail.isEmpty {
            if let inviteError = await familyService.sendInvite(
                to: trimmedEmail, name: trimmedName, role: "guest",
                propertyId: propertyService.primary?.id,
                propertyName: propertyService.primary?.name) {
                self.error = String(localized: "Contact added, but the invite email couldn't be sent: \(inviteError)")
                return
            }
        }
        dismiss()
    }
}

// MARK: - Encryption info

struct EncryptionInfoView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(AppFont.scaled(54))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, AppSpacing.xxl)

                Text("Your messages are encrypted")
                    .font(AppFont.scaled(20, weight: .bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    encRow("network", "Encrypted in transit",
                           "Messages, calls and media travel over TLS between your device and the servers.")
                    encRow("externaldrive.fill.badge.checkmark", "Protected at rest",
                           "Stored data is encrypted on the server and protected by per-user access rules.")
                    encRow("hand.raised.fill", "Private by access control",
                           "Only the people in a conversation can read its messages.")
                }
                .padding(AppSpacing.lg)
                .liquidGlass(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.lg)

                Text("End-to-end encryption is on our roadmap. Until then, conversations are secured in transit and by strict access control.")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
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
                .font(AppFont.scaled(18)).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(AppFont.subheadline)
                Text(LocalizedStringKey(body)).font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.55))
            }
        }
    }
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
                            .font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 26)
                        Text("Advanced chat privacy").font(AppFont.scaled(16))
                        Spacer()
                        Toggle("", isOn: $on).labelsHidden()
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                }
                .liquidGlass(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.lg)

                Text("When on, others are blocked from exporting this chat, auto-saving its media, and using its messages for AI features. Best for sensitive conversations.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.horizontal, AppSpacing.xl)
            }
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Advanced privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { on = ChatPrivacyStore.isOn(convId) }
        .onChange(of: on) { _, v in ChatPrivacyStore.setOn(convId, v) }
    }
}

struct DisappearingMessagesView: View {
    let convId: String
    /// Server-side conversation key; when set, TTL changes sync to every
    /// participant instead of staying a this-device preference.
    var serverKey: String? = nil
    @State private var ttl: TimeInterval = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("New messages in this chat will disappear for everyone after the selected duration. This only affects messages from now on.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.horizontal, AppSpacing.xl)

                VStack(spacing: 0) {
                    ForEach(Array(ChatDisappearStore.options.enumerated()), id: \.offset) { idx, opt in
                        Button {
                            ttl = opt.seconds
                            if let serverKey {
                                ChatDisappearStore.pushToServer(serverKey: serverKey, seconds: opt.seconds)
                            }
                            ChatDisappearStore.setTTL(convId, opt.seconds)
                            HapticFeedback.impact(.light)
                        } label: {
                            HStack(spacing: 14) {
                                Text(LocalizedStringKey(opt.label))
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if ttl == opt.seconds {
                                    Image(systemName: "checkmark")
                                        .font(AppFont.scaled(15, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < ChatDisappearStore.options.count - 1 {
                            Divider().padding(.leading, AppSpacing.lg)
                        }
                    }
                }
                .liquidGlass(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.top, AppSpacing.sm)
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
                            .font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 26)
                        Toggle("Mute notifications", isOn: $muted).font(AppFont.scaled(16))
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                    Divider().padding(.leading, 52)
                    tonePicker(icon: "bell.badge", label: "Alert tone",
                               options: ChatToneStore.alertTones, selection: $alertTone, isCall: false)
                }

                section("Calls") {
                    tonePicker(icon: "phone.badge.waveform", label: "Ringtone",
                               options: ChatToneStore.callTones, selection: $callTone, isCall: true)
                }
            }
            .padding(.top, AppSpacing.sm)
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
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .padding(.horizontal, AppSpacing.xl)
            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func tonePicker(icon: String, label: String, options: [String], selection: Binding<String>, isCall: Bool) -> some View {
        NavigationLink {
            TonePickerView(title: label, options: options, selection: selection, isCall: isCall)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 26)
                Text(LocalizedStringKey(label)).font(AppFont.scaled(16)).foregroundStyle(.primary)
                Spacer()
                Text(selection.wrappedValue).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText)).font(AppFont.scaled(15))
                Image(systemName: "chevron.right")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TonePickerView: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    var isCall: Bool = false

    /// Device tones not already covered by the curated list — Apple's own
    /// names are proper nouns, shown verbatim like iOS Settings does.
    private var deviceTones: [SystemToneCatalog.Tone] {
        let curated = Set(options)
        return (isCall ? SystemToneCatalog.ringtones : SystemToneCatalog.alertTones)
            .filter { !curated.contains($0.name) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { opt in
                        toneRow(title: Text(LocalizedStringKey(opt)), name: opt,
                                isNone: opt == "None", isLast: opt == options.last) {
                            ChatTonePreview.play(opt, isCall: isCall)
                        }
                    }
                }
                .liquidGlass(cornerRadius: AppRadius.lg)

                if !deviceTones.isEmpty {
                    Text("tones_apple_section")
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .padding(.leading, AppSpacing.xxs)
                    LazyVStack(spacing: 0) {
                        ForEach(deviceTones) { tone in
                            toneRow(title: Text(verbatim: tone.name), name: tone.name,
                                    isNone: false, isLast: tone == deviceTones.last) {
                                SystemToneCatalog.play(tone)
                            }
                        }
                    }
                    .liquidGlass(cornerRadius: AppRadius.lg)
                }

                Text("tones_footer_hint")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    .padding(.leading, AppSpacing.xxs)
            }
            .padding(AppSpacing.lg)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { SystemToneCatalog.stop() }
    }

    private func toneRow(title: Text, name: String, isNone: Bool, isLast: Bool,
                         play: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button {
                selection = name
                play()
                HapticFeedback.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isNone ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(isNone ? Color.primary.opacity(0.4) : Color.accentColor)
                        .frame(width: 24)
                    title.font(AppFont.scaled(16)).foregroundStyle(.primary)
                    Spacer()
                    if selection == name {
                        Image(systemName: "checkmark")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isLast { Divider().padding(.leading, 52) }
        }
    }
}

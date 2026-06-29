import SwiftUI

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
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false

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
                        InfoRow(icon: "photo.on.rectangle", label: "Media, links, docs") {}
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
                        InfoRow(icon: "paintpalette", label: "Conversation theme") { dismiss(); onTheme() }
                    }
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 30)
                }
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Contact details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { muted = ChatMuteStore.isMuted(convId) }
            .onChange(of: muted) { _, m in ChatMuteStore.setMuted(convId, m) }
        }
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
                        InfoRow(icon: "star", label: "Starred") { dismiss(); onStarred() }
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
                        InfoRow(icon: "paintpalette", label: "Conversation theme") { dismiss(); onTheme() }
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

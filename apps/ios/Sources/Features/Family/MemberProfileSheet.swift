import SwiftUI

struct MemberProfileSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember
    @State private var showEdit = false
    @State private var showDM = false
    @State private var resolvedMember: FamilyMember

    init(member: FamilyMember) {
        self.member = member
        _resolvedMember = State(initialValue: member)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        profileHeader
                        quickActions
                        if resolvedMember.email != nil || resolvedMember.phone != nil || resolvedMember.birthday != nil {
                            contactSection
                        }
                        if let links = resolvedMember.socialLinks, !links.isEmpty {
                            socialSection(links)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.md)
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") { showEdit = true }
                        .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
            .sheet(isPresented: $showEdit, onDismiss: {
                if let updated = familyService.members.first(where: { $0.id == member.id }) {
                    resolvedMember = updated
                }
            }) {
                EditFamilyMemberSheet(member: resolvedMember)
            }
            .navigationDestination(isPresented: $showDM) {
                DirectMessageView(member: resolvedMember)
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 10) {
            MemberAvatar(member: resolvedMember, size: 80)
            Text(resolvedMember.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text(LocalizedStringKey(resolvedMember.roleLabel))
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(resolvedMember.swiftColor)
                .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xxs)
                .background(resolvedMember.swiftColor.opacity(0.12), in: Capsule())
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            if let phone = resolvedMember.phone, !phone.isEmpty {
                profileActionBtn(icon: "phone.fill", label: "Call", color: Color.brandSuccess) {
                    if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                }
                profileActionBtn(icon: "facetime", label: "FaceTime", color: .blue) {
                    if let url = URL(string: "facetime://\(phone.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                }
                profileActionBtn(icon: "message.badge.filled.fill", label: "WhatsApp", color: Color(red: 0.16, green: 0.72, blue: 0.37)) {
                    let num = phone.filter { $0.isNumber }
                    if let url = URL(string: "https://wa.me/\(num)") { UIApplication.shared.open(url) }
                }
                if let tg = resolvedMember.socialLinks?.first(where: { $0.platform == "telegram" }) {
                    let handle = tg.handle.replacingOccurrences(of: "@", with: "")
                    profileActionBtn(icon: "paperplane.fill", label: "Telegram", color: Color(red: 0.13, green: 0.60, blue: 0.87)) {
                        if let url = URL(string: "tg://resolve?domain=\(handle)") ?? URL(string: "https://t.me/\(handle)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            profileActionBtn(icon: "bubble.left.fill", label: "Message", color: .purple) {
                showDM = true
            }
            if let email = resolvedMember.email, !email.isEmpty {
                profileActionBtn(icon: "envelope.fill", label: "Email", color: .orange) {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
            }
        }
    }

    private func profileActionBtn(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppFont.title3)
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5))
                Text(label)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CONTACT")
            VStack(spacing: 0) {
                if let email = resolvedMember.email, !email.isEmpty {
                    contactRow(icon: "envelope.fill", color: .orange, value: email)
                    if resolvedMember.phone != nil || resolvedMember.birthday != nil {
                        divider
                    }
                }
                if let phone = resolvedMember.phone, !phone.isEmpty {
                    contactRow(icon: "phone.fill", color: Color.brandSuccess, value: phone)
                    if resolvedMember.birthday != nil { divider }
                }
                if let bd = resolvedMember.birthdayDate {
                    contactRow(icon: "gift.fill", color: .pink, value: formatted(bd))
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private func socialSection(_ links: [SocialLink]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SOCIAL NETWORKS")
            HStack(spacing: 12) {
                ForEach(links) { link in
                    Button {
                        if let url = link.openURL { UIApplication.shared.open(url) }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(link.platformColor.opacity(0.13))
                                .frame(width: 46, height: 46)
                            Image(systemName: link.platformIcon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(link.platformColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(link.platformLabel) profile")
                }
            }
        }
    }

    private func contactRow(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 36)
            Text(value).font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding(.leading, AppSpacing.xxs)
    }

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMMM"
        fmt.locale = .current
        return fmt.string(from: date)
    }
}

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
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        profileHeader
                        quickActions
                        if resolvedMember.email != nil || resolvedMember.phone != nil || resolvedMember.birthday != nil {
                            contactSection
                        }
                        if !SocialLinksRow.displayable(resolvedMember.socialLinks).isEmpty {
                            socialSection
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
        .presentationBackground(.thinMaterial)
    }

    private var profileHeader: some View {
        VStack(spacing: 10) {
            headerAvatar
            Text(resolvedMember.name)
                .font(AppFont.scaled(22, weight: .bold))
                .foregroundStyle(.primary)
            Text(LocalizedStringKey(resolvedMember.roleLabel))
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(resolvedMember.swiftColor)
                .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xxs)
                .background(resolvedMember.swiftColor.opacity(0.12), in: Capsule())
        }
    }

    // Header avatar: the member's photo when one exists, otherwise their
    // initials in `.primary` on a clear Liquid Glass disc — never a tinted
    // colour fill.
    @ViewBuilder
    private var headerAvatar: some View {
        if let urlStr = resolvedMember.avatarUrl, !urlStr.isEmpty, URL(string: urlStr) != nil {
            MemberAvatar(member: resolvedMember, size: 80)
        } else {
            Text(resolvedMember.initials)
                .font(AppFont.scaled(26, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 80, height: 80)
                .glassCircle()
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            // Call is always offered: over the phone line when we have a
            // number, over FaceTime Audio via e-mail otherwise.
            if let phone = resolvedMember.phone, !phone.isEmpty {
                profileActionBtn(icon: "phone.fill", label: "Call") {
                    if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                }
            } else if let email = resolvedMember.email, !email.isEmpty {
                profileActionBtn(icon: "phone.fill", label: "Call") {
                    if let url = URL(string: "facetime-audio://\(email)") { UIApplication.shared.open(url) }
                }
                profileActionBtn(icon: "video.fill", label: "FaceTime") {
                    if let url = URL(string: "facetime://\(email)") { UIApplication.shared.open(url) }
                }
            }
            if let phone = resolvedMember.phone, !phone.isEmpty {
                profileActionBtn(icon: "video.fill", label: "FaceTime") {
                    if let url = URL(string: "facetime://\(phone.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                }
                profileActionBtn(icon: "message.badge.filled.fill", label: "WhatsApp") {
                    let num = phone.filter { $0.isNumber }
                    if let url = URL(string: "https://wa.me/\(num)") { UIApplication.shared.open(url) }
                }
                if let tg = resolvedMember.socialLinks?.first(where: { $0.platform == "telegram" }) {
                    let handle = tg.handle.replacingOccurrences(of: "@", with: "")
                    profileActionBtn(icon: "paperplane.fill", label: "Telegram") {
                        if let url = URL(string: "tg://resolve?domain=\(handle)") ?? URL(string: "https://t.me/\(handle)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            profileActionBtn(icon: "bubble.left.fill", label: "Message") {
                showDM = true
            }
            if let email = resolvedMember.email, !email.isEmpty {
                profileActionBtn(icon: "envelope.fill", label: "Email") {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
            }
        }
    }

    // Round liquid-glass action discs — the profile actions read like the
    // system Contacts card, per the app's Liquid Glass language:
    // a 52pt clear glass circle, a monochrome hierarchical glyph, and an
    // 11pt secondary label. Never tinted.
    private func profileActionBtn(icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        GlassActionButton(icon: icon, label: label, action: action)
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

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "soc_section_title"))
            SocialLinksRow(links: resolvedMember.socialLinks ?? [])
        }
    }

    private func contactRow(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 36)
            Text(value).font(AppFont.scaled(14)).foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .textCase(.uppercase)
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

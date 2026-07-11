import SwiftUI

// MARK: - Unified person (account ∪ roster)

/// One human in the Family/Others lists: an active account (property_members
/// + live profile), a hand-added roster row (family_members), or both merged
/// by auth user id. Display data prefers the live profile; contact details
/// prefer the roster (that's where hand-entered phones live).
struct HubPerson: Identifiable {
    let account: AccountMember?
    let profile: AccountProfile?
    let member: FamilyMember?
    let isSelf: Bool

    var id: String {
        if let account { return account.userId.uuidString }
        return "roster-" + (member?.id.uuidString ?? "")
    }

    var userId: UUID? { account?.userId ?? member?.userId }

    var displayName: String {
        if let p = profile, !p.bestName.isEmpty { return p.bestName }
        return member?.name ?? ""
    }

    var email: String? {
        let e = member?.email ?? profile?.email
        return (e?.isEmpty == false) ? e : nil
    }

    var phone: String? {
        let p = member?.phone ?? profile?.phone
        return (p?.isEmpty == false) ? p : nil
    }

    var isOwner: Bool { account?.role == "owner" || member?.role == "owner" }

    /// When they joined: the account's joined_at, else the roster row's
    /// created_at. nil (unparseable/missing) simply hides the subtitle —
    /// only real fields are shown.
    var joinedDate: Date? {
        if let d = account?.joinedDate { return d }
        guard let created = member?.createdAt else { return nil }
        return ISODate.date(from: created)
    }

    var roleLabel: LocalizedStringKey {
        if let account { return accountRoleLabel(account.role) }
        let role = member?.role ?? ""
        return LocalizedStringKey(kRoleLabels[role] ?? role.capitalized)
    }

    var roleColor: Color { member?.swiftColor ?? Color.accentColor }

    /// Destination for "Send message": the durable auth user id when there is
    /// one (ConversationsView hydrates a ChatPeer from it), else the roster
    /// row id (its legacy member-DM path). nil for yourself — no self-DMs.
    var chatTarget: String? {
        guard !isSelf else { return nil }
        if let uid = userId { return uid.uuidString }
        return member?.id.uuidString
    }

    /// Owner first, then yourself, then other account holders, then
    /// roster-only rows — each group alphabetized by the caller.
    var sortRank: Int {
        if isOwner { return 0 }
        if isSelf { return 1 }
        if account != nil { return 2 }
        return 3
    }

    func matchesSearch(_ text: String) -> Bool {
        displayName.matchesSearch(text) || (email ?? "").matchesSearch(text)
    }
}

// MARK: - Person row

struct PersonHubRow: View {
    let person: HubPerson
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                subtitle
            }
            Spacer()
            roleBadge
            if !person.isSelf {
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        avatarImage
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(Color.brandSuccess)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                        .accessibilityLabel(Text("convo_online"))
                }
            }
    }

    private var avatarImage: some View {
        HubAvatar(member: person.member,
                  avatarUrl: person.profile?.avatarUrl,
                  name: person.displayName,
                  size: 42)
    }

    /// "member since <month year>" from real dates only; falls back to the
    /// e-mail when there's no join date to show.
    @ViewBuilder private var subtitle: some View {
        if let joined = person.joinedDate {
            Text("mem_member_since \(joined.formatted(.dateTime.month(.wide).year()))")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .lineLimit(1)
        } else if let email = person.email {
            Text(email)
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .lineLimit(1)
        }
    }

    private var roleBadge: some View {
        Group {
            if person.isSelf {
                Text("You") + Text(verbatim: " · ") + Text(person.roleLabel)
            } else {
                Text(person.roleLabel)
            }
        }
        .font(AppFont.label)
        .foregroundStyle(person.roleColor)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(person.roleColor.opacity(0.14), in: Capsule())
    }
}

// MARK: - Hub avatar (row + long-press preview)
//
// One avatar for everyone in the hub: roster members render through
// MemberAvatar (live profile photo for account holders), profile-only people
// through their avatar URL, and everyone else as accent initials. Shared by
// PersonHubRow and both PreviewCard mounts so the peek always matches the row.
struct HubAvatar: View {
    let member: FamilyMember?
    var avatarUrl: String? = nil
    let name: String
    var size: CGFloat = 42

    var body: some View {
        if let member {
            MemberAvatar(member: member, size: size)
        } else if let urlStr = avatarUrl, let url = URL(string: urlStr) {
            StorageImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { initialsCircle }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsCircle.frame(width: size, height: size)
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.18))
            Text(String(name.prefix(2)).uppercased())
                .font(AppFont.scaled(size * 0.33, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - Invitation row

struct InvitationRow: View {
    let invitation: MemberInvitation
    var onResend: (() -> Void)? = nil
    var onRevoke: (() -> Void)? = nil

    private var status: (text: LocalizedStringKey, color: Color) {
        if invitation.isRevoked { return ("Revoked", Color.brandDanger) }
        if invitation.accepted { return ("Accepted", Color.brandSuccess) }
        if invitation.isExpired { return ("Expired", .gray) }
        return ("Pending", Color.brandWarning)
    }

    /// Days until the link dies, painted urgent (brandWarning) at ≤ 2 days.
    @ViewBuilder private var expiryCountdown: some View {
        if !invitation.accepted && !invitation.isRevoked && !invitation.isExpired {
            let d = max(invitation.daysLeft, 0)
            Label {
                Group {
                    if d == 0 {
                        Text("mem_expires_today")
                    } else if d == 1 {
                        Text("Expires in 1 day")
                    } else {
                        Text("Expires in \(d) days")
                    }
                }
                .font(AppFont.scaled(11, weight: d <= 2 ? .semibold : .regular))
            } icon: {
                Image(systemName: "hourglass").font(AppFont.scaled(10))
            }
            .foregroundStyle(d <= 2 ? Color.brandWarning
                                    : Color.primary.opacity(AppOpacity.secondaryText))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "envelope.fill", color: status.color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.name?.isEmpty == false ? invitation.name! : invitation.email)
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Text(invitation.email)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                    if invitation.accepted && !invitation.isRevoked {
                        Text("mem_became_member")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(Color.brandSuccess)
                    }
                }
                Spacer()
                Text(status.text)
                    .font(AppFont.label)
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(status.color.opacity(0.13), in: Capsule())
            }
            HStack(spacing: 10) {
                Label {
                    Text(String(format: String(localized: "Sent %@"), invitation.sentDisplay))
                        .font(AppFont.scaled(11))
                } icon: {
                    Image(systemName: "paperplane").font(AppFont.scaled(10))
                }
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))

                Text(LocalizedStringKey(kRoleLabels[invitation.role] ?? invitation.role.capitalized))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))

                expiryCountdown

                Spacer()

                if let onResend {
                    Button { onResend() } label: {
                        Text("Resend")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                if let onRevoke {
                    Button(role: .destructive) { onRevoke() } label: {
                        Text("Revoke")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.base)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }
}

import SwiftUI

// MARK: - Members hub
//
// One home for everyone with access to the house: the family (with child
// supervision), non-family members (tenants, workers, friends) and the
// invitation audit trail (who was invited, when, and for how long the link is
// still valid). Replaces the separate "Family Members" + "Supervision" rows.
//
// The Family/Others lists merge TWO real sources by auth user id:
//  - property_members + profiles (AccountMemberService): everyone with an
//    ACTIVE account — including the owner, who never gets a family_members
//    row of their own (creating the property grants membership directly).
//    This is why a partner's device used to show no owner here at all.
//  - family_members (FamilyService): the hand-added roster, with or without
//    a linked account.
// An account linked to a roster row renders ONCE (live profile name, roster
// contact details). The owner sorts first; your own row wears a "You · role"
// badge; a green dot marks members online right now (PresenceService).

struct MembersHubView: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(PresenceService.self) private var presenceService

    @State private var invitationService = InvitationService()
    @State private var accountService = AccountMemberService()
    @State private var segment: Segment = .family
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?
    @State private var reviewingAccount: AccountMember?
    @State private var showRevokedHistory = false

    enum Segment: String, CaseIterable, Identifiable {
        case family, others, accounts, invitations
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .family:      return "Family"
            case .others:      return "Others"
            case .accounts:    return "Accounts"
            case .invitations: return "Invitations"
            }
        }
        var icon: String {
            switch self {
            case .family:      return "figure.2.and.child.holdinghands"
            case .others:      return "person.2.wave.2.fill"
            case .accounts:    return "person.crop.circle.badge.checkmark"
            case .invitations: return "envelope.badge.clock.fill"
            }
        }
    }

    // Tenants are NOT family — they belong to the Tenants page and to the
    // "others" section here (tenants, workers, friends), never to the
    // family list.
    private static let familyRoles: Set<String> = ["owner", "partner", "member", "teen", "child"]

    private var children: [FamilyMember] {
        familyService.members.filter { $0.role == "child" }
    }

    // MARK: Unified people (accounts ∪ roster, deduped by user id)

    private var familyPeople: [HubPerson] { people(family: true) }
    private var otherPeople: [HubPerson] { people(family: false) }

    private func people(family: Bool) -> [HubPerson] {
        let myId = accountService.currentUserId
        var rosterByUserId: [UUID: FamilyMember] = [:]
        for m in familyService.members {
            if let uid = m.userId { rosterByUserId[uid] = m }
        }

        var linkedUserIds: Set<UUID> = []
        var result: [HubPerson] = []

        // 1. Active accounts, split family/outsider by the typed property
        //    role — the same gate RLS uses (PropertyRole.isFamilyMember).
        for account in accountService.members where account.status == "active" {
            guard let role = PropertyRole.resolve(account.role),
                  role.isFamilyMember == family else { continue }
            linkedUserIds.insert(account.userId)
            result.append(HubPerson(account: account,
                                    profile: accountService.profiles[account.userId],
                                    member: rosterByUserId[account.userId],
                                    isSelf: account.userId == myId))
        }

        // 2. Roster rows without an active account behind them.
        for m in familyService.members {
            guard Self.familyRoles.contains(m.role) == family else { continue }
            if let uid = m.userId, linkedUserIds.contains(uid) { continue }
            result.append(HubPerson(account: nil, profile: nil, member: m,
                                    isSelf: m.userId != nil && m.userId == myId))
        }

        return result
            .filter { $0.matchesSearch(searchText) }
            .sorted { a, b in
                if a.sortRank != b.sortRank { return a.sortRank < b.sortRank }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    private var filteredAccounts: [AccountMember] {
        accountService.members.filter { account in
            let profile = accountService.profiles[account.userId]
            return (profile?.bestName ?? "").matchesSearch(searchText)
                || (profile?.email ?? "").matchesSearch(searchText)
        }
    }

    private var filteredInvitations: [MemberInvitation] {
        invitationService.invitations.filter {
            $0.email.matchesSearch(searchText) || ($0.name ?? "").matchesSearch(searchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                segmentPicker

                switch segment {
                case .family:      familySection
                case .others:      othersSection
                case .accounts:    accountsSection
                case .invitations: invitationsSection
                }

                Spacer(minLength: 90)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .refreshable {
            await familyService.load()
            if let pid = propertyService.primary?.id {
                async let a: Void = invitationService.load(propertyId: pid)
                async let b: Void = accountService.load(propertyId: pid)
                async let c: Void = presenceService.load(propertyId: pid)
                _ = await (a, b, c)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    HapticFeedback.impact(.light)
                    showAdd = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Add member")
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { reload() }) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id,
                                 propertyName: propertyService.primary?.name,
                                 preselectedRole: segment == .others ? "guest" : "member")
                .environment(familyService)
        }
        .sheet(item: $editingMember, onDismiss: { reload() }) { member in
            EditMemberSheet(member: member, invitationService: invitationService)
                .environment(familyService)
                .environment(propertyService)
        }
        .sheet(item: $reviewingAccount) { account in
            AccountReviewSheet(member: account,
                               profile: accountService.profiles[account.userId],
                               service: accountService)
        }
        .task { reload() }
    }

    private func reload() {
        Task {
            await familyService.load()
            if let pid = propertyService.primary?.id {
                async let a: Void = invitationService.load(propertyId: pid)
                async let b: Void = accountService.load(propertyId: pid)
                async let c: Void = presenceService.load(propertyId: pid)
                _ = await (a, b, c)
                // Idempotent — live join/leave flips the green dots instantly.
                await presenceService.subscribe(propertyId: pid)
            }
        }
    }

    // MARK: Segment picker

    private var segmentPicker: some View {
        HStack(spacing: 6) {
            ForEach(Segment.allCases) { seg in
                let selected = segment == seg
                Button {
                    HapticFeedback.selection()
                    withAnimation(.snappy) { segment = seg }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: seg.icon).font(AppFont.label)
                        Text(seg.title).font(AppFont.captionEmphasis)
                        if seg == .invitations, pendingInviteCount > 0 {
                            Text("\(pendingInviteCount)")
                                .font(AppFont.scaled(10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.25), in: Capsule())
                        }
                    }
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.horizontal, AppSpacing.md).padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.05)),
                                in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pendingInviteCount: Int {
        invitationService.invitations.filter { !$0.accepted && !$0.isRevoked && !$0.isExpired }.count
    }

    // MARK: Family segment

    private var familySection: some View {
        VStack(spacing: 14) {
            if !children.isEmpty {
                NavigationLink {
                    SupervisionView()
                        .environment(familyService)
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "eyes", color: Color.brandPurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Supervision").font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                            Text("Screen rules and protection for children")
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                        Spacer()
                        Text("\(children.count)")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.brandPurple)
                        Image(systemName: "chevron.right")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.primary.opacity(0.25))
                    }
                    .padding(AppSpacing.base)
                    .liquidGlass(cornerRadius: AppRadius.lg)
                }
                .buttonStyle(.plain)
            }

            personList(familyPeople, empty: "No family members yet")
        }
    }

    // MARK: Others segment

    private var othersSection: some View {
        personList(otherPeople, empty: "No tenants, workers or friends yet")
    }

    @ViewBuilder
    private func personList(_ people: [HubPerson], empty: LocalizedStringKey) -> some View {
        if people.isEmpty {
            emptyState(icon: "person.crop.circle.badge.questionmark", text: empty)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { idx, person in
                    personRow(person)
                    if idx < people.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5).padding(.leading, 66)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    @ViewBuilder
    private func personRow(_ person: HubPerson) -> some View {
        let row = PersonHubRow(person: person, isOnline: isOnline(person))
        if person.isSelf {
            // Your own row is informational — profile/account editing lives in
            // Settings, so it deliberately isn't a button.
            row
        } else if let member = person.member {
            Button { editingMember = member } label: { row }
                .buttonStyle(.plain)
                .contextMenu { personMenu(person) } preview: { personPreview(person) }
        } else if let account = person.account {
            Button { reviewingAccount = account } label: { row }
                .buttonStyle(.plain)
                .contextMenu { personMenu(person) } preview: { personPreview(person) }
        } else {
            row
        }
    }

    // MARK: Long-press preview (PreviewCard)
    //
    // Real fields only: avatar, name, role — plus e-mail/phone rows and the
    // "member since" subtitle exactly when the person actually has them.
    private func personPreview(_ person: HubPerson) -> some View {
        PreviewCard(
            title: Text(verbatim: person.displayName),
            subtitle: person.joinedDate.map {
                Text("mem_member_since \($0.formatted(.dateTime.month(.wide).year()))")
            },
            tint: person.roleColor,
            details: personDetails(person),
            chips: isOnline(person)
                ? [PreviewCardChip(icon: "circle.fill", text: Text("convo_online"), tint: .brandSuccess)]
                : []
        ) {
            HubAvatar(member: person.member,
                      avatarUrl: person.profile?.avatarUrl,
                      name: person.displayName,
                      size: 54)
        }
    }

    private func personDetails(_ person: HubPerson) -> [PreviewCardDetail] {
        var rows: [PreviewCardDetail] = [
            PreviewCardDetail(icon: "person.text.rectangle",
                              label: Text("Role"),
                              value: Text(person.roleLabel)),
        ]
        if let email = person.email {
            rows.append(PreviewCardDetail(icon: "envelope.fill",
                                          label: Text("E-mail"),
                                          value: Text(verbatim: email)))
        }
        if let phone = person.phone {
            rows.append(PreviewCardDetail(icon: "phone.fill",
                                          label: Text("Phone"),
                                          value: Text(verbatim: phone)))
        }
        return rows
    }

    private func isOnline(_ person: HubPerson) -> Bool {
        guard let uid = person.userId else { return false }
        return presenceService.status(userId: uid) == .online
    }

    @ViewBuilder
    private func personMenu(_ person: HubPerson) -> some View {
        if person.chatTarget != nil {
            Button {
                openChat(with: person)
            } label: {
                Label("mem_send_message", systemImage: "bubble.left.fill")
            }
        }
        if let phone = person.phone {
            Button {
                call(phone)
            } label: {
                Label("Call", systemImage: "phone.fill")
            }
        }
        if let account = person.account {
            Button { reviewingAccount = account } label: {
                Label("Review account", systemImage: "person.text.rectangle")
            }
        }
    }

    /// Lands on the chat tab with the DM target persisted — the exact route a
    /// tapped chat push takes (ChatNotificationTarget → .prvioOpenChat →
    /// MainTabView switches tab → ConversationsView drains and opens the
    /// thread), so Members needs no chat-stack plumbing of its own.
    private func openChat(with person: HubPerson) {
        guard let target = person.chatTarget else { return }
        HapticFeedback.impact(.light)
        ChatNotificationTarget.store(target)
        NotificationCenter.default.post(name: .prvioOpenChat, object: nil)
    }

    private func call(_ phone: String) {
        let dial = phone.filter { $0.isNumber || $0 == "+" }
        guard !dial.isEmpty, let url = URL(string: "tel://\(dial)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Accounts segment

    @ViewBuilder
    private var accountsSection: some View {
        if accountService.isLoading && accountService.members.isEmpty {
            ProgressView().padding(.top, 40)
        } else if accountService.members.isEmpty {
            emptyState(icon: "person.crop.circle.badge.checkmark",
                       text: "No one has an account yet. Accepted invitations appear here.")
        } else if !searchText.isEmpty && filteredAccounts.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "No results")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(filteredAccounts.enumerated()), id: \.element.id) { idx, account in
                    Button { reviewingAccount = account } label: {
                        AccountMemberRow(member: account,
                                         profile: accountService.profiles[account.userId])
                    }
                    .buttonStyle(.plain)
                    .contextMenu { accountMenu(account) } preview: { accountPreview(account) }
                    if idx < filteredAccounts.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5).padding(.leading, 66)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    /// Long-press preview for the Accounts segment: live profile data only.
    /// A profile that hasn't loaded (or was deleted) falls back to the role
    /// label as the title — real data, never a fabricated name.
    private func accountPreview(_ account: AccountMember) -> some View {
        let profile = accountService.profiles[account.userId]
        let name = profile?.bestName ?? ""
        var rows: [PreviewCardDetail] = [
            PreviewCardDetail(icon: "person.text.rectangle",
                              label: Text("Role"),
                              value: Text(accountRoleLabel(account.role))),
        ]
        if let email = profile?.email, !email.isEmpty {
            rows.append(PreviewCardDetail(icon: "envelope.fill",
                                          label: Text("E-mail"),
                                          value: Text(verbatim: email)))
        }
        if let phone = profile?.phone, !phone.isEmpty {
            rows.append(PreviewCardDetail(icon: "phone.fill",
                                          label: Text("Phone"),
                                          value: Text(verbatim: phone)))
        }
        return PreviewCard(
            title: name.isEmpty ? Text(accountRoleLabel(account.role)) : Text(verbatim: name),
            subtitle: account.joinedDate.map {
                Text("mem_member_since \($0.formatted(.dateTime.month(.wide).year()))")
            },
            tint: .accentColor,
            details: rows,
            chips: account.isBlocked
                ? [PreviewCardChip(icon: "hand.raised.fill", text: Text("Blocked"), tint: .brandDanger)]
                : []
        ) {
            HubAvatar(member: nil, avatarUrl: profile?.avatarUrl, name: name, size: 54)
        }
    }

    @ViewBuilder
    private func accountMenu(_ account: AccountMember) -> some View {
        Button { reviewingAccount = account } label: {
            Label("Review account", systemImage: "person.text.rectangle")
        }
        if accountService.canAdminister,
           account.role != "owner",
           account.userId != accountService.currentUserId {
            if account.isBlocked {
                Button {
                    Task { try? await accountService.unblock(account); HapticFeedback.success() }
                } label: {
                    Label("Unblock access", systemImage: "lock.open.fill")
                }
            } else {
                Menu {
                    Button { blockAccount(account, days: 1) } label: { Text("For 1 day") }
                    Button { blockAccount(account, days: 7) } label: { Text("For 7 days") }
                    Button { blockAccount(account, days: 30) } label: { Text("For 30 days") }
                    Button(role: .destructive) { blockAccount(account, days: nil) } label: {
                        Text("Indefinitely")
                    }
                } label: {
                    Label("Block access", systemImage: "hand.raised.fill")
                }
            }
            Divider()
            Button(role: .destructive) { reviewingAccount = account } label: {
                Label("Delete account", systemImage: "trash")
            }
        }
    }

    private func blockAccount(_ account: AccountMember, days: Int?) {
        Task {
            let until = days.map { Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date() }
            try? await accountService.block(account, until: until)
            HapticFeedback.success()
        }
    }

    // MARK: Invitations segment

    private var pendingInvitations: [MemberInvitation] {
        filteredInvitations.filter { !$0.accepted && !$0.isRevoked }
    }
    private var acceptedInvitations: [MemberInvitation] {
        filteredInvitations.filter { $0.accepted && !$0.isRevoked }
    }
    private var revokedInvitations: [MemberInvitation] {
        filteredInvitations.filter { $0.isRevoked }
    }

    @ViewBuilder
    private var invitationsSection: some View {
        if invitationService.isLoading && invitationService.invitations.isEmpty {
            ProgressView().padding(.top, 40)
        } else if invitationService.invitations.isEmpty {
            emptyState(icon: "envelope.open",
                       text: "No invitations sent yet. Add a member with an email to invite them.")
        } else if !searchText.isEmpty && filteredInvitations.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "No results")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !pendingInvitations.isEmpty {
                    inviteSectionHeader("mem_invites_pending", count: pendingInvitations.count)
                    ForEach(pendingInvitations) { inv in
                        InvitationRow(invitation: inv,
                                      onResend: { resend(inv) },
                                      onRevoke: { revoke(inv) })
                    }
                }

                if !acceptedInvitations.isEmpty {
                    inviteSectionHeader("mem_invites_accepted", count: acceptedInvitations.count)
                    ForEach(acceptedInvitations) { inv in
                        InvitationRow(invitation: inv)
                    }
                }

                if !revokedInvitations.isEmpty {
                    revokedHistoryToggle
                    if showRevokedHistory {
                        ForEach(revokedInvitations) { inv in
                            InvitationRow(invitation: inv)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private func inviteSectionHeader(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            Text(verbatim: "\(count)")
                .font(AppFont.label).monospacedDigit()
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        }
        .padding(.leading, AppSpacing.xxs)
        .padding(.top, AppSpacing.xs)
    }

    /// Revoked invitations are an audit trail, not daily business — folded
    /// behind one honest "show history" toggle.
    private var revokedHistoryToggle: some View {
        Button {
            HapticFeedback.impact(.light)
            withAnimation(.smooth(duration: 0.3)) { showRevokedHistory.toggle() }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Text("mem_show_history")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Text(verbatim: "\(revokedInvitations.count)")
                    .font(AppFont.label).monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .rotationEffect(.degrees(showRevokedHistory ? 180 : 0))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showRevokedHistory ? [.isSelected] : [])
    }

    private func resend(_ inv: MemberInvitation) {
        guard let pid = propertyService.primary?.id else { return }
        Task {
            let err = await familyService.sendInvite(
                to: inv.email, name: inv.name ?? "", role: inv.role,
                propertyId: pid, propertyName: propertyService.primary?.name)
            if err == nil { HapticFeedback.success() }
            await invitationService.load(propertyId: pid)
        }
    }

    private func revoke(_ inv: MemberInvitation) {
        guard let pid = propertyService.primary?.id else { return }
        Task {
            await invitationService.revoke(inv, propertyId: pid)
            HapticFeedback.impact(.medium)
        }
    }

    private func emptyState(icon: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.scaled(34))
                .foregroundStyle(Color.primary.opacity(0.25))
            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Unified person (account ∪ roster)

/// One human in the Family/Others lists: an active account (property_members
/// + live profile), a hand-added roster row (family_members), or both merged
/// by auth user id. Display data prefers the live profile; contact details
/// prefer the roster (that's where hand-entered phones live).
private struct HubPerson: Identifiable {
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

private struct PersonHubRow: View {
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
private struct HubAvatar: View {
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

private struct InvitationRow: View {
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

// MARK: - Edit member sheet

struct EditMemberSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember
    let invitationService: InvitationService

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var role: String = "member"
    @State private var color: String = "#5B8AF5"
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    /// Empty is fine (e-mail is optional); non-empty must pass the shared
    /// EmailFormat authority — same rule as the add-member and tenant flows.
    private var emailFieldOK: Bool {
        email.trimmingCharacters(in: .whitespaces).isEmpty || EmailFormat.isValid(email)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Identity preview
                        ZStack {
                            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
                            Text(String(name.prefix(2)).uppercased())
                                .font(AppFont.scaled(26, weight: .bold))
                                .foregroundStyle(Color(hex: color) ?? .blue)
                        }
                        .frame(width: 76, height: 76)
                        .padding(.top, AppSpacing.sm)

                        HStack(spacing: 10) {
                            ForEach(kColors, id: \.self) { c in
                                Button { color = c } label: {
                                    Circle().fill(Color(hex: c) ?? .blue)
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: color == c ? 2 : 0))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(spacing: 0) {
                            editRow(icon: "person.fill", tint: .blue, placeholder: "Name", text: $name)
                            div
                            editRow(icon: "envelope.fill", tint: .orange, placeholder: "E-mail", text: $email,
                                    keyboard: .emailAddress)
                            div
                            editRow(icon: "phone.fill", tint: Color.brandSuccess, placeholder: "Phone", text: $phone,
                                    keyboard: .phonePad)
                            div
                            HStack(spacing: 12) {
                                Image(systemName: kRoleIcons[role] ?? "person.fill")
                                    .font(AppFont.scaled(14)).foregroundStyle(.purple).frame(width: 28)
                                Text("Role").font(AppFont.scaled(15)).foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $role) {
                                    ForEach(kRoles.filter { $0 != "owner" } + (role == "owner" ? ["owner"] : []), id: \.self) { r in
                                        Text(LocalizedStringKey(kRoleLabels[r] ?? r.capitalized)).tag(r)
                                    }
                                }
                                .tint(Color.primary.opacity(AppOpacity.mediumText))
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.xs)
                        }
                        .liquidGlass(cornerRadius: AppRadius.lg)

                        if !emailFieldOK {
                            Label {
                                Text("This e-mail address doesn't look valid")
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.brandDanger)
                            } icon: {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.brandDanger)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, AppSpacing.xxs)
                        }

                        if let err = errorMessage {
                            Text(err).font(AppFont.scaled(13)).foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        if member.role != "owner" {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("Remove member")
                                }
                                .font(AppFont.subheadline)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Save").font(AppFont.subheadline).foregroundStyle(Color.accentColor) }
                    }
                    .disabled(isSaving
                              || name.trimmingCharacters(in: .whitespaces).isEmpty
                              || !emailFieldOK)
                }
            }
            .confirmationDialog("Remove this member?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove member", role: .destructive) { Task { await remove() } }
            } message: {
                Text("They lose access to the home and are removed from the member list. This cannot be undone.")
            }
        }
        .onAppear {
            name = member.name
            email = member.email ?? ""
            phone = member.phone ?? ""
            role = member.role
            color = member.color
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = member
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.email = email.isEmpty ? nil : email
        updated.phone = phone.isEmpty ? nil : phone
        updated.role = role
        updated.color = color
        if await familyService.update(updated) {
            HapticFeedback.success()
            dismiss()
        } else {
            errorMessage = familyService.error ?? String(localized: "Couldn't save changes.")
            HapticFeedback.warning()
        }
    }

    private func remove() async {
        do {
            try await invitationService.removeMember(familyMemberId: member.id)
            await familyService.load()
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func editRow(icon: String, tint: Color, placeholder: LocalizedStringKey,
                         text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(tint).frame(width: 28)
            TextField(placeholder, text: text)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}

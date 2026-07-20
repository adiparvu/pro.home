import SwiftUI

// MARK: - MembersHubView — family / others / accounts /
// invitations segments (mechanically extracted from
// MembersHubView.swift; bodies unchanged).

extension MembersHubView {
    // MARK: Family segment

    var familySection: some View {
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

    var othersSection: some View {
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
                : [],
            socialLinks: person.profile?.socialLinks ?? person.member?.socialLinks ?? []
        ) {
            HubAvatar(member: person.member,
                      avatarUrl: person.profile?.avatarUrl,
                      name: person.displayName,
                      size: 54)
        }
    }

    private func personDetails(_ person: HubPerson) -> [PreviewCardDetail] {
        var rows: [PreviewCardDetail] = []
        // The full name from the profile, when it says more than the title
        // already does (the title shows the display name / nickname).
        if let full = person.profile?.fullName?.trimmingCharacters(in: .whitespaces),
           !full.isEmpty, full != person.displayName {
            rows.append(PreviewCardDetail(icon: "person.fill",
                                          label: Text("Name"),
                                          value: Text(verbatim: full)))
        }
        rows.append(PreviewCardDetail(icon: "person.text.rectangle",
                                      label: Text("Role"),
                                      value: Text(person.roleLabel)))
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
        if let birthday = birthdayText(person.profile?.birthDate) {
            rows.append(PreviewCardDetail(icon: "birthday.cake.fill",
                                          label: Text("cal_birthday"),
                                          value: birthday))
        }
        return rows
    }

    /// "yyyy-MM-dd" from profiles → a localized "14 iunie 1996". nil (absent
    /// or unparseable) simply hides the row — real fields only.
    private func birthdayText(_ raw: String?) -> Text? {
        guard let raw, let date = AppDate.day(from: raw) else { return nil }
        return Text(verbatim: date.formatted(.dateTime.day().month(.wide).year()))
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
    var accountsSection: some View {
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
        var rows: [PreviewCardDetail] = []
        if let full = profile?.fullName?.trimmingCharacters(in: .whitespaces),
           !full.isEmpty, full != name {
            rows.append(PreviewCardDetail(icon: "person.fill",
                                          label: Text("Name"),
                                          value: Text(verbatim: full)))
        }
        rows.append(PreviewCardDetail(icon: "person.text.rectangle",
                                      label: Text("Role"),
                                      value: Text(accountRoleLabel(account.role))))
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
        if let birthday = birthdayText(profile?.birthDate) {
            rows.append(PreviewCardDetail(icon: "birthday.cake.fill",
                                          label: Text("cal_birthday"),
                                          value: birthday))
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
                : [],
            socialLinks: profile?.socialLinks ?? []
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
    var invitationsSection: some View {
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
                .foregroundStyle(Color.backdropSecondaryText)
            Text(verbatim: "\(count)")
                .font(AppFont.label).monospacedDigit()
                .foregroundStyle(Color.backdropSecondaryText)
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

import SwiftUI

// MARK: - Members hub
//
// One home for everyone with access to the house: the family (with child
// supervision), non-family members (tenants, workers, friends) and the
// invitation audit trail (who was invited, when, and for how long the link is
// still valid). Replaces the separate "Family Members" + "Supervision" rows.

struct MembersHubView: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService

    @State private var invitationService = InvitationService()
    @State private var accountService = AccountMemberService()
    @State private var segment: Segment = .family
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?
    @State private var reviewingAccount: AccountMember?

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

    private static let familyRoles: Set<String> = ["owner", "partner", "member", "child", "tenant"]

    private var familyMembers: [FamilyMember] {
        familyService.members.filter { Self.familyRoles.contains($0.role) && matchesMemberSearch($0) }
    }
    private var otherMembers: [FamilyMember] {
        familyService.members.filter { !Self.familyRoles.contains($0.role) && matchesMemberSearch($0) }
    }
    private var children: [FamilyMember] {
        familyService.members.filter { $0.role == "child" }
    }

    private func matchesMemberSearch(_ member: FamilyMember) -> Bool {
        member.name.matchesSearch(searchText) || (member.email ?? "").matchesSearch(searchText)
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
                PageHeader(titleKey: "Members", subtitleKey: "HOUSEHOLD")
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
                _ = await (a, b)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                        .font(.system(size: 16, weight: .semibold))
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
                _ = await (a, b)
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
                        Image(systemName: seg.icon).font(.system(size: 11, weight: .semibold))
                        Text(seg.title).font(AppFont.captionEmphasis)
                        if seg == .invitations, pendingInviteCount > 0 {
                            Text("\(pendingInviteCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
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
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                        Spacer()
                        Text("\(children.count)")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.brandPurple)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.25))
                    }
                    .padding(AppSpacing.base)
                    .liquidGlass(cornerRadius: AppRadius.lg)
                }
                .buttonStyle(.plain)
            }

            memberList(familyMembers, empty: "No family members yet")
        }
    }

    // MARK: Others segment

    private var othersSection: some View {
        memberList(otherMembers, empty: "No tenants, workers or friends yet")
    }

    @ViewBuilder
    private func memberList(_ members: [FamilyMember], empty: LocalizedStringKey) -> some View {
        if members.isEmpty {
            emptyState(icon: "person.crop.circle.badge.questionmark", text: empty)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { idx, member in
                    Button { editingMember = member } label: {
                        MemberHubRow(member: member)
                    }
                    .buttonStyle(.plain)
                    if idx < members.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5).padding(.leading, 66)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
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
                    .contextMenu { accountMenu(account) }
                    if idx < filteredAccounts.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5).padding(.leading, 66)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
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
            VStack(spacing: 12) {
                ForEach(filteredInvitations) { inv in
                    InvitationRow(invitation: inv,
                                  onResend: { resend(inv) },
                                  onRevoke: { revoke(inv) })
                }
            }
        }
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
                .font(.system(size: 34))
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

// MARK: - Member row

private struct MemberHubRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                if let email = member.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(LocalizedStringKey(kRoleLabels[member.role] ?? member.role.capitalized))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(member.swiftColor)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(member.swiftColor.opacity(0.14), in: Capsule())
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Invitation row

private struct InvitationRow: View {
    let invitation: MemberInvitation
    let onResend: () -> Void
    let onRevoke: () -> Void

    private var status: (text: LocalizedStringKey, color: Color) {
        if invitation.isRevoked { return ("Revoked", .red) }
        if invitation.accepted { return ("Accepted", Color.brandSuccess) }
        if invitation.isExpired { return ("Expired", .gray) }
        let d = max(invitation.daysLeft, 0)
        return (d == 1 ? "Expires in 1 day" : "Expires in \(d) days", .orange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "envelope.fill", color: status.color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.name?.isEmpty == false ? invitation.name! : invitation.email)
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Text(invitation.email)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
                Spacer()
                Text(status.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(status.color.opacity(0.13), in: Capsule())
            }
            HStack(spacing: 10) {
                Label {
                    Text(String(format: String(localized: "Sent %@"), invitation.sentDisplay))
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "paperplane").font(.system(size: 10))
                }
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))

                Text(LocalizedStringKey(kRoleLabels[invitation.role] ?? invitation.role.capitalized))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))

                Spacer()

                if !invitation.accepted && !invitation.isRevoked {
                    Button { onResend() } label: {
                        Text("Resend")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                if !invitation.isRevoked {
                    Button(role: .destructive) { onRevoke() } label: {
                        Text("Revoke")
                            .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 26, weight: .bold))
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
                                    .font(.system(size: 14)).foregroundStyle(.purple).frame(width: 28)
                                Text("Role").font(.system(size: 15)).foregroundStyle(.primary)
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

                        if let err = errorMessage {
                            Text(err).font(.system(size: 13)).foregroundStyle(.red)
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
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
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
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint).frame(width: 28)
            TextField(placeholder, text: text)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}

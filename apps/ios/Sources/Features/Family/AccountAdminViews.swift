import SwiftUI

// MARK: - Account members UI (Members hub "Accounts" segment)
//
// Rows and the review/admin sheet for people with real PRVIO accounts:
// details review, role change, block-for-a-period and account deletion.

func accountRoleLabel(_ role: String) -> LocalizedStringKey {
    switch role {
    case "owner":            return "Owner"
    case "partner":          return "Partner"
    case "family_adult":     return "Member"
    case "family_teen":      return "Teen"
    case "family_child":     return "Child"
    case "family_elderly":   return "Member"
    case "tenant":           return "Tenant"
    case "service_provider": return "Worker"
    case "guest":            return "Guest"
    default:                 return LocalizedStringKey(role.capitalized)
    }
}

private let kAssignableRoles = ["partner", "family_adult", "family_teen",
                                "family_child", "family_elderly", "tenant",
                                "service_provider", "guest"]

// MARK: - Row

struct AccountMemberRow: View {
    let member: AccountMember
    let profile: AccountProfile?

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.bestName ?? member.nickname ?? "—")
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                if let email = profile?.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
            }
            Spacer()
            if member.isBlocked {
                statusChip("Blocked", color: Color.brandDanger, icon: "hand.raised.fill")
            }
            Text(accountRoleLabel(member.role))
                .font(AppFont.label)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
            Image(systemName: "chevron.right")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            if let urlStr = profile?.avatarUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay {
            if member.isBlocked {
                Circle().strokeBorder(Color.brandDanger.opacity(0.7), lineWidth: 1.5)
            }
        }
        .opacity(member.isBlocked ? 0.55 : 1)
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.18))
            Text(String((profile?.bestName ?? "?").prefix(2)).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func statusChip(_ text: LocalizedStringKey, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: - Review / admin sheet

struct AccountReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let member: AccountMember
    let profile: AccountProfile?
    let service: AccountMemberService

    @State private var role: String
    @State private var isWorking = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(member: AccountMember, profile: AccountProfile?, service: AccountMemberService) {
        self.member = member
        self.profile = profile
        self.service = service
        _role = State(initialValue: member.role)
    }

    private var live: AccountMember {
        service.members.first { $0.id == member.id } ?? member
    }

    private var isOwnerRow: Bool { live.role == "owner" }
    private var isSelf: Bool { live.userId == service.currentUserId }
    private var canAdmin: Bool { service.canAdminister && !isOwnerRow && !isSelf }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header
                        detailsCard
                        if canAdmin {
                            roleCard
                            blockCard
                            deleteButton
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.brandDanger)
                                .multilineTextAlignment(.center)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.primary)
                }
            }
            .confirmationDialog("Delete this account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their account and access are permanently removed. This cannot be undone.")
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                if let urlStr = profile?.avatarUrl, let url = URL(string: urlStr) {
                    StorageImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            initials
                        }
                    }
                } else {
                    initials
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())

            Text(profile?.bestName ?? live.nickname ?? "—")
                .font(AppFont.title3)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Text(accountRoleLabel(live.role))
                    .font(AppFont.label)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                if live.isBlocked {
                    Label(blockedLabel, systemImage: "hand.raised.fill")
                        .font(AppFont.label)
                        .foregroundStyle(Color.brandDanger)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.brandDanger.opacity(0.13), in: Capsule())
                }
            }
        }
        .padding(.top, AppSpacing.sm)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.18))
            Text(String((profile?.bestName ?? "?").prefix(2)).uppercased())
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var blockedLabel: String {
        if let until = live.blockedUntilDate {
            return String(format: String(localized: "Blocked until %@"),
                          until.formatted(date: .abbreviated, time: .omitted))
        }
        return String(localized: "Blocked")
    }

    private var detailsCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if let email = profile?.email, !email.isEmpty {
                    infoRow("envelope.fill", "E-mail", email, .orange)
                    div
                }
                if let phone = profile?.phone, !phone.isEmpty {
                    infoRow("phone.fill", "Phone", phone, Color.brandSuccess)
                    div
                }
                if let joined = live.joinedDate {
                    infoRow("calendar", "Joined", joined.formatted(date: .abbreviated, time: .omitted), .blue)
                    div
                }
                infoRow("shield.lefthalf.filled", "Status",
                        live.isBlocked ? String(localized: "Blocked") : String(localized: "Active"),
                        live.isBlocked ? Color.brandDanger : Color.brandSuccess)
            }
        }
    }

    private var roleCard: some View {
        GlassCard(padding: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brandPurple)
                    .frame(width: 28)
                Text("Role").font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
                Picker("", selection: $role) {
                    ForEach(kAssignableRoles, id: \.self) { r in
                        Text(accountRoleLabel(r)).tag(r)
                    }
                }
                .tint(Color.primary.opacity(AppOpacity.mediumText))
                .disabled(isWorking)
                .onChange(of: role) { _, newRole in
                    guard newRole != live.role else { return }
                    Task { await changeRole(newRole) }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xs)
        }
    }

    private var blockCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if live.isBlocked {
                    actionRow("lock.open.fill", "Unblock access", Color.brandSuccess) {
                        Task { await unblock() }
                    }
                } else {
                    Menu {
                        Button { Task { await block(days: 1) } } label: { Text("For 1 day") }
                        Button { Task { await block(days: 7) } } label: { Text("For 7 days") }
                        Button { Task { await block(days: 30) } } label: { Text("For 30 days") }
                        Button(role: .destructive) { Task { await block(days: nil) } } label: {
                            Text("Indefinitely")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.brandWarning)
                                .frame(width: 28)
                            Text("Block access")
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            HStack {
                if isWorking { ProgressView().tint(.red) }
                Image(systemName: "trash.fill")
                Text("Delete account")
            }
            .font(AppFont.subheadline)
            .foregroundStyle(Color.brandDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.brandDanger.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    // MARK: Actions

    private func changeRole(_ newRole: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.updateRole(live, to: newRole)
            HapticFeedback.success()
        } catch {
            role = live.role
            errorMessage = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    private func block(days: Int?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let until = days.map { Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date() }
            try await service.block(live, until: until)
            HapticFeedback.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    private func unblock() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.unblock(live)
            HapticFeedback.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.deleteAccount(live)
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            HapticFeedback.warning()
        }
    }

    // MARK: Bits

    private func infoRow(_ icon: String, _ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(label).font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private func actionRow(_ icon: String, _ label: LocalizedStringKey, _ color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(label).font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}

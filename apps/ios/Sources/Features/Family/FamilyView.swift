import SwiftUI

// MARK: - Main view

struct FamilyView: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @State private var showAdd = false
    @State private var selectedMember: FamilyMember?
    @State private var searchText = ""

    /// The roles that belong on the FAMILY page. Tenants, workers and
    /// guests are household contacts — they live in Members/Tenants, never
    /// here (IMG_8551: a "guest" was showing up as family).
    private static let familyRoles: Set<String> = ["owner", "partner", "member", "teen", "child"]

    private var familyMembers: [FamilyMember] {
        familyService.members.filter { Self.familyRoles.contains($0.role) }
    }

    private var filteredMembers: [FamilyMember] {
        guard !searchText.isEmpty else { return familyMembers }
        return familyMembers.filter { member in
            var haystack = [member.name, member.role, member.roleLabel, member.email ?? ""]
            if let bd = member.birthdayDate {
                let comps = Calendar.current.dateComponents([.month, .day], from: bd)
                if let d = comps.day, let m = comps.month {
                    haystack.append("\(d)/\(m)")   // the visible "🎂 d/m" badge
                }
            }
            return haystack.contains { $0.matchesSearch(searchText) }
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if familyService.isLoading && familyService.members.isEmpty {
                    Spacer(); ProgressView().tint(.white); Spacer()
                } else if familyMembers.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            // The family's reward chart lives with the family,
                            // not buried in Finances.
                            ChoresEntryCard()
                                .padding(.bottom, AppSpacing.xs)
                            ForEach(filteredMembers) { member in
                                FamilyMemberRow(member: member)
                                    .onTapGesture { selectedMember = member }
                                    // Long-press: a real profile PEEK plus the
                                    // quick actions, Contacts-style (IMG_8551).
                                    .contextMenu {
                                        Button {
                                            selectedMember = member
                                        } label: {
                                            Label("View profile", systemImage: "person.crop.circle")
                                        }
                                        if let phone = member.phone, !phone.isEmpty {
                                            Button {
                                                if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                                    UIApplication.shared.open(url)
                                                }
                                            } label: {
                                                Label("Call member", systemImage: "phone.fill")
                                            }
                                        }
                                        if let email = member.email, !email.isEmpty {
                                            Button {
                                                if let url = URL(string: "mailto:\(email)") {
                                                    UIApplication.shared.open(url)
                                                }
                                            } label: {
                                                Label("Email member", systemImage: "envelope.fill")
                                            }
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await familyService.delete(member) }
                                        } label: { Label("Remove", systemImage: "trash") }
                                    } preview: {
                                        MemberPeekCard(member: member)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await familyService.delete(member) }
                                        } label: { Label("Remove", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button { selectedMember = member } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.accentColor)
                                    }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.bottom, 110)
                    }
                    .refreshable { await familyService.load() }
                }
            }
        }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .floatingSpeedDial(.family)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "person.badge.plus")
                        .font(AppFont.scaled(20, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add member")
            }
        }
        .task { await familyService.load() }
        // Pull the live profile photos so account holders show their current
        // avatar (not the family_members snapshot), and refresh on every
        // appearance so a member's new photo is already here.
        .task {
            await MemberDirectory.shared.loadIfNeeded()
            MemberDirectory.shared.refreshSoon()
        }
        .sheet(isPresented: $showAdd) {
            AddFamilyMemberSheet(
                propertyId: propertyService.primary?.id,
                propertyName: propertyService.primary?.name
            )
        }
        .sheet(item: $selectedMember) { member in
            MemberProfileSheet(member: member)
        }
        .alert("Error", isPresented: Binding(
            get: { familyService.error != nil },
            set: { if !$0 { familyService.error = nil } }
        )) {
            Button("OK") { familyService.error = nil }
        } message: { Text(LocalizedStringKey(familyService.error ?? "")) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.2.fill").font(AppFont.scaled(52)).foregroundStyle(Color.primary.opacity(0.15))
            Text("No members").font(AppFont.title3).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text("Add family members to collaborate on tasks and chat.").font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Add first member") { showAdd = true }.font(AppFont.scaled(14)).foregroundStyle(Color.accentColor)
            Spacer()
        }
    }
}

// MARK: - Long-press peek

/// The compact profile card shown as the context-menu PREVIEW: the fast
/// "who is this" read — live avatar, name, role, birthday and the contact
/// lines — without committing to the full profile sheet.
private struct MemberPeekCard: View {
    let member: FamilyMember

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            MemberAvatar(member: member, size: 76)
            VStack(spacing: 3) {
                Text(member.name)
                    .font(AppFont.title3)
                    .foregroundStyle(.primary)
                Text(LocalizedStringKey(member.roleLabel))
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if let phone = member.phone, !phone.isEmpty {
                    peekLine(icon: "phone.fill", text: phone)
                }
                if let email = member.email, !email.isEmpty {
                    peekLine(icon: "envelope.fill", text: email)
                }
                if let bd = member.birthdayDate {
                    peekLine(icon: "gift.fill",
                             text: bd.formatted(.dateTime.day().month(.wide)))
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 290)
    }

    private func peekLine(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppFont.scaled(12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(verbatim: text)
                .font(AppFont.scaled(13))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - Row

struct FamilyMemberRow: View {
    let member: FamilyMember

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                MemberAvatar(member: member, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(member.roleLabel))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        if let bd = member.birthdayDate {
                            let calendar = Calendar.current
                            let comps = calendar.dateComponents([.month, .day], from: bd)
                            if let m = comps.month, let d = comps.day {
                                Text("·").foregroundStyle(Color.primary.opacity(0.2)).font(AppFont.scaled(12))
                                Text("🎂 \(d)/\(m)")
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    if let phone = member.phone, !phone.isEmpty {
                        quickActionBtn(icon: "phone.fill") {
                            if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    if let email = member.email, !email.isEmpty {
                        quickActionBtn(icon: "envelope.fill") {
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
    }

    private func quickActionBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
        }
        .glassCircle()
        .accessibilityLabel(icon == "phone.fill" ? "Call member" : "Email member")
    }
}

// MARK: - Avatar (shared)

struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 38

    // Always prefer the LIVE profile photo for account holders over the
    // `family_members` snapshot — reading the @Observable directory here
    // subscribes this view, so a new avatar (this member's or anyone's,
    // on any device) repaints instantly. Falls back to the row snapshot,
    // then to coloured initials.
    private var effectiveAvatar: String? {
        MemberDirectory.shared.avatarString(userId: member.userId, fallback: member.avatarUrl)
    }

    var body: some View {
        if let urlStr = effectiveAvatar, !urlStr.isEmpty {
            StorageImage(source: urlStr) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { initials }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(member.swiftColor.opacity(0.25))
                .overlay(Circle().strokeBorder(member.swiftColor.opacity(0.5), lineWidth: 1.5))
            Text(member.initials)
                .font(.system(size: size * 0.33, weight: .bold))
                .foregroundStyle(member.swiftColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Member picker (shared for tasks/chat)

struct MemberPickerView: View {
    @Environment(FamilyService.self) private var familyService
    @Binding var selectedIds: [String]
    @Binding var selectedNames: [String]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(familyService.members) { m in
                let selected = selectedIds.contains(m.id.uuidString)
                Button {
                    HapticFeedback.selection()
                    if selected {
                        selectedIds.removeAll { $0 == m.id.uuidString }
                        selectedNames.removeAll { $0 == m.name }
                    } else {
                        selectedIds.append(m.id.uuidString)
                        selectedNames.append(m.name)
                    }
                } label: {
                    HStack(spacing: 12) {
                        MemberAvatar(member: m, size: 36)
                        Text(m.name).font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(m.swiftColor).font(AppFont.scaled(20))
                        } else {
                            Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                    .background(Color.primary.opacity(selected ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

import SwiftUI
import Combine

// MARK: - Groups (UI shell)
//
// Groups — multiple named chat groups per property (workers, family, …),
// backed by chat_groups / chat_group_members (migration 078). This screen lists
// and creates groups and manages their members. (The type keeps its historical
// "Communities" name because ChatSettingsView also presents it; only the
// user-facing wording changed.)

struct CommunitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var service = ChatGroupService()

    var propertyId: UUID? = nil
    var members: [FamilyMember] = []
    var myName: String = "Me"

    @State private var showCreate = false
    /// Value-based path so a deep link (prvio://communities/<id>) can open a
    /// specific group programmatically, not just by tap.
    @State private var path: [ChatGroup] = []
    @State private var searchText = ""

    private var filteredGroups: [ChatGroup] {
        guard !searchText.isEmpty else { return service.groups }
        return service.groups.filter {
            $0.name.matchesSearch(searchText)
                || $0.kindLabel.matchesSearch(searchText)
                || (service.previewLine(for: $0)?.text ?? "").matchesSearch(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    newGroupButton

                    if service.groups.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredGroups) { group in
                                NavigationLink(value: group) {
                                    CommunityRow(group: group,
                                                 memberCount: service.members(for: group).count,
                                                 preview: service.previewLine(for: group),
                                                 avatarMembers: resolvedMembers(of: group))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, AppSpacing.sm)
            }
            .navigationDestination(for: ChatGroup.self) { group in
                GroupChatView(group: group,
                              propertyId: propertyId,
                              myName: myName,
                              members: members,
                              service: service)
            }
            .navigationTitle("chat_groups_title")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text("Search…"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showCreate) {
                CreateGroupSheet(members: members) { name, selected in
                    showCreate = false
                    guard let pid = propertyId else { return }
                    Task {
                        // Kinds are no longer chosen at creation — every new
                        // group is a plain one; legacy kinds keep their icons.
                        if let created = await service.create(propertyId: pid, name: name, kind: "custom",
                                                              selected: selected, myName: myName) {
                            // Land straight in the new conversation.
                            path = [created]
                        }
                    }
                }
            }
            .task {
                if let pid = propertyId { await service.load(propertyId: pid) }
                openDeepLinkedGroupIfNeeded()
            }
            // A second deep link while the sheet is already up re-targets the
            // path instead of relying on a fresh .task.
            .onChange(of: router.communitiesRequest) { _, _ in
                openDeepLinkedGroupIfNeeded()
            }
            // A shared task card asked for the Tasks page — clear the stage.
            .onChange(of: router.dismissGeneration) { _, _ in
                dismiss()
            }
        }
        .presentationBackground(.thinMaterial)
    }

    /// Opens the group a deep link asked for, once, when it exists.
    private func openDeepLinkedGroupIfNeeded() {
        guard let gid = router.deepLinkCommunityGroupId else { return }
        router.deepLinkCommunityGroupId = nil
        if let group = service.groups.first(where: { $0.id == gid }) {
            path = [group]
        }
    }

    /// Group members resolved back to FamilyMembers (for real avatars).
    private func resolvedMembers(of group: ChatGroup) -> [FamilyMember] {
        service.members(for: group).compactMap { gm in
            members.first { $0.id.uuidString == gm.memberId }
        }
    }

    private var newGroupButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .glassRoundedRect(AppRadius.lg)
                Text("Grup nou").font(AppFont.headline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .padding(.horizontal, AppSpacing.lg)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.3.sequence.fill",
            title: "Organizează grupuri",
            message: "Creează grupuri separate pentru muncitori, familie sau orice altă echipă."
        )
    }
}

// Community group thread. A thin wrapper that reuses the full, polished
// iMessage-style `ChatView` — scoped to this group via its OWN group-scoped
// `MessageService` injected through the environment — so a group conversation
// has full feature/visual parity with the main property chat (attachments,
// voice, reactions, reply, long-press menu, outbox, jump-to-latest, themes)
// without duplicating any of it. Everything arrives as plain params — no
// @EnvironmentObject — so it can't crash on a missing ancestor when pushed
// from the Communities sheet.
private struct GroupChatView: View {
    let group: ChatGroup
    let propertyId: UUID?
    let myName: String
    let members: [FamilyMember]
    /// Passed by reference from CommunitiesView (not @EnvironmentObject) so this
    /// view stays crash-safe while still sharing live group/member state.
    /// A rename in the settings sheet updates the title live.
    var service: ChatGroupService

    @Environment(\.dismiss) private var dismiss
    /// Group-scoped message service — loaded with this group's id so it never
    /// collides with the main chat. Injected into ChatView via `.environment`.
    @State private var svc = MessageService()
    @State private var showSettings = false

    private var currentGroup: ChatGroup { service.groups.first(where: { $0.id == group.id }) ?? group }

    var body: some View {
        ChatView(
            groupId: group.id,
            groupTitle: currentGroup.name.isEmpty ? currentGroup.kindLabel : currentGroup.name,
            groupSettingsAction: { showSettings = true }
        )
        .environment(svc)                    // ChatView now uses the GROUP-scoped MessageService
        .task { svc.myName = myName }        // keep sender name in sync for typing indicator
        .sheet(isPresented: $showSettings) {
            GroupSettingsSheet(group: currentGroup, service: service, availableMembers: members) { dismiss() }
        }
        .onDisappear {
            let messageSvc = svc
            let groupSvc = service
            let pid = propertyId
            Task {
                // ChatView.onDisappear deliberately leaves the main messages
                // channel alive (ConversationsView owns it for the main chat).
                // Here the channel belongs to THIS group's throwaway service, so
                // tear it down explicitly to avoid leaking a realtime subscription.
                await messageSvc.unsubscribeAll()
                // The list behind us shows each group's newest message — refresh
                // it so the row reflects this conversation.
                if let pid { await groupSvc.loadPreviews(propertyId: pid) }
            }
        }
    }
}

private struct CommunityRow: View {
    let group: ChatGroup
    let memberCount: Int
    /// Newest message ("Ana: vin mâine") + its timestamp, when the group has one.
    let preview: (text: String, date: Date?)?
    /// Members resolved to FamilyMembers, for the overlapping avatar stack.
    let avatarMembers: [FamilyMember]

    private var fallbackLine: String {
        "\(group.kindLabel) · " + String(format: String(localized: "comm_member_count"), memberCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: group.kindIcon)
                .font(AppFont.scaled(20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(group.kindTint)
                .frame(width: 48, height: 48)
                .glassCircle()

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name.isEmpty ? group.kindLabel : group.name)
                    .font(AppFont.headline).foregroundStyle(.primary)
                    .lineLimit(1)
                Text(preview?.text.isEmpty == false ? preview!.text : fallbackLine)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: 5) {
                if let date = preview?.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineLimit(1)
                }
                if !avatarMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(avatarMembers.prefix(3)) { m in
                            MemberAvatar(member: m, size: 20)
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.2))
                        }
                        if avatarMembers.count > 3 {
                            Text(verbatim: "+\(avatarMembers.count - 3)")
                                .font(AppFont.scaled(9, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.primary.opacity(0.08)))
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.2))
                        }
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityElement(children: .combine)
    }
}

// Group management: rename, add/remove members, contractors roster, delete.
private struct GroupSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContractorService.self) private var contractorService
    let group: ChatGroup
    var service: ChatGroupService
    let availableMembers: [FamilyMember]
    /// Called after the group is deleted, so the presenting chat screen pops.
    let onDeleted: () -> Void

    @State private var name: String
    @State private var showAddMembers = false
    @State private var showAddContractors = false
    @State private var showDeleteConfirm = false

    init(group: ChatGroup, service: ChatGroupService, availableMembers: [FamilyMember],
         onDeleted: @escaping () -> Void) {
        self.group = group
        self.service = service
        self.availableMembers = availableMembers
        self.onDeleted = onDeleted
        _name = State(initialValue: group.name)
    }

    private var currentGroup: ChatGroup { service.groups.first(where: { $0.id == group.id }) ?? group }
    private var currentMembers: [ChatGroupMember] { service.members(for: group) }
    /// Management (rename / members / delete) belongs to the creator only;
    /// everyone else gets a read-only view plus their own notification prefs.
    private var isAdmin: Bool {
        currentGroup.isAdmin(userId: supabase.auth.currentSession?.user.id)
    }
    /// Family members not already in this group, for the "add" picker.
    private var addableMembers: [FamilyMember] {
        let existingIds = Set(currentMembers.map { $0.memberId })
        return availableMembers.filter { !existingIds.contains($0.id.uuidString) }
    }

    // MARK: Contractors roster (contact list, honestly labeled)

    private var currentExternals: [ChatGroupMember] { service.externals(for: group) }
    private var addableContractors: [ContractorModel] {
        let attached = Set(currentExternals.map { $0.memberId })
        return contractorService.contractors.filter {
            !attached.contains(ChatGroupService.externalPrefix + $0.id.uuidString)
        }
    }

    private func contractor(for member: ChatGroupMember) -> ContractorModel? {
        let raw = String(member.memberId.dropFirst(ChatGroupService.externalPrefix.count))
        guard let id = UUID(uuidString: raw) else { return nil }
        return contractorService.contractors.first { $0.id == id }
    }

    @ViewBuilder private var contractorsSection: some View {
        if !currentExternals.isEmpty || (isAdmin && !addableContractors.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("comm_externals").font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                    if isAdmin {
                        Button { showAddContractors = true } label: {
                            Label("Adaugă", systemImage: "person.badge.plus")
                                .font(AppFont.captionEmphasis)
                        }
                        .disabled(addableContractors.isEmpty)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(currentExternals) { m in
                        externalRow(m)
                    }
                }

                if !currentExternals.isEmpty {
                    Text("comm_externals_note")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
            }
        }
    }

    private func externalRow(_ m: ChatGroupMember) -> some View {
        let model = contractor(for: m)
        return HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(AppFont.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .glassCircle()
            VStack(alignment: .leading, spacing: 1) {
                Text(m.memberName).font(AppFont.body)
                if let category = model?.category, !category.isEmpty {
                    Text(category).font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
            }
            Spacer()
            if let phone = model?.phone, !phone.isEmpty {
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                Button {
                    if let url = URL(string: "tel://\(digits)") { UIApplication.shared.open(url) }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.brandSuccess)
                        .frame(width: 32, height: 32)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Sună"))
            }
            if isAdmin {
                Button {
                    Task { await service.removeMember(m, from: group) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(format: String(localized: "Remove %@"), m.memberName)))
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.sm)
        .liquidGlass(cornerRadius: 14)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if isAdmin {
                        HStack(spacing: 10) {
                            TextField("Nume grup", text: $name)
                                .font(AppFont.scaled(16))
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                                .liquidGlass(cornerRadius: 14)
                            Button("Salvează") {
                                Task { await service.rename(group, to: name) }
                            }
                            .font(AppFont.footnoteEmphasis)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                      || name == group.name)
                        }
                    }

                    // Every member controls their own alerts for this group —
                    // mute + tones keyed by the group id, the same key the
                    // incoming-message sound and disappearing timer use.
                    SettingsGroup(title: "Notificări") {
                        NavSettingsRow(icon: "bell.fill", color: .red, label: "Notificări chat") {
                            ConversationNotificationsView(
                                convId: group.id.uuidString,
                                subtitle: currentGroup.name.isEmpty ? currentGroup.kindLabel
                                                                    : currentGroup.name)
                        }
                    }

                    HStack {
                        Text("Membri").font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                        if isAdmin {
                            Button { showAddMembers = true } label: {
                                Label("Adaugă", systemImage: "person.badge.plus")
                                    .font(AppFont.captionEmphasis)
                            }
                            .disabled(addableMembers.isEmpty)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(currentMembers) { m in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                                    Text(String(m.memberName.prefix(1)).uppercased())
                                        .font(AppFont.headline).foregroundStyle(Color.accentColor)
                                }
                                Text(m.memberName).font(AppFont.body)
                                Spacer()
                                if m.role == "admin" {
                                    Text("Admin").font(AppFont.captionStrong)
                                        .foregroundStyle(Color.accentColor)
                                } else if isAdmin {
                                    Button {
                                        Task { await service.removeMember(m, from: group) }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red.opacity(0.85))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(m.memberName)")
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.sm)
                            .liquidGlass(cornerRadius: 14)
                        }
                    }

                    contractorsSection

                    if isAdmin {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Șterge grupul", systemImage: "trash")
                                .font(AppFont.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(currentGroup.name.isEmpty ? currentGroup.kindLabel : currentGroup.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gata") { dismiss() } } }
            .sheet(isPresented: $showAddMembers) {
                AddGroupMembersSheet(members: addableMembers) { selected in
                    showAddMembers = false
                    Task { await service.addMembers(selected, to: group) }
                }
            }
            .sheet(isPresented: $showAddContractors) {
                AddContractorsSheet(contractors: addableContractors) { selected in
                    showAddContractors = false
                    Task { await service.addContractors(selected, to: group) }
                }
            }
            .task { await contractorService.load() }
            .confirmationDialog("Ștergi acest grup?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Șterge grupul", role: .destructive) {
                    Task {
                        await service.delete(group)
                        dismiss()
                        onDeleted()
                    }
                }
                Button("Anulează", role: .cancel) {}
            } message: {
                Text("Mesajele acestui grup vor fi șterse definitiv.")
            }
        }
    }
}

private struct AddGroupMembersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [FamilyMember]
    let onAdd: ([FamilyMember]) -> Void

    @State private var selectedIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(members) { m in
                        Button {
                            if selectedIds.contains(m.id) { selectedIds.remove(m.id) }
                            else { selectedIds.insert(m.id) }
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatar(member: m, size: 32)
                                Text(m.name).font(AppFont.body).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selectedIds.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                    .font(AppFont.scaled(20))
                                    .foregroundStyle(selectedIds.contains(m.id) ? Color.accentColor : Color.primary.opacity(0.25))
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                            .liquidGlass(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Adaugă membri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulează") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adaugă") { onAdd(members.filter { selectedIds.contains($0.id) }) }
                        .disabled(selectedIds.isEmpty)
                }
            }
        }
    }
}

/// Attach contractors to a group's roster (they don't receive messages —
/// the picker says so, honestly).
private struct AddContractorsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contractors: [ContractorModel]
    let onAdd: ([ContractorModel]) -> Void

    @State private var selectedIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("comm_externals_note")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .padding(.bottom, AppSpacing.xs)
                    ForEach(contractors) { c in
                        Button {
                            if selectedIds.contains(c.id) { selectedIds.remove(c.id) }
                            else { selectedIds.insert(c.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(AppFont.caption)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.orange)
                                    .frame(width: 34, height: 34)
                                    .glassCircle()
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name).font(AppFont.body).foregroundStyle(.primary)
                                    if !c.category.isEmpty {
                                        Text(c.category).font(AppFont.scaled(12))
                                            .foregroundStyle(Color.primary.opacity(0.45))
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedIds.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                    .font(AppFont.scaled(20))
                                    .foregroundStyle(selectedIds.contains(c.id) ? Color.accentColor : Color.primary.opacity(0.25))
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                            .liquidGlass(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(Text("comm_add_contractors"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulează") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adaugă") { onAdd(contractors.filter { selectedIds.contains($0.id) }) }
                        .disabled(selectedIds.isEmpty)
                }
            }
        }
    }
}

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [FamilyMember]
    let onCreate: (String, [FamilyMember]) -> Void

    @State private var name = ""
    @State private var selectedIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Nume grup", text: $name)
                        .font(AppFont.scaled(16))
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                        .liquidGlass(cornerRadius: 14)

                    Text("Membri").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    VStack(spacing: 8) {
                        ForEach(members) { m in
                            Button {
                                if selectedIds.contains(m.id) { selectedIds.remove(m.id) }
                                else { selectedIds.insert(m.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    MemberAvatar(member: m, size: 32)
                                    Text(m.name).font(AppFont.body).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedIds.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                        .font(AppFont.scaled(20))
                                        .foregroundStyle(selectedIds.contains(m.id) ? Color.accentColor : Color.primary.opacity(0.25))
                                }
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                                .liquidGlass(cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Grup nou")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulează") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Creează") {
                        let selected = members.filter { selectedIds.contains($0.id) }
                        onCreate(name.trimmingCharacters(in: .whitespaces), selected)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

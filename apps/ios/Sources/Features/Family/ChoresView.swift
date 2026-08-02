import SwiftUI

// MARK: - Chores & allowance — entry card, page, add/edit sheet
//
// "Corvezi & alocație": the family's reward chart. Chores are small paid jobs;
// completions flow log → approve → payout, and the approved-but-unpaid rows
// are each child's live balance. Paying out writes a real expense (tag
// "allowance") into the ledger, so pocket money is never invisible money.

// MARK: Entry card (embedded on FamilyView)

struct ChoresEntryCard: View {
    var body: some View {
        NavigationLink { ChoresView() } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "star.circle.fill")
                    .font(AppFont.scaled(24, weight: .semibold))
                    .foregroundStyle(Color.brandWarning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("chores_title")
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("chores_entry_caption")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(Color.secondaryTextColor)
            }
            .padding(AppSpacing.lg)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Full page

struct ChoresView: View {
    @Environment(ChoreService.self) private var service
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false
    @State private var editing: Chore?
    @State private var payoutTarget: ChoreBalance?
    @State private var isPaying = false

    private var canApprove: Bool { propertyService.canApproveChores }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if !service.balances.isEmpty {
                    balancesSection
                }
                if canApprove && !service.pending.isEmpty {
                    pendingSection
                }
                choresSection
                if !service.recentHistory.isEmpty {
                    historySection
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("chores_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canApprove {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(Color.glassInk)
                    }
                    .accessibilityLabel(Text("chore_add"))
                }
            }
        }
        .sheet(isPresented: $showAdd) { ChoreFormSheet() }
        .sheet(item: $editing) { ChoreFormSheet(editing: $0) }
        .confirmationDialog("chore_payout", isPresented: Binding(
            get: { payoutTarget != nil },
            set: { if !$0 { payoutTarget = nil } }
        ), titleVisibility: .visible) {
            if let target = payoutTarget {
                Button {
                    pay(target)
                } label: {
                    Text(String(format: String(localized: "chore_payout_confirm_fmt"),
                                target.memberName))
                }
            }
        }
        .task { await service.loadIfNeeded() }
        .refreshable { await service.load() }
    }

    // MARK: Balances

    private var balancesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("chore_balances_title")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(.primary)
            VStack(spacing: 0) {
                ForEach(service.balances) { balance in
                    balanceRow(balance)
                    if balance.id != service.balances.last?.id {
                        FormDivider()
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private func balanceRow(_ balance: ChoreBalance) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle().fill(Color.brandWarning.opacity(AppOpacity.tintedFill))
                Text(verbatim: String(balance.memberName.prefix(1)).uppercased())
                    .font(AppFont.scaled(15, weight: .bold))
                    .foregroundStyle(Color.brandWarning)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: balance.memberName)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(String(format: String(localized: "chore_balance_count_fmt"), balance.count))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(balance.totals, id: \.currency) { total in
                    Text(verbatim: CurrencyService.money(total.amount, code: total.currency))
                        .font(AppFont.scaled(15, weight: .bold))
                        .foregroundStyle(Color.brandSuccess)
                }
            }
            if canApprove {
                Button {
                    payoutTarget = balance
                    HapticFeedback.impact(.medium)
                } label: {
                    Text("chore_payout")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isPaying)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: Pending approvals

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("chore_pending_title")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(.primary)
            VStack(spacing: 0) {
                ForEach(service.pending) { completion in
                    pendingRow(completion)
                    if completion.id != service.pending.last?.id {
                        FormDivider()
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private func pendingRow(_ completion: ChoreCompletion) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: service.chore(for: completion)?.iconName ?? "sparkles")
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(Color.brandWarning)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: service.chore(for: completion)?.title ?? "—")
                    .font(AppFont.scaled(14, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                Text(verbatim: [completion.memberName,
                                completion.date?.formatted(date: .abbreviated, time: .omitted)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
            }
            Spacer()
            Text(verbatim: CurrencyService.money(completion.reward, code: completion.currency))
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(Color.secondaryTextColor)
            Button {
                HapticFeedback.success()
                Task { try? await service.approve(completion) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(26))
                    .foregroundStyle(Color.brandSuccess)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("chore_approve"))
            Button {
                HapticFeedback.warning()
                Task { await service.reject(completion) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(26))
                    .foregroundStyle(Color.brandDanger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("chore_reject"))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: Chores

    private var choresSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if service.activeChores.isEmpty {
                if canApprove {
                    EmptyStateView(icon: "star.circle.fill",
                                   title: "chores_empty_title",
                                   message: "chores_empty_message",
                                   actionLabel: "chore_add") { showAdd = true }
                        .padding(.top, AppSpacing.xxl)
                } else {
                    EmptyStateView(icon: "star.circle.fill",
                                   title: "chores_empty_title",
                                   message: "chores_empty_message")
                        .padding(.top, AppSpacing.xxl)
                }
            } else {
                Text("chores_section_active")
                    .font(AppFont.scaled(20, weight: .bold))
                    .foregroundStyle(.primary)
                ForEach(service.activeChores) { chore in
                    ChoreCard(chore: chore,
                              lastDone: service.lastCompletion(for: chore.id),
                              canManage: canApprove,
                              onDone: { Task { try? await service.logCompletion(for: chore) } },
                              onEdit: { editing = chore },
                              onDelete: { Task { await service.delete(chore) } })
                }
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("chore_history_title")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(.primary)
            VStack(spacing: 0) {
                ForEach(service.recentHistory.prefix(10)) { completion in
                    historyRow(completion)
                    if completion.id != service.recentHistory.prefix(10).last?.id {
                        FormDivider()
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private func historyRow(_ completion: ChoreCompletion) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: completion.isPaid ? "banknote.fill" : "checkmark.seal.fill")
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(completion.isPaid ? Color.brandSuccess : Color.brandPrimaryBlue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: service.chore(for: completion)?.title ?? "—")
                    .font(AppFont.scaled(14, weight: .medium))
                    .foregroundStyle(.primary).lineLimit(1)
                Text(verbatim: [completion.memberName,
                                completion.date?.formatted(date: .abbreviated, time: .omitted)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
            }
            Spacer()
            Text(verbatim: CurrencyService.money(completion.reward, code: completion.currency))
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(completion.isPaid ? Color.secondaryTextColor : Color.brandSuccess)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    private func pay(_ balance: ChoreBalance) {
        isPaying = true
        Task {
            defer { isPaying = false }
            do {
                try await service.payout(balance, into: financialService)
                HapticFeedback.success()
            } catch {
                service.error = error.recordableDescription
            }
        }
    }
}

// MARK: Chore card

private struct ChoreCard: View {
    let chore: Chore
    let lastDone: ChoreCompletion?
    let canManage: Bool
    let onDone: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle().fill(Color.brandWarning.opacity(AppOpacity.tintedFill))
                Image(systemName: chore.iconName)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(Color.brandWarning)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: chore.title)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: AppSpacing.xs) {
                    if let who = chore.assignedMemberName {
                        Text(verbatim: who)
                    } else {
                        Text("chore_assignee_anyone")
                    }
                    Text(verbatim: "·")
                    Text(chore.recurrenceKind.label)
                }
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.secondaryTextColor)
                if let last = lastDone, let d = last.date {
                    Text(String(format: String(localized: "chore_last_done_fmt"),
                                d.formatted(date: .abbreviated, time: .omitted)))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text(verbatim: CurrencyService.money(chore.reward, code: chore.currency))
                    .font(AppFont.scaled(15, weight: .bold))
                    .foregroundStyle(Color.brandSuccess)
                Button {
                    HapticFeedback.success()
                    onDone()
                } label: {
                    Text("chore_mark_done")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .contextMenu {
            if canManage {
                Button { onEdit() } label: {
                    Label("chore_edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    HapticFeedback.warning()
                    onDelete()
                } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }
}

// MARK: Add / edit sheet

struct ChoreFormSheet: View {
    @Environment(ChoreService.self) private var service
    @Environment(FamilyService.self) private var familyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    var editing: Chore?

    @State private var title = ""
    @State private var icon = "sparkles"
    @State private var reward = ""
    @State private var assigneeId: String?
    @State private var recurrence: ChoreRecurrence = .weekly
    @State private var active = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var hydrated = false

    private static let icons = [
        "sparkles", "trash.fill", "fork.knife", "bed.double.fill",
        "pawprint.fill", "leaf.fill", "washer.fill", "dishwasher.fill",
        "book.fill", "backpack.fill", "cart.fill", "shower.fill",
        "car.fill", "paintbrush.fill", "sun.max.fill", "gamecontroller.fill"
    ]

    /// The family core, kids first — the natural assignees of a reward chart.
    private var assignees: [FamilyMember] {
        let familyRoles: Set<String> = ["owner", "partner", "member", "teen", "child"]
        let kids: Set<String> = ["child", "teen"]
        return familyService.members.filter { familyRoles.contains($0.role) }
            .sorted { (kids.contains($0.role) ? 0 : 1, $0.name) < (kids.contains($1.role) ? 0 : 1, $1.name) }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(reward.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        FormScaffold(title: editing == nil ? "chore_add" : "chore_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: icon, tint: .brandWarning) {
                    TextField("chore_title_ph", text: $title).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "eurosign.circle.fill", tint: .brandWarning) {
                    Text("chore_reward").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $reward).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppFont.scaled(18, weight: .semibold))
                    Text(verbatim: editing?.currency ?? appSettings.preferredCurrency)
                        .foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                FormRow(icon: "person.fill", tint: .brandWarning) {
                    Picker("chore_assignee", selection: $assigneeId) {
                        Text("chore_assignee_anyone").tag(String?.none)
                        ForEach(assignees) { member in
                            Text(verbatim: member.name).tag(String?.some(member.id.uuidString))
                        }
                    }
                    .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "repeat", tint: .brandWarning) {
                    Picker("chore_recurrence", selection: $recurrence) {
                        ForEach(ChoreRecurrence.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .font(AppFont.body)
                }
                if editing != nil {
                    FormDivider()
                    FormRow(icon: "power", tint: .brandWarning) {
                        Toggle("chore_active", isOn: $active).font(AppFont.body)
                    }
                }
            }

            FormGroup(title: "chore_icon_title") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8),
                          spacing: AppSpacing.sm) {
                    ForEach(Self.icons, id: \.self) { symbol in
                        Button {
                            icon = symbol
                            HapticFeedback.selection()
                        } label: {
                            Image(systemName: symbol)
                                .font(AppFont.scaled(15, weight: .semibold))
                                .foregroundStyle(icon == symbol ? Color.white : Color.brandWarning)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(icon == symbol
                                        ? Color.brandWarning
                                        : Color.brandWarning.opacity(AppOpacity.tintedFill)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.md)
            }
        }
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard let chore = editing, !hydrated else { return }
        hydrated = true
        title = chore.title
        icon = chore.iconName
        reward = chore.reward == chore.reward.rounded()
            ? String(Int(chore.reward)) : String(chore.reward)
        assigneeId = chore.assignedMemberId
        recurrence = chore.recurrenceKind
        active = chore.active
    }

    private func save() {
        guard let amount = Double(reward.replacingOccurrences(of: ",", with: ".")) else { return }
        let assignee = assignees.first { $0.id.uuidString == assigneeId }
        let payload = ChoreService.ChorePayload(
            title: title.trimmingCharacters(in: .whitespaces),
            icon: icon,
            reward: amount,
            currency: editing?.currency ?? appSettings.preferredCurrency,
            assignedMemberId: assignee?.id.uuidString,
            assignedMemberName: assignee?.name,
            recurrence: recurrence.rawValue,
            active: active)
        isSaving = true
        Task {
            do {
                if let chore = editing {
                    try await service.update(chore.id, payload: payload)
                } else {
                    try await service.add(payload)
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}

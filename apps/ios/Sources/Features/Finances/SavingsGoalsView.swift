import SwiftUI

// MARK: - Savings goals — section, full list, detail, and the two sheets
//
// "Obiective comune": shared family savings targets with per-member manual
// deposits. The section rides on the Finances page (top goals + See all); the
// full page owns the one-circle add trigger; the detail shows the ledger and
// the per-member breakdown.

// MARK: Section (embedded on FinancesView)

struct SavingsGoalsSection: View {
    @Environment(SavingsGoalService.self) private var service

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Naked header (headers-no-borders law) with a See-all affordance.
            NavigationLink { SavingsGoalsView() } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("goal_section_title")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    if !service.goals.isEmpty {
                        Text(verbatim: "\(service.goals.count)")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            if service.goals.isEmpty {
                NavigationLink { SavingsGoalsView() } label: {
                    EmptyStateView(icon: "target",
                                   title: "goal_empty_title",
                                   message: "goal_empty_message")
                }
                .buttonStyle(.plain)
            } else {
                // Top 2 goals inline; the rest live on the full page.
                ForEach(service.goals.prefix(2)) { goal in
                    NavigationLink { SavingsGoalDetailView(goal: goal) } label: {
                        SavingsGoalCard(progress: service.progress(for: goal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: Full list page (one-circle add)

struct SavingsGoalsView: View {
    @Environment(SavingsGoalService.self) private var service
    @State private var showAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                if service.goals.isEmpty {
                    EmptyStateView(icon: "target",
                                   title: "goal_empty_title",
                                   message: "goal_empty_message",
                                   actionLabel: "goal_add") { showAdd = true }
                        .padding(.top, AppSpacing.xxl)
                } else {
                    ForEach(service.goals) { goal in
                        NavigationLink { SavingsGoalDetailView(goal: goal) } label: {
                            SavingsGoalCard(progress: service.progress(for: goal))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("goal_section_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text("goal_add"))
            }
        }
        .sheet(isPresented: $showAdd) { AddSavingsGoalSheet() }
        .task { await service.load() }
    }
}

// MARK: Detail — ledger + per-member breakdown

struct SavingsGoalDetailView: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal

    @State private var showContribute = false
    @State private var showDeleteConfirm = false

    /// Re-resolve from the service so realtime updates repaint the detail.
    private var live: SavingsGoal { service.goals.first { $0.id == goal.id } ?? goal }
    private var progress: SavingsGoalProgress { service.progress(for: live) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                SavingsGoalCard(progress: progress)

                Button { showContribute = true; HapticFeedback.impact(.medium) } label: {
                    Label("goal_add_deposit", systemImage: "plus.circle.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.base)
                        .background(live.tint.opacity(AppOpacity.tintedFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.lg))
                        .foregroundStyle(live.tint)
                }
                .buttonStyle(.plain)

                if !progress.byMember.isEmpty { memberBreakdown }
                contributionHistory
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text(verbatim: live.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("goal_delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(AppFont.scaled(17, weight: .semibold)).foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showContribute) { AddContributionSheet(goal: live) }
        .confirmationDialog("goal_delete_confirm", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("goal_delete", role: .destructive) {
                Task { await service.deleteGoal(live); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var memberBreakdown: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("goal_by_member").font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
            ForEach(progress.byMember, id: \.name) { row in
                HStack {
                    Text(verbatim: row.name).font(AppFont.scaled(14)).foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: CurrencyService.money(row.amount, code: live.currency, whole: true))
                        .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private var contributionHistory: some View {
        let items = service.contributions(for: live.id)
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("goal_history").font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
            if items.isEmpty {
                Text("goal_history_empty").font(AppFont.scaled(13)).foregroundStyle(Color.secondaryTextColor)
            } else {
                ForEach(items) { c in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: c.memberName ?? "—").font(AppFont.scaled(14)).foregroundStyle(.primary)
                            if let d = c.date {
                                Text(verbatim: AppDate.monthDay.string(from: d))
                                    .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                            }
                            if let note = c.note, !note.isEmpty {
                                Text(verbatim: note).font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                            }
                        }
                        Spacer()
                        Text(verbatim: CurrencyService.money(c.amount, code: live.currency, whole: true))
                            .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await service.deleteContribution(c) }
                        } label: { Label("goal_delete_deposit", systemImage: "trash") }
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }
}

// MARK: Add goal sheet

struct AddSavingsGoalSheet: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var target = ""
    @State private var monthly = ""
    @State private var icon = "target"
    @State private var colorToken = "brandPurple"
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var isSaving = false
    @State private var error: String?

    private let icons = ["target", "house.fill", "shield.fill", "airplane", "car.fill",
                         "gift.fill", "graduationcap.fill", "heart.fill", "banknote.fill"]
    private let colors = ["brandPurple", "brandSuccess", "brandPrimaryBlue", "brandSkyBlue",
                          "brandWarning", "brandDanger"]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (Double(target) ?? 0) > 0
    }

    var body: some View {
        FormScaffold(title: "goal_new", canSave: canSave, isSaving: isSaving,
                     error: $error, onSave: save) {
            FormGroup {
                TextField("goal_title_placeholder", text: $title)
                    .font(AppFont.body)
                FormDivider()
                HStack {
                    Text("goal_target").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $target).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.body)
                    Text(verbatim: appSettings.preferredCurrency).foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                HStack {
                    Text("goal_monthly_per_member").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $monthly).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.body)
                    Text(verbatim: appSettings.preferredCurrency).foregroundStyle(Color.secondaryTextColor)
                }
            }

            FormGroup(title: "goal_icon") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(icons, id: \.self) { name in
                            Button { icon = name; HapticFeedback.selection() } label: {
                                Image(systemName: name)
                                    .font(AppFont.scaled(18, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(icon == name ? tint(colorToken).opacity(AppOpacity.tintedFill)
                                                             : Color.primary.opacity(AppOpacity.subtleFill),
                                                in: RoundedRectangle(cornerRadius: AppRadius.md))
                                    .foregroundStyle(icon == name ? tint(colorToken) : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            FormGroup(title: "goal_color") {
                HStack(spacing: AppSpacing.md) {
                    ForEach(colors, id: \.self) { token in
                        Button { colorToken = token; HapticFeedback.selection() } label: {
                            ZStack {
                                Circle().fill(tint(token)).frame(width: 34, height: 34)
                                if colorToken == token {
                                    Image(systemName: "checkmark")
                                        .font(AppFont.captionStrong).foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            FormGroup {
                Toggle("goal_deadline", isOn: $hasDeadline.animation(.snappy)).font(AppFont.body)
                if hasDeadline {
                    FormDivider()
                    DatePicker("goal_deadline_date", selection: $deadline, displayedComponents: .date)
                        .font(AppFont.body)
                }
            }
        }
    }

    private func tint(_ token: String) -> Color { SavingsGoal.tint(forToken: token) }

    private func save() {
        guard let pid = propertyService.primary?.id else {
            error = String(localized: "No property found. Please set up your property first."); return
        }
        isSaving = true
        Task {
            do {
                try await service.addGoal(SavingsGoalService.NewGoal(
                    propertyId: pid.uuidString,
                    title: title.trimmingCharacters(in: .whitespaces),
                    icon: icon,
                    color: colorToken,
                    targetAmount: Double(target) ?? 0,
                    currency: appSettings.preferredCurrency,
                    monthlyPerMember: Double(monthly).flatMap { $0 > 0 ? $0 : nil },
                    deadline: hasDeadline ? AppDate.day.string(from: deadline) : nil))
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}

// MARK: Add contribution sheet

struct AddContributionSheet: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal

    @State private var amount = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { (Double(amount) ?? 0) > 0 }

    var body: some View {
        FormScaffold(title: "goal_add_deposit", saveLabel: "goal_deposit_save",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                HStack {
                    Text("goal_amount").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $amount).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.scaled(20, weight: .semibold))
                    Text(verbatim: goal.currency).foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                TextField("goal_note_placeholder", text: $note).font(AppFont.body)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await service.addContribution(to: goal, amount: Double(amount) ?? 0, note: note)
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}

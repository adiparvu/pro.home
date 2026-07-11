import SwiftUI

// MARK: - Budget Management View
//
// Living budgets: every category row edits inline (tap → amount field +
// confirm, no navigation), shows real spend from the month's receipts as
// a progress bar, and an empty month can copy last month's budgets in one
// tap. All writes go through the existing `upsertBudget`.

struct BudgetManagementView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var expandedCategory: String? = nil
    @State private var budgetInput: String = ""
    @State private var isSaving = false
    @State private var isCopying = false
    @FocusState private var amountFocused: Bool

    private var currentMonth: String { receiptService.currentMonthKey }

    private var currentBudgets: [HouseholdBudget] {
        receiptService.budgets.filter { $0.month == currentMonth && $0.monthlyLimit > 0 }
    }

    private var previousMonthBudgets: [HouseholdBudget] {
        let prev = receiptService.previousMonthKey(from: currentMonth)
        return receiptService.budgets.filter { $0.month == prev && $0.monthlyLimit > 0 }
    }

    private func money(_ amount: Double) -> String {
        CurrencyService.money(amount, code: appSettings.preferredCurrency)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        if currentBudgets.isEmpty && !previousMonthBudgets.isEmpty {
                            copyLastMonthButton
                        }
                        categoriesSection
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(String(localized: "budget_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "target").font(AppFont.scaled(18)).foregroundStyle(Color.accentColor)
                    Text(LocalizedStringKey(receiptService.monthDisplayName(currentMonth)))
                        .font(AppFont.subheadline)
                    Spacer()
                    let totalBudget = currentBudgets.reduce(0) { $0 + $1.monthlyLimit }
                    let totalSpent = receiptService.totalSpent(in: currentMonth)
                    if totalBudget > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: "\(money(totalSpent)) / \(money(totalBudget))")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(totalSpent > totalBudget ? Color.brandDanger : .primary)
                            Text(String(localized: "budget_total_label"))
                                .font(AppFont.scaled(10)).foregroundStyle(.secondary)
                        }
                    }
                }

                let totalBudget = currentBudgets.reduce(0) { $0 + $1.monthlyLimit }
                if totalBudget > 0 {
                    let totalSpent = receiptService.totalSpent(in: currentMonth)
                    progressBar(spent: totalSpent, limit: totalBudget, height: 8)
                }

                Text(String(localized: "budget_description"))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Copy last month
    //
    // Offered only when the current month has no budgets AND last month
    // has some — never a dead control.

    private var copyLastMonthButton: some View {
        GlassWideButton(icon: "doc.on.doc",
                        label: "budget_copy_last_month",
                        isBusy: isCopying) {
            Task { await copyLastMonth() }
        }
    }

    private func copyLastMonth() async {
        guard let propId = propertyService.primary?.id else { return }
        isCopying = true
        defer { isCopying = false }
        for budget in previousMonthBudgets {
            await receiptService.upsertBudget(propertyId: propId,
                                              category: budget.category,
                                              monthlyLimit: budget.monthlyLimit)
        }
        HapticFeedback.success()
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "budget_categories_section"))
                .font(AppFont.captionStrong).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(ReceiptCategory.all.enumerated()), id: \.element.id) { idx, cat in
                        categoryRow(category: cat.id, label: cat.label, isLast: idx == ReceiptCategory.all.count - 1)
                    }
                }
            }
        }
    }

    private func categoryRow(category: String, label: String, isLast: Bool) -> some View {
        let budget = receiptService.budget(for: category, month: currentMonth)
        let limit = budget?.monthlyLimit ?? 0
        let spent = receiptService.spent(for: category, in: currentMonth)
        let isOver = limit > 0 && spent > limit
        let isExpanded = expandedCategory == category

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Clear Liquid Glass badge — colour lives on the glyph only,
                // never on a filled tile (the app-wide icon language).
                Image(systemName: ReceiptCategory.icon(for: category))
                    .font(AppFont.footnoteEmphasis)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ReceiptCategory.color(for: category))
                    .frame(width: 36, height: 36)
                    .mediaGlass(in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(label)).font(AppFont.footnote).foregroundStyle(.primary)
                    if limit > 0 {
                        let pct = min(spent / limit * 100, 999)
                        Text(verbatim: "\(money(spent)) / \(money(limit)) · \(Int(pct))%")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(isOver ? Color.brandDanger : .secondary)
                        progressBar(spent: spent, limit: limit, height: 5)
                    } else if spent > 0 {
                        Text(String(format: String(localized: "budget_spent_no_limit"), money(spent)))
                            .font(AppFont.scaled(11)).foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "budget_no_budget_set"))
                            .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.3))
                    }
                }

                Spacer()

                if isOver {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFont.scaled(13)).foregroundStyle(Color.brandDanger)
                }

                Image(systemName: "chevron.down")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
            .onTapGesture { toggleEditor(for: category, existing: budget) }

            if isExpanded {
                inlineEditor(category: category, existing: budget)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
            }
        }
    }

    // MARK: - Inline quick-set editor

    private func toggleEditor(for category: String, existing: HouseholdBudget?) {
        HapticFeedback.selection()
        withAnimation(.snappy(duration: 0.25)) {
            if expandedCategory == category {
                expandedCategory = nil
                amountFocused = false
            } else {
                budgetInput = (existing?.monthlyLimit).map {
                    $0 > 0 ? String(format: "%.2f", $0) : ""
                } ?? ""
                expandedCategory = category
                amountFocused = true
            }
        }
    }

    private func inlineEditor(category: String, existing: HouseholdBudget?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField("0.00", text: $budgetInput)
                        .font(AppFont.scaled(17, weight: .semibold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .focused($amountFocused)
                        .submitLabel(.done)
                    Text(verbatim: appSettings.preferredCurrency)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.sm)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                GlassProminentIconButton(systemImage: "checkmark",
                                         isEnabled: parsedInput != nil,
                                         isBusy: isSaving,
                                         accessibilityLabel: "budget_save") {
                    Task { await saveBudget(category: category) }
                }
            }

            if let existing, existing.monthlyLimit > 0 {
                Button(role: .destructive) {
                    Task {
                        await receiptService.deleteBudget(existing)
                        withAnimation(.snappy(duration: 0.25)) { expandedCategory = nil }
                        HapticFeedback.selection()
                    }
                } label: {
                    Text(String(localized: "budget_remove"))
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.brandDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.bottom, AppSpacing.md)
    }

    private var parsedInput: Double? {
        let normalized = budgetInput.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private func saveBudget(category: String) async {
        guard let propId = propertyService.primary?.id, let limit = parsedInput else { return }
        isSaving = true
        defer { isSaving = false }
        await receiptService.upsertBudget(propertyId: propId, category: category, monthlyLimit: limit)
        HapticFeedback.success()
        withAnimation(.snappy(duration: 0.25)) {
            expandedCategory = nil
            budgetInput = ""
        }
    }

    // MARK: - Progress bar
    //
    // One visual language for budget health: accent while comfortable,
    // brandWarning past 80%, brandDanger past the limit.

    private func progressBar(spent: Double, limit: Double, height: CGFloat) -> some View {
        let ratio = limit > 0 ? spent / limit : 0
        let fill: Color = ratio > 1.0 ? .brandDanger
                        : ratio > 0.8 ? .brandWarning
                        : .accentColor
        // Progress bar without GeometryReader: scale a full-width fill.
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(height: height)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill)
                    .scaleEffect(x: min(ratio, 1.0), y: 1, anchor: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .animation(.snappy(duration: 0.25), value: spent)
    }
}

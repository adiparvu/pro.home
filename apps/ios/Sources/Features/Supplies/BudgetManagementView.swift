import SwiftUI

// MARK: - Budget Management View

struct BudgetManagementView: View {
    @EnvironmentObject private var receiptService: ReceiptService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var editingCategoryItem: BudgetCategoryItem? = nil
    @State private var budgetInput: String = ""
    @State private var isSaving = false

    private var currentMonth: String { receiptService.currentMonthKey }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        categoriesSection
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                }
            }
            .navigationTitle(String(localized: "budget_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $editingCategoryItem) { item in
                setBudgetSheet(category: item.value)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "target").font(.system(size: 18)).foregroundStyle(.accentColor)
                    Text(receiptService.monthDisplayName(currentMonth))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    let totalBudget = receiptService.budgets.filter { $0.month == currentMonth }.reduce(0) { $0 + $1.monthlyLimit }
                    let totalSpent = receiptService.totalSpent(in: currentMonth)
                    if totalBudget > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Receipt.format(totalSpent)) / \(Receipt.format(totalBudget))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(totalSpent > totalBudget ? .red : .primary)
                            Text(String(localized: "budget_total_label"))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }

                let totalBudget = receiptService.budgets.filter { $0.month == currentMonth }.reduce(0) { $0 + $1.monthlyLimit }
                if totalBudget > 0 {
                    let totalSpent = receiptService.totalSpent(in: currentMonth)
                    let pct = min(totalSpent / totalBudget, 1.0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.08)).frame(height: 8)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(totalSpent > totalBudget ? Color.red : Color.accentColor)
                                .frame(width: geo.size.width * pct, height: 8)
                        }
                    }
                    .frame(height: 8)
                }

                Text(String(localized: "budget_description"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "budget_categories_section"))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)

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
        let spent = receiptService.spent(for: category, in: currentMonth)
        let isOver = (budget?.monthlyLimit).map { spent > $0 && $0 > 0 } ?? false

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ReceiptCategory.color(for: category).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: ReceiptCategory.icon(for: category))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReceiptCategory.color(for: category))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                    if let budget, budget.monthlyLimit > 0 {
                        let pct = min(spent / budget.monthlyLimit * 100, 100)
                        Text("\(Receipt.format(spent)) / \(Receipt.format(budget.monthlyLimit)) · \(Int(pct))%")
                            .font(.system(size: 11))
                            .foregroundStyle(isOver ? .red : .secondary)
                    } else if spent > 0 {
                        Text(String(format: String(localized: "budget_spent_no_limit"), Receipt.format(spent)))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "budget_no_budget_set"))
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.3))
                    }
                }

                Spacer()

                if isOver {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13)).foregroundStyle(.red)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { editingCategoryItem = BudgetCategoryItem(value: category); HapticFeedback.selection() }

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
            }
        }
    }

    // MARK: - Set budget sheet

    private func setBudgetSheet(category: String) -> some View {
        let label = ReceiptCategory.label(for: category)
        let existing = receiptService.budget(for: category, month: currentMonth)

        return NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 28) {
                    // Icon + label
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(ReceiptCategory.color(for: category).opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: ReceiptCategory.icon(for: category))
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(ReceiptCategory.color(for: category))
                        }
                        Text(label)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .padding(.top, 20)

                    // Budget input
                    VStack(spacing: 8) {
                        Text(String(localized: "budget_monthly_limit"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("0.00", text: Binding(
                            get: {
                                if budgetInput.isEmpty, let b = existing {
                                    return String(format: "%.2f", b.monthlyLimit)
                                }
                                return budgetInput
                            },
                            set: { budgetInput = $0 }
                        ))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                        let spent = receiptService.spent(for: category, in: currentMonth)
                        if spent > 0 {
                            Text(String(format: String(localized: "budget_already_spent"), Receipt.format(spent)))
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            Task { await saveBudget(category: category) }
                        } label: {
                            Group {
                                if isSaving { ProgressView().tint(Color(UIColor.systemBackground)) }
                                else { Text(String(localized: "budget_save")).font(.system(size: 16, weight: .semibold)) }
                            }
                            .foregroundStyle(Color(UIColor.systemBackground))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)

                        if let budget = existing, budget.monthlyLimit > 0 {
                            Button(role: .destructive) {
                                Task {
                                    await receiptService.deleteBudget(budget)
                                    editingCategoryItem = nil
                                }
                            } label: {
                                Text(String(localized: "budget_remove"))
                                    .font(.system(size: 15))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle(String(format: String(localized: "budget_set_for"), label))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { editingCategoryItem = nil }.foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveBudget(category: String) async {
        guard let propId = propertyService.primary?.id else { return }
        let limitStr = budgetInput.replacingOccurrences(of: ",", with: ".")
        let limit = Double(limitStr) ?? 0
        isSaving = true
        defer { isSaving = false; budgetInput = "" }
        await receiptService.upsertBudget(propertyId: propId, category: category, monthlyLimit: limit)
        HapticFeedback.success()
        editingCategoryItem = nil
    }
}

// MARK: - Helper

private struct BudgetCategoryItem: Identifiable {
    let id = UUID()
    let value: String
}

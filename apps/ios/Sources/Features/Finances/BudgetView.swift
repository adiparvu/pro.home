import SwiftUI

struct BudgetView: View {
    @Environment(BudgetService.self) private var budgetService
    @Environment(FinancialService.self) private var financialService
    @State private var editingCategory: String? = nil
    @State private var editAmount = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryCard
                categoriesSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Monthly Budget")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: Binding(
            get: { editingCategory.map { IdentifiableString($0) } },
            set: { editingCategory = $0?.value }
        )) { item in
            EditBudgetSheet(
                category: item.value,
                current: budgetService.budget(for: item.value),
                currencySymbol: financialService.currencySymbol,
                onSave: { amount in
                    budgetService.setBudget(amount, for: item.value)
                    HapticFeedback.success()
                    editingCategory = nil
                }
            )
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Total Budget")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("This month")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }

                let total = budgetService.totalBudget()
                let spent = financialService.currentMonthExpenses
                let remaining = total - spent
                let progress = total > 0 ? min(spent / total, 1.0) : 0

                HStack(alignment: .bottom, spacing: 4) {
                    Text(financialService.moneyDisplay(spent))
                        .font(AppFont.scaled(32, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("/ " + financialService.moneyDisplay(total))
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .padding(.bottom, AppSpacing.xxs)
                }

                // Progress bar without GeometryReader: scale a full-width fill.
                Capsule()
                    .fill(Color.primary.opacity(AppOpacity.subtleFill))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(progress > 0.9 ? Color.red : progress > 0.7 ? Color.orange : Color.blue)
                            .scaleEffect(x: progress, y: 1, anchor: .leading)
                            .animation(.spring(response: 0.5), value: progress)
                    }
                    .clipShape(Capsule())

                HStack {
                    Label(remaining >= 0
                          ? String(format: String(localized: "%@ remaining"), financialService.moneyDisplay(abs(remaining)))
                          : String(format: String(localized: "%@ over budget"), financialService.moneyDisplay(abs(remaining))),
                          systemImage: remaining >= 0 ? "checkmark.circle" : "exclamationmark.circle")
                        .font(AppFont.caption)
                        .foregroundStyle(remaining >= 0 ? Color.brandSuccess : Color.red)
                    Spacer()
                    Text(String(format: String(localized: "%.0f%% used"), progress * 100))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Per Category")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 8) {
                ForEach(BudgetService.categories, id: \.self) { cat in
                    let budget = budgetService.budget(for: cat)
                    let spent  = spentFor(cat)
                    let progress = budgetService.spendingProgress(for: cat, spent: spent)

                    Button { editingCategory = cat; HapticFeedback.selection() } label: {
                        GlassCard(padding: 14) {
                            VStack(spacing: 10) {
                                HStack {
                                    ColoredIconBadge(icon: categoryIcon(cat), color: categoryColor(cat), size: 32)
                                    Text(LocalizedStringKey(cat.capitalized))
                                        .font(AppFont.footnote)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        if budget > 0 {
                                            Text("\(financialService.moneyDisplay(spent)) / \(financialService.moneyDisplay(budget))")
                                                .font(AppFont.captionEmphasis)
                                                .foregroundStyle(progress > 0.9 ? .red : .white)
                                        } else {
                                            Text("Set budget")
                                                .font(AppFont.scaled(12))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                        if budget > 0 {
                                            Text(String(format: "%.0f%%", progress * 100))
                                                .font(AppFont.scaled(10))
                                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                        }
                                    }
                                }

                                if budget > 0 {
                                    Capsule()
                                        .fill(Color.primary.opacity(AppOpacity.subtleFill))
                                        .frame(height: 5)
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(progress > 0.9 ? Color.red : progress > 0.7 ? Color.orange : categoryColor(cat))
                                                .scaleEffect(x: progress, y: 1, anchor: .leading)
                                                .animation(.spring(response: 0.5), value: progress)
                                        }
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func spentFor(_ category: String) -> Double {
        financialService.currentMonthRecords
            .filter { $0.type == "expense" && $0.category == category }
            .reduce(0) { $0 + $1.amount }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "rent":        return "house.fill"
        case "utilities":   return "bolt.fill"
        case "maintenance": return "wrench.fill"
        case "insurance":   return "shield.fill"
        case "taxes":       return "building.columns.fill"
        case "mortgage":    return "banknote.fill"
        case "supplies":    return "cart.fill"
        default:            return "square.grid.2x2.fill"
        }
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "rent":        return .blue
        case "utilities":   return .yellow
        case "maintenance": return .orange
        case "insurance":   return Color.brandSuccess
        case "taxes":       return .purple
        case "mortgage":    return .cyan
        case "supplies":    return .pink
        default:            return Color.primary.opacity(0.6)
        }
    }
}

// MARK: - Edit sheet

private struct EditBudgetSheet: View {
    let category: String
    let current: Double
    /// The household's real currency symbol — this sheet used to hardcode "€".
    let currencySymbol: String
    let onSave: (Double) -> Void

    @State private var amount: String = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                VStack(spacing: 24) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Monthly Budget")
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            HStack(spacing: 8) {
                                Text(verbatim: currencySymbol)
                                    .font(AppFont.scaled(32, weight: .light))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                TextField(current > 0 ? String(Int(current)) : "0", text: $amount)
                                    .font(AppFont.scaled(40, weight: .light))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                                    .keyboardType(.decimalPad)
                                    .focused($focused)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    Spacer()
                }
                .padding(.top, AppSpacing.sm)
            }
            .navigationTitle(LocalizedStringKey(category.capitalized))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let val = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? current
                        onSave(val)
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .onAppear {
            amount = current > 0 ? String(Int(current)) : ""
            focused = true
        }
    }
}

// MARK: - Helpers

private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
    init(_ value: String) { self.value = value }
}

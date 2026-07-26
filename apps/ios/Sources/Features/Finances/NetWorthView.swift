import SwiftUI

// MARK: - Net worth — section, full page, and the add/edit sheet
//
// "Avere netă gospodărie": one honest number for what the household owns minus
// what it owes. It folds together what PRVIO already knows (property value,
// shared savings pot, mortgage balance) with manually tracked accounts (bank,
// investments, vehicles, loans). Every line is a real figure — nothing is
// estimated (honesty law).

// MARK: Shared composition

extension View {
    /// Builds the net-worth snapshot from all sources, converting each figure
    /// into the preferred currency. Kept here so the section and the full page
    /// compute it identically.
    func buildNetWorth(accounts: [NetWorthAccount],
                       propertyValue: PropertyValueEntry?,
                       goals: [SavingsGoal],
                       collected: (SavingsGoal) -> Double,
                       mortgageRemaining: Double,
                       preferred: String,
                       convert: (Double, String) -> Double) -> NetWorthSnapshot {
        var derived: [NetWorthLine] = []

        if let pv = propertyValue, pv.valueAmount > 0 {
            derived.append(NetWorthLine(
                id: "derived-property", name: String(localized: "nw_line_property"),
                icon: "house.fill", amount: convert(pv.valueAmount, pv.currency),
                isAsset: true, isDerived: true, account: nil))
        }

        let savings = goals.reduce(0.0) { $0 + convert(collected($1), $1.currency) }
        if savings > 0 {
            derived.append(NetWorthLine(
                id: "derived-savings", name: String(localized: "nw_line_savings"),
                icon: "target", amount: savings,
                isAsset: true, isDerived: true, account: nil))
        }

        if mortgageRemaining > 0 {
            derived.append(NetWorthLine(
                id: "derived-mortgage", name: String(localized: "nw_line_mortgage"),
                icon: "house.fill", amount: mortgageRemaining,
                isAsset: false, isDerived: true, account: nil))
        }

        let manual = accounts.map { a in
            NetWorthLine(id: a.id.uuidString, name: a.name, icon: a.iconName,
                         amount: convert(a.balance, a.currency),
                         isAsset: a.isAsset, isDerived: false, account: a)
        }
        return NetWorthComposition.build(accounts: manual, derived: derived)
    }
}

// MARK: Section (embedded on FinancesView)

struct NetWorthSection: View {
    @Environment(NetWorthService.self) private var service
    @Environment(PropertyValueService.self) private var valueService
    @Environment(SavingsGoalService.self) private var savingsService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    private var preferred: String { appSettings.preferredCurrency }

    private var snapshot: NetWorthSnapshot {
        buildNetWorth(accounts: service.accounts,
                      propertyValue: valueService.latestValue,
                      goals: savingsService.goals,
                      collected: { savingsService.progress(for: $0).collected },
                      mortgageRemaining: MortgageSnapshot.remainingBalance,
                      preferred: preferred,
                      convert: { currencyService.convert($0, from: $1, to: preferred) })
    }

    var body: some View {
        let snap = snapshot
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            NavigationLink { NetWorthView() } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("nw_section_title")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            NavigationLink { NetWorthView() } label: {
                if snap.hasData {
                    NetWorthSummaryCard(snapshot: snap, currency: preferred)
                } else {
                    EmptyStateView(icon: "chart.pie.fill",
                                   title: "nw_empty_title",
                                   message: "nw_empty_message")
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: Summary card (net number + asset/liability split)

struct NetWorthSummaryCard: View {
    let snapshot: NetWorthSnapshot
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            VStack(alignment: .leading, spacing: 2) {
                Text("nw_net_label")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                Text(verbatim: CurrencyService.money(snapshot.net, code: currency, whole: true))
                    .font(AppFont.scaled(30, weight: .bold))
                    .foregroundStyle(snapshot.net >= 0 ? Color.brandSuccess : Color.brandDanger)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            SplitBar(fraction: snapshot.assetFraction,
                     leadingTint: .brandSuccess, trailingTint: .brandDanger)

            HStack {
                labelled("nw_assets", snapshot.assets, .brandSuccess, alignment: .leading)
                Spacer()
                labelled("nw_liabilities", snapshot.liabilities, .brandDanger, alignment: .trailing)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
    }

    private func labelled(_ key: LocalizedStringKey, _ value: Double, _ tint: Color,
                          alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(key).font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
            }
            Text(verbatim: CurrencyService.money(value, code: currency, whole: true))
                .font(AppFont.scaled(16, weight: .bold)).foregroundStyle(.primary).monospacedDigit()
        }
    }
}

/// A two-tone bar: assets fill from the left, liabilities from the right.
struct SplitBar: View {
    let fraction: Double     // assets' share, 0…1
    let leadingTint: Color
    let trailingTint: Color

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule().fill(leadingTint)
                    .frame(width: max(0, (geo.size.width - 2) * fraction))
                Capsule().fill(trailingTint.opacity(0.85))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: Full page

struct NetWorthView: View {
    @Environment(NetWorthService.self) private var service
    @Environment(PropertyValueService.self) private var valueService
    @Environment(SavingsGoalService.self) private var savingsService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false
    @State private var editing: NetWorthAccount?

    private var preferred: String { appSettings.preferredCurrency }

    private var snapshot: NetWorthSnapshot {
        buildNetWorth(accounts: service.accounts,
                      propertyValue: valueService.latestValue,
                      goals: savingsService.goals,
                      collected: { savingsService.progress(for: $0).collected },
                      mortgageRemaining: MortgageSnapshot.remainingBalance,
                      preferred: preferred,
                      convert: { currencyService.convert($0, from: $1, to: preferred) })
    }

    var body: some View {
        let snap = snapshot
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                if snap.hasData {
                    NetWorthSummaryCard(snapshot: snap, currency: preferred)
                    lineGroup("nw_assets", lines: snap.assetLines)
                    lineGroup("nw_liabilities", lines: snap.liabilityLines)
                } else {
                    EmptyStateView(icon: "chart.pie.fill",
                                   title: "nw_empty_title",
                                   message: "nw_empty_message",
                                   actionLabel: "nw_add") { showAdd = true }
                        .padding(.top, AppSpacing.xxl)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("nw_section_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text("nw_add"))
            }
        }
        .sheet(isPresented: $showAdd) { AddNetWorthAccountSheet() }
        .sheet(item: $editing) { AddNetWorthAccountSheet(editing: $0) }
        .task { await service.load() }
    }

    @ViewBuilder
    private func lineGroup(_ title: LocalizedStringKey, lines: [NetWorthLine]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title).font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
                ForEach(lines) { line in
                    NetWorthRow(line: line, currency: preferred,
                                onDelete: line.account.map { acc in { Task { await service.deleteAccount(acc) } } },
                                onEdit: line.account.map { acc in { editing = acc } })
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }
}

// MARK: One row (derived = read-only; manual = editable/deletable)

struct NetWorthRow: View {
    let line: NetWorthLine
    let currency: String
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: line.icon)
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(line.isAsset ? Color.brandSuccess : Color.brandDanger)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: line.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                if line.isDerived {
                    Text("nw_auto").font(AppFont.scaled(11)).foregroundStyle(Color.secondaryTextColor)
                }
            }
            Spacer()
            Text(verbatim: (line.isAsset ? "" : "−") + CurrencyService.money(line.amount, code: currency, whole: true))
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(line.isAsset ? .primary : Color.brandDanger)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let onEdit {
                Button { onEdit() } label: { Label("nw_edit", systemImage: "pencil") }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: { Label("nw_delete", systemImage: "trash") }
            }
        }
    }
}

// MARK: Add / edit sheet

struct AddNetWorthAccountSheet: View {
    @Environment(NetWorthService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    /// When set, the sheet edits this account instead of creating one.
    var editing: NetWorthAccount? = nil

    @State private var name = ""
    @State private var isAsset = true
    @State private var kind: NetWorthKind = .bank
    @State private var balance = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var didHydrate = false

    private var currency: String { editing?.currency ?? appSettings.preferredCurrency }

    private var kinds: [NetWorthKind] { isAsset ? NetWorthKind.assetKinds : NetWorthKind.liabilityKinds }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(balance) ?? 0) > 0
    }

    var body: some View {
        FormScaffold(title: editing == nil ? "nw_new" : "nw_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                Picker("nw_side", selection: $isAsset.animation(.snappy)) {
                    Text("nw_assets").tag(true)
                    Text("nw_liabilities").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: isAsset) { _, _ in
                    if !kinds.contains(kind) { kind = kinds.first ?? .otherAsset }
                }
            }

            FormGroup {
                TextField("nw_name_placeholder", text: $name).font(AppFont.body)
                FormDivider()
                HStack {
                    Text("nw_balance").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $balance).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.body)
                    Text(verbatim: currency).foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                TextField("nw_notes_placeholder", text: $notes).font(AppFont.body)
            }

            FormGroup(title: "nw_kind") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4),
                          spacing: AppSpacing.md) {
                    ForEach(kinds) { k in
                        Button { kind = k; HapticFeedback.selection() } label: {
                            VStack(spacing: 4) {
                                Image(systemName: k.icon)
                                    .font(AppFont.scaled(18, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(kind == k
                                        ? (isAsset ? Color.brandSuccess : Color.brandDanger).opacity(AppOpacity.tintedFill)
                                        : Color.primary.opacity(AppOpacity.subtleFill),
                                        in: RoundedRectangle(cornerRadius: AppRadius.md))
                                    .foregroundStyle(kind == k
                                        ? (isAsset ? Color.brandSuccess : Color.brandDanger) : .primary)
                                Text(k.label)
                                    .font(AppFont.scaled(10))
                                    .foregroundStyle(Color.secondaryTextColor)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard !didHydrate else { return }
        didHydrate = true
        guard let a = editing else { return }
        name = a.name
        isAsset = a.isAsset
        kind = NetWorthKind(rawValue: a.kind) ?? (a.isAsset ? .bank : .loan)
        balance = a.balance == a.balance.rounded() ? String(Int(a.balance)) : String(a.balance)
        notes = a.notes ?? ""
    }

    private func save() {
        isSaving = true
        let cat = isAsset ? "asset" : "liability"
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let bal = Double(balance) ?? 0
        let cleanNotes = notes.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                if let a = editing {
                    try await service.updateAccount(a.id, patch: NetWorthService.AccountPatch(
                        name: cleanName, category: cat, kind: kind.rawValue, balance: bal,
                        currency: currency, icon: nil,
                        notes: cleanNotes.isEmpty ? nil : cleanNotes,
                        updatedAt: ISODate.string(from: Date())))
                } else {
                    guard let pid = propertyService.primary?.id else {
                        error = String(localized: "No property found. Please set up your property first.")
                        isSaving = false; return
                    }
                    try await service.addAccount(NetWorthService.NewAccount(
                        propertyId: pid.uuidString, name: cleanName, category: cat,
                        kind: kind.rawValue, balance: bal, currency: appSettings.preferredCurrency,
                        icon: nil, notes: cleanNotes.isEmpty ? nil : cleanNotes))
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

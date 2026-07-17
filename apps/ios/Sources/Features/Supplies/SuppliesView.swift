import SwiftUI

// MARK: - Category / priority helpers (used by AddSupplyItemSheet, SupplyListDetailView)

// `label` holds a LOCALIZATION KEY, not display text — render sites resolve it
// (Text(LocalizedStringKey:) / String(localized:)) so the shopping form reads
// in the user's language, not English.
let supplyCategories: [(id: String, label: String)] = [
    ("food",        "sup_cat_food"),
    ("cleaning",    "sup_cat_cleaning"),
    ("bathroom",    "sup_cat_bathroom"),
    ("garden",      "sup_cat_garden"),
    ("diy",         "sup_cat_diy"),
    ("electronics", "sup_cat_electronics"),
    ("pet",         "sup_cat_pet"),
    ("other",       "sup_cat_other"),
]

let supplyPriorities: [(id: String, label: String)] = [
    ("low",      "sup_prio_low"),
    ("medium",   "sup_prio_medium"),
    ("high",     "sup_prio_high"),
    ("critical", "sup_prio_critical"),
]

// MARK: - Supplies / Expense Hub

enum ExpenseTab: Hashable { case overview, lists, toBuy, completed }

struct SuppliesView: View {
    @Environment(SupplyService.self) private var supplyService
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService

    @State private var activeTab: ExpenseTab = .overview
    @State private var showAddList = false
    @State private var showScanner = false
    @State private var showAddReceipt = false
    @State private var showBudgets = false
    @State private var showReports = false
    @State private var searchText = ""
    @State private var priceHistoryTarget: PriceHistoryTarget? = nil

    private var filteredLists: [SupplyList] {
        supplyService.lists.filter { $0.name.matchesSearch(searchText) }
    }

    private var pageTitle: String {
        switch activeTab {
        case .overview:   return String(localized: "expense_title")
        case .lists:      return String(localized: "expense_lists_title")
        case .toBuy:      return String(localized: "De cumpărat")
        case .completed:  return String(localized: "Finalizate")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch activeTab {
            case .overview:
                ExpenseDashboardView(
                    activeTab: $activeTab,
                    showScanner: $showScanner,
                    showAddReceipt: $showAddReceipt,
                    showBudgets: $showBudgets,
                    showReports: $showReports
                )
                .environment(receiptService)
                .environment(propertyService)
                .environment(supplyService)
            case .lists:
                shoppingListsContent
            case .toBuy:
                toBuyContent
            case .completed:
                completedContent
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    filterButton
                    if activeTab == .lists {
                        Button { showAddList = true; HapticFeedback.impact(.light) } label: {
                            Image(systemName: "plus").font(AppFont.title3).foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Add list")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddList) {
            AddSupplyListSheet().environment(supplyService).environment(propertyService)
        }
        .sheet(isPresented: $showScanner) {
            ReceiptScannerView().environment(receiptService).environment(propertyService)
        }
        .sheet(isPresented: $showAddReceipt) {
            AddReceiptSheet().environment(receiptService).environment(propertyService)
        }
        .sheet(isPresented: $showBudgets) {
            BudgetManagementView().environment(receiptService).environment(propertyService)
        }
        .sheet(isPresented: $showReports) {
            SpendingReportView().environment(receiptService)
        }
        .sheet(item: $priceHistoryTarget) { target in
            ProductPriceHistorySheet(productName: target.name)
                .environment(receiptService)
        }
        .task {
            if let id = propertyService.primary?.id {
                async let _ = supplyService.load(propertyId: id)
                async let _ = receiptService.load(propertyId: id)
            }
        }
        .userActivity("com.prvio.shopping") { activity in
            activity.title = String(localized: "Shopping — PRVIO")
            activity.userInfo = ["tab": "shopping"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
    }

    // MARK: - Toolbar

    /// One circle, everything (the one-circle law): the four views that used
    /// to sit as a permanent underline strip on the page body, plus the old
    /// "+" menu's one-shot actions (scan / manual receipt / budgets /
    /// reports) — a single aggregated popover, same pattern as Inventory.
    /// Nothing here narrows a list — switching views navigates and the rows
    /// are one-shot — so the trigger never claims the "filtered" accent dot.
    private var filterButton: some View {
        GlassFilterButton(inToolbar: true) {
            GlassFilterSection(
                title: "View",
                options: [
                    GlassPickerOption(value: ExpenseTab.overview, icon: "chart.bar.fill",
                                      title: String(localized: "expense_tab_overview")),
                    GlassPickerOption(value: ExpenseTab.lists, icon: "list.bullet",
                                      title: String(localized: "expense_tab_lists"),
                                      count: supplyService.lists.count),
                    GlassPickerOption(value: ExpenseTab.toBuy, icon: "cart.fill",
                                      title: String(localized: "De cumpărat"),
                                      count: supplyService.totalPending),
                    GlassPickerOption(value: ExpenseTab.completed, icon: "checkmark.circle.fill",
                                      title: String(localized: "Finalizate"),
                                      count: supplyService.totalCompleted)
                ],
                selection: $activeTab)
            GlassFilterSectionDivider()
            GlassFilterActionRow(icon: "camera.viewfinder",
                                 title: String(localized: "expense_scan_receipt")) {
                showScanner = true
            }
            GlassFilterActionRow(icon: "plus.circle",
                                 title: String(localized: "expense_add_manual")) {
                showAddReceipt = true
            }
            GlassFilterActionRow(icon: "target",
                                 title: String(localized: "expense_manage_budgets")) {
                showBudgets = true
            }
            GlassFilterActionRow(icon: "chart.bar.doc.horizontal",
                                 title: String(localized: "expense_reports")) {
                showReports = true
            }
        }
    }

    // MARK: - Shopping lists

    private var shoppingListsContent: some View {
        Group {
            if propertyService.primary == nil {
                noPropertyState
            } else if supplyService.isLoading && supplyService.lists.isEmpty {
                loadingState
            } else if supplyService.lists.isEmpty {
                emptyListsState
            } else {
                listsScrollContent
            }
        }
    }

    private var listsScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if searchText.isEmpty { pantryCard }
                if !filteredLists.isEmpty {
                    listsGrid
                } else if !searchText.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                }
                if supplyService.totalPending > 0 { urgentSection }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await supplyService.load(propertyId: id)
            }
        }
    }

    /// The pantry door: real stock, fed automatically by receipt scans.
    private var pantryCard: some View {
        NavigationLink(destination: PantryView()) {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "basket.fill")
                        .font(AppFont.scaled(17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .mediaGlass(in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("pantry_title")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text("pantry_card_subtitle")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var listsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "supply_section_lists"))
                .font(AppFont.label).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(filteredLists) { list in
                    NavigationLink(destination:
                        SupplyListDetailView(list: list)
                            .environment(supplyService)
                            .environment(propertyService)
                    ) {
                        SupplyListCard(list: list).environment(supplyService)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await supplyService.deleteList(list) }
                        } label: { Label("Delete list", systemImage: "trash") }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var urgentSection: some View {
        let urgent = supplyService.items
            .filter { !$0.isCompleted && ($0.priority == "critical" || $0.priority == "high") && $0.name.matchesSearch(searchText) }
            .prefix(5)
        if !urgent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("URGENT")
                    .font(AppFont.label).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(urgent.enumerated()), id: \.element.id) { idx, item in
                            compactRow(item, isLast: idx == urgent.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func compactRow(_ item: SupplyItem, isLast: Bool) -> some View {
        let listName = supplyService.lists.first { $0.id == item.listId }?.name ?? ""
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: item.categoryIcon).font(AppFont.captionEmphasis).foregroundStyle(item.categoryColor)
                    .frame(width: 30, height: 30)
                    .glassRoundedRect(7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(AppFont.footnote).foregroundStyle(.primary)
                    Text(listName).font(AppFont.scaled(11)).foregroundStyle(.secondary)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(item.priorityColor).frame(width: 3, height: 22)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
            if !isLast { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 54) }
        }
    }

    // MARK: - To Buy / Completed tabs

    private var toBuyContent: some View {
        let pending = supplyService.items.filter { !$0.isCompleted && $0.name.matchesSearch(searchText) }
        return Group {
            if pending.isEmpty && searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cart.badge.checkmark")
                        .font(AppFont.scaled(52)).foregroundStyle(Color.primary.opacity(0.12))
                    Text(String(localized: "supply_all_done"))
                        .font(AppFont.scaled(17, weight: .semibold)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !pending.isEmpty {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(pending.enumerated()), id: \.element.id) { idx, item in
                                        SupplyItemRow(
                                            item: item,
                                            isLast: idx == pending.count - 1,
                                            onToggle: { Task { await supplyService.toggleComplete(item) } },
                                            onEdit: {},
                                            onDelete: { Task { await supplyService.deleteItem(item) } },
                                            onPriceHistory: receiptService.receiptItems.isEmpty
                                                ? nil
                                                : { priceHistoryTarget = PriceHistoryTarget(name: item.name) }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.xl)
                        } else if !searchText.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No results")
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.top, AppSpacing.lg)
                }
            }
        }
    }

    private var completedContent: some View {
        let done = supplyService.items.filter { $0.isCompleted && $0.name.matchesSearch(searchText) }
        return Group {
            if done.isEmpty && searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(AppFont.scaled(52)).foregroundStyle(Color.primary.opacity(0.12))
                    Text(String(localized: "supply_empty_title"))
                        .font(AppFont.scaled(17, weight: .semibold)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !done.isEmpty {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(done.enumerated()), id: \.element.id) { idx, item in
                                        SupplyItemRow(
                                            item: item,
                                            isLast: idx == done.count - 1,
                                            onToggle: { Task { await supplyService.toggleComplete(item) } },
                                            onEdit: {},
                                            onDelete: { Task { await supplyService.deleteItem(item) } },
                                            onPriceHistory: receiptService.receiptItems.isEmpty
                                                ? nil
                                                : { priceHistoryTarget = PriceHistoryTarget(name: item.name) }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.xl)
                        } else if !searchText.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No results")
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.top, AppSpacing.lg)
                }
            }
        }
    }

    // MARK: - States

    private var emptyListsState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cart.badge.plus").font(AppFont.scaled(56)).foregroundStyle(Color.primary.opacity(0.12))
            Text(String(localized: "supply_empty_title")).font(AppFont.title3).foregroundStyle(Color.primary.opacity(0.6))
            Text(String(localized: "supply_empty_body")).font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).multilineTextAlignment(.center)
            Button { showAddList = true } label: {
                Label(String(localized: "supply_add_first"), systemImage: "plus")
                    .font(AppFont.subheadline).foregroundStyle(.primary)
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack { Spacer(); ProgressView().tint(.primary); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noPropertyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "house.slash").font(AppFont.scaled(48)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No property added").font(AppFont.headline).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - List card

struct SupplyListCard: View {
    @Environment(SupplyService.self) private var supplyService
    let list: SupplyList

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [list.swiftColor.opacity(0.65), list.swiftColor.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ).frame(height: 72)
                    Image(systemName: list.icon)
                        .font(AppFont.scaled(28, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).padding(AppSpacing.base)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(list.name).font(AppFont.footnoteEmphasis).foregroundStyle(.primary).lineLimit(1)
                    let pending = supplyService.pendingCount(for: list.id)
                    Text(pending == 0 ? String(localized: "supply_all_done") : "\(pending) \(String(localized: "supply_to_buy_short"))")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(pending == 0 ? Color.brandSuccess : Color.primary.opacity(AppOpacity.secondaryText))
                }
                .padding(.horizontal, AppSpacing.md).padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Item row

struct SupplyItemRow: View {
    let item: SupplyItem
    let isLast: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Optional "price history" context action — offered only where the
    /// caller can actually present the history (real receipt data).
    var onPriceHistory: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(AppFont.scaled(22))
                        .foregroundStyle(item.isCompleted
                            ? Color.brandSuccess
                            : Color.primary.opacity(0.28))
                        .symbolEffect(.bounce, value: item.isCompleted)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(AppFont.scaled(15)).foregroundStyle(item.isCompleted ? Color.primary.opacity(AppOpacity.disabled) : .primary)
                            .strikethrough(item.isCompleted, color: .secondary).lineLimit(1)
                        if let qty = item.quantity, !qty.isEmpty {
                            QuantityBadge(text: qty)
                        }
                    }
                    if let loc = item.location, !loc.isEmpty {
                        Label(SupplyLocation.displayName(for: loc), systemImage: "mappin")
                            .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                }
                Spacer()
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.isCompleted ? Color.clear : item.priorityColor).frame(width: 3, height: 24)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
            .contextMenu {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                Button { onToggle() } label: {
                    Label(LocalizedStringKey(item.isCompleted ? "Mark as incomplete" : "Mark as complete"),
                          systemImage: item.isCompleted ? "circle" : "checkmark.circle")
                }
                if let onPriceHistory {
                    Button { onPriceHistory() } label: {
                        Label(String(localized: "price_history_title"),
                              systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
            }
            if !isLast { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 58) }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { onToggle() } label: {
                Label(LocalizedStringKey(item.isCompleted ? "Undo" : "Complete"),
                      systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(item.isCompleted ? .orange : Color.brandSuccess)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
        }
    }
}

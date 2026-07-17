import SwiftUI
import VisionKit

// MARK: - Main View

struct InventoryView: View {
    var autoScan: Bool = false
    var autoAdd: Bool = false
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) private var router
    @Environment(InventoryService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @State private var status: StatusFilter?
    @State private var selectedCategory: String?
    @State private var selectedLocation: String?
    @AppStorage("inventory.sort") private var sortRaw = InvSort.recent.rawValue
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var showScanner = false
    @State private var selectedItem: InventoryItem?
    @State private var editItem: InventoryItem?
    @State private var loanItem: InventoryItem?
    @State private var deleteCandidate: InventoryItem?
    @State private var scannedUnknown = false
    @State private var didAutoScan = false
    @State private var didAutoAdd = false
    private let favorites = InventoryFavorites.shared

    /// Cross-cutting slices (favorites / loaned / warranty). One at a time —
    /// they answer different questions — but each combines freely with a
    /// category, a location and the search text.
    enum StatusFilter { case favorites, loaned, warranty }

    enum InvSort: String, CaseIterable {
        case recent, name, value, location

        /// Same catalog keys the sort menu resolved, as plain strings for
        /// `GlassPickerOption.title`.
        var title: String {
            switch self {
            case .recent:   return String(localized: "inv_sort_recent")
            case .name:     return String(localized: "inv_sort_name")
            case .value:    return String(localized: "inv_sort_value")
            case .location: return String(localized: "inv_sort_location")
            }
        }
        var icon: String {
            switch self {
            case .recent:   return "clock"
            case .name:     return "textformat"
            case .value:    return "eurosign.circle"
            case .location: return "mappin.circle"
            }
        }
    }

    private var sort: InvSort { InvSort(rawValue: sortRaw) ?? .recent }
    private var hasActiveFilter: Bool { status != nil || selectedCategory != nil || selectedLocation != nil }

    // MARK: Filtering + sorting

    private var filtered: [InventoryItem] {
        var base = service.items
        switch status {
        case .favorites: base = base.filter { favorites.isFavorite($0.id) }
        case .loaned:    base = base.filter(\.isLoaned)
        case .warranty:  base = base.filter { $0.warrantyExpiresAt != nil }
        case nil:        break
        }
        if let cat = selectedCategory { base = base.filter { $0.category == cat } }
        if let loc = selectedLocation { base = base.filter { $0.location == loc } }
        base = base.filter {
            $0.name.matchesSearch(searchText)
                || $0.brand.matchesSearch(searchText)
                || $0.serialNumber.matchesSearch(searchText)
                || $0.category.matchesSearch(searchText)
                || $0.location.matchesSearch(searchText)
        }
        return sorted(base)
    }

    private func sorted(_ items: [InventoryItem]) -> [InventoryItem] {
        switch sort {
        case .recent:
            // The service delivers newest-first (created_at desc). The one
            // exception: the warranty slice defaults to soonest-expiring
            // first — the order the user checks under time pressure.
            if status == .warranty {
                return items.sorted {
                    ($0.warrantyExpiresAt ?? .distantFuture) < ($1.warrantyExpiresAt ?? .distantFuture)
                }
            }
            return items
        case .name:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .value:
            return items.sorted {
                $0.purchasePrice != $1.purchasePrice
                    ? $0.purchasePrice > $1.purchasePrice
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .location:
            return items.sorted {
                let l0 = InventoryLabels.location($0.location)
                let l1 = InventoryLabels.location($1.location)
                return l0 != l1
                    ? l0.localizedStandardCompare(l1) == .orderedAscending
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !service.items.isEmpty {
                    summaryBar.padding(.horizontal, AppSpacing.xl).padding(.top, 10).padding(.bottom, AppSpacing.sm)
                }
                if service.items.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    VStack {
                        Spacer()
                        Text("inv_no_results").font(AppFont.scaled(16)).foregroundStyle(Color.primary.opacity(0.4))
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { item in
                                InventoryRow(item: item, isFavorite: favorites.isFavorite(item.id))
                                    .onTapGesture { selectedItem = item }
                                    .contextMenu {
                                        Button { selectedItem = item } label: {
                                            Label("View", systemImage: "eye")
                                        }
                                        Button { editItem = item } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button {
                                            HapticFeedback.impact(.light)
                                            favorites.toggle(item.id)
                                        } label: {
                                            if favorites.isFavorite(item.id) {
                                                Label("Remove from Favorites", systemImage: "star.slash")
                                            } else {
                                                Label("Add to Favorites", systemImage: "star")
                                            }
                                        }
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); Task { await service.markReturned(item) } } label: {
                                                Label("Returned", systemImage: "checkmark.circle")
                                            }
                                        } else {
                                            Button { HapticFeedback.impact(.medium); loanItem = item } label: {
                                                Label("inv_lend_action", systemImage: "arrow.uturn.right.circle")
                                            }
                                        }
                                        Divider()
                                        Button(role: .destructive) { deleteCandidate = item } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } preview: {
                                        InventoryItemPreview(item: item)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { HapticFeedback.warning(); Task { await service.delete(item) } } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); Task { await service.markReturned(item) } } label: { Label("Returned", systemImage: "checkmark.circle") }
                                                .tint(Color.brandSuccess)
                                        } else {
                                            Button { HapticFeedback.impact(.medium); loanItem = item } label: { Label("inv_lend_action", systemImage: "arrow.uturn.right.circle") }
                                                .tint(.accentColor)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl).padding(.bottom, 110)
                    }
                    .refreshable {
                        if let pid = PropertyService.activePropertyId {
                            await service.load(propertyId: pid)
                        }
                    }
                }
            }
            FloatingSpeedDial(
                actions: appSettings.fabVisible(.inventory) ? appSettings.fabActions(.inventory) : [],
                onSelect: { action in
                    switch action {
                    case .scan:    showScanner = true
                    case .addItem: showAdd = true
                    default:       router.perform(action)
                    }
                },
                bottomPadding: 16
            )
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 5) {
                    if !service.items.isEmpty {
                        filterButton
                        exportMenu
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5, height: 18)
                    }
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus").font(AppFont.subheadline).frame(width: 38, height: 32)
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Add item")
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddInventorySheet { item in Task { await service.add(item) } } }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerSheet { qrValue in
                showScanner = false
                if let found = resolveScanned(qrValue) {
                    HapticFeedback.success()
                    selectedItem = found
                } else {
                    HapticFeedback.error()
                    scannedUnknown = true
                }
            }
        }
        .sheet(item: $selectedItem) { item in ItemDetailView(item: item, service: service) }
        .sheet(item: $editItem) { item in
            AddInventorySheet(editing: item) { updated in Task { await service.update(updated) } }
        }
        .sheet(item: $loanItem) { item in
            LoanItemSheet(suggestions: service.items.recentBorrowers) { borrower, returnDate in
                Task { await service.loanOut(item, to: borrower, expectedReturn: returnDate) }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: .init(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = deleteCandidate {
                    HapticFeedback.warning()
                    Task { await service.delete(item) }
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Item not found", isPresented: $scannedUnknown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This QR code doesn't match any item in your inventory.")
        }
        .onAppear {
            if autoScan && !didAutoScan { didAutoScan = true; showScanner = true }
            if autoAdd && !didAutoAdd   { didAutoAdd = true; showAdd = true }
        }
    }

    // MARK: - Toolbar menus

    /// ONE aggregated control replaces both the chip row and the old sort
    /// menu: every slice (status / category / location) plus the sort order,
    /// in a single popover visit. The accent dot reflects narrowing filters
    /// only — a non-default sort reorders the same items, it never narrows
    /// the list, so it must not claim "filtered".
    private var filterButton: some View {
        let counts = filterCounts
        return GlassFilterButton(isActive: hasActiveFilter, inToolbar: true) {
            GlassFilterSection(title: "Status",
                               options: statusOptions(counts), selection: $status)
            GlassFilterSectionDivider()
            GlassFilterSection(title: "Category",
                               options: categoryOptions(counts), selection: $selectedCategory)
            GlassFilterSectionDivider()
            GlassFilterSection(title: "Location",
                               options: locationOptions(counts), selection: $selectedLocation)
            GlassFilterSectionDivider()
            GlassFilterSection(title: "inv_sort_by",
                               options: sortOptions, selection: $sortRaw)
        }
    }

    private var exportMenu: some View {
        Menu {
            Button {
                HapticFeedback.impact(.light)
                shareReport()
            } label: {
                Label("inv_report_action", systemImage: "doc.richtext")
            }
            Button {
                HapticFeedback.impact(.light)
                printQRLabels()
            } label: {
                Label("inv_qr_labels_action", systemImage: "qrcode")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(AppFont.subheadline).frame(width: 38, height: 32)
        }
        .accessibilityLabel(Text("inv_share_print"))
    }

    /// Full inventory, grouped by category with subtotals — the document you
    /// hand an insurer, so it always covers every item, not the current slice.
    private func shareReport() {
        guard let url = InventoryExport.makeReportPDF(
            items: service.items,
            propertyName: propertyService.primary?.name
        ) else { return }
        SystemActions.share([url])
    }

    /// One printable A4 sheet of QR labels for what's currently listed —
    /// filter first to print a subset, or leave "Toate" for everything.
    private func printQRLabels() {
        guard let data = InventoryExport.makeQRLabelsPDF(items: filtered) else { return }
        SystemActions.print(data: data, jobName: String(localized: "inv_qr_labels_job"))
    }

    // MARK: - Scan resolution

    /// The service resolves legacy formats (`?id=` and `prvio://inventory/`);
    /// current labels encode `https://…/i/<uuid>`, whose id rides in the last
    /// path component — without this, the app couldn't find its own codes.
    private func resolveScanned(_ value: String) -> InventoryItem? {
        if let hit = service.itemByQR(value) { return hit }
        if let last = value.split(separator: "/").last,
           let id = UUID(uuidString: String(last)) {
            return service.items.first { $0.id == id }
        }
        return nil
    }

    // MARK: - Sub-views

    private var summaryBar: some View {
        HStack(spacing: 8) {
            // Honest value: until at least one item carries a price, there is
            // no total to report — show a dash, not a misleading "0 €".
            infoTile(service.items.contains(where: { $0.purchasePrice > 0 })
                        ? CurrencyService.money(service.totalValue, code: "EUR", whole: true)
                        : "—",
                     "Value")
            infoTile("\(service.items.count)", "Items")
            filterTile("\(service.loanedCount)", "Loaned", target: .loaned,
                       highlight: service.loanedCount > 0 ? .orange : nil)
            filterTile("\(service.warrantyCount)", "inv_stat_warranties", target: .warranty,
                       highlight: service.expiringWarrantyCount > 0 ? Color.brandDanger : nil)
        }
    }

    private func infoTile(_ value: String, _ label: LocalizedStringKey) -> some View {
        GlassCard(padding: 10) {
            VStack(spacing: 3) {
                // Was `.white`, which is invisible on the light-mode card. Use
                // `.primary` so it's readable in both light and dark.
                Text(value).font(AppFont.scaled(15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(AppFont.scaled(10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }.frame(maxWidth: .infinity)
        }
    }

    /// A summary tile that doubles as a filter: tap filters the list to this
    /// slice, tap again returns to All. Selection speaks the GlassFilterChip
    /// language (accent-tinted glass / accent ring) so it reads instantly.
    private func filterTile(_ value: String, _ label: LocalizedStringKey,
                            target: StatusFilter, highlight: Color? = nil) -> some View {
        let isSelected = status == target
        return Button {
            HapticFeedback.impact(.light)
            withAnimation(.spring(response: 0.25)) { status = isSelected ? nil : target }
        } label: {
            VStack(spacing: 3) {
                Text(value).font(AppFont.scaled(15, weight: .bold))
                    .foregroundStyle(isSelected ? Color.accentColor : (highlight ?? .primary))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(AppFont.scaled(10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(AppOpacity.secondaryText))
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .glassFilterRoundedRect(selected: isSelected, cornerRadius: 24)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Filter options

    /// Everything the chip row could slice by, unchanged: the three status
    /// slices, then the categories and locations that actually hold items
    /// (real counts, never a dead row). Each section's "All" row carries the
    /// nil selection that clearing a chip used to produce, so status +
    /// category + location + search still combine freely.
    private func statusOptions(_ counts: FilterCounts) -> [GlassPickerOption<StatusFilter?>] {
        [.init(value: nil, title: String(localized: "inv_filter_all")),
         .init(value: .favorites, icon: "star.fill",
               title: String(localized: "inv_filter_favorites"), count: counts.favorites),
         .init(value: .loaned, icon: "arrow.uturn.right.circle",
               title: String(localized: "inv_filter_loaned"), count: counts.loaned),
         .init(value: .warranty, icon: "checkmark.shield",
               title: String(localized: "inv_filter_warranty"), count: counts.warranty)]
    }

    private func categoryOptions(_ counts: FilterCounts) -> [GlassPickerOption<String?>] {
        var options: [GlassPickerOption<String?>] = [
            .init(value: nil, title: String(localized: "inv_filter_all"))
        ]
        for cat in InventoryCatalog.categories where counts.categories[cat] != nil {
            options.append(.init(value: cat, icon: InventoryCatalog.icon(for: cat),
                                 title: InventoryLabels.category(cat),
                                 count: counts.categories[cat]))
        }
        return options
    }

    private func locationOptions(_ counts: FilterCounts) -> [GlassPickerOption<String?>] {
        var options: [GlassPickerOption<String?>] = [
            .init(value: nil, title: String(localized: "inv_filter_all"))
        ]
        for loc in orderedLocations(counts.locations) {
            options.append(.init(value: loc, icon: "mappin",
                                 title: InventoryLabels.location(loc),
                                 count: counts.locations[loc]))
        }
        return options
    }

    private var sortOptions: [GlassPickerOption<String>] {
        InvSort.allCases.map { .init(value: $0.rawValue, icon: $0.icon, title: $0.title) }
    }

    /// Known locations keep their canonical order; free-form ones (from older
    /// data) follow, alphabetically.
    private func orderedLocations(_ present: [String: Int]) -> [String] {
        let known = InventoryCatalog.locations.filter { present[$0] != nil }
        let extra = present.keys.filter { !InventoryCatalog.locations.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return known + extra
    }

    private struct FilterCounts {
        var favorites = 0
        var loaned = 0
        var warranty = 0
        var categories: [String: Int] = [:]
        var locations: [String: Int] = [:]
    }

    /// One pass over the items builds every option badge.
    private var filterCounts: FilterCounts {
        var c = FilterCounts()
        for item in service.items {
            if favorites.isFavorite(item.id) { c.favorites += 1 }
            if item.isLoaned { c.loaned += 1 }
            if item.warrantyExpiresAt != nil { c.warranty += 1 }
            c.categories[item.category, default: 0] += 1
            c.locations[item.location, default: 0] += 1
        }
        return c
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box.fill").font(AppFont.scaled(44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No inventory yet").font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Button("Add first item") { showAdd = true }.font(AppFont.scaled(14)).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

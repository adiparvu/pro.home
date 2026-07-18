import SwiftUI

// MARK: - AppliancesView
//
// The household appliance registry: a stats strip whose first two tiles
// double as filters (in-warranty / expiring ≤60 days — the inventory summary
// bar language), category chips, search, sorting and an optional
// group-by-location reading of the same list. Every number on this screen is
// computed from real columns (warranty_until, purchase_date, location).

struct AppliancesView: View {
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false
    @State private var selectedAppliance: Appliance? = nil
    @State private var search = ""
    @State private var selectedCategory: ApplianceCategory? = nil
    @State private var sort: ApplianceSort = .newest
    @State private var groupByLocation = false
    @State private var warrantySlice: WarrantySlice? = nil

    enum ApplianceSort: String, CaseIterable {
        case newest, name, warranty

        var labelKey: LocalizedStringKey {
            switch self {
            case .newest:   return "appliance_sort_newest"
            case .name:     return "appliance_sort_name"
            case .warranty: return "appliance_sort_warranty"
            }
        }

        /// Same catalog entries as `labelKey`, resolved for the filter
        /// popover's `GlassPickerOption` (String titles).
        var title: String {
            switch self {
            case .newest:   return String(localized: "appliance_sort_newest")
            case .name:     return String(localized: "appliance_sort_name")
            case .warranty: return String(localized: "appliance_sort_warranty")
            }
        }
    }

    /// The two stat tiles that filter: real warranty math, nothing else.
    enum WarrantySlice { case inWarranty, expiringSoon }

    // MARK: Derived data (all traced to real columns)

    private var inWarranty: [Appliance] {
        applianceService.appliances.filter { ($0.warrantyDaysRemaining ?? -1) >= 0 }
    }

    /// Expiring within 60 days (still valid today).
    private var expiringSoon: [Appliance] {
        applianceService.appliances.filter {
            guard let d = $0.warrantyDaysRemaining else { return false }
            return d >= 0 && d <= 60
        }
    }

    /// Group-by-location is only offered when the data can carry it:
    /// at least half the appliances have a location.
    private var locationGroupingAvailable: Bool {
        let total = applianceService.appliances.count
        guard total > 1 else { return false }
        let located = applianceService.appliances.filter { !($0.location ?? "").isEmpty }.count
        return located * 2 >= total
    }

    private var filtered: [Appliance] {
        var list = selectedCategory == nil
            ? applianceService.appliances
            : selectedCategory.flatMap { applianceService.byCategory[$0] } ?? []
        switch warrantySlice {
        case .inWarranty:   list = list.filter { ($0.warrantyDaysRemaining ?? -1) >= 0 }
        case .expiringSoon: list = list.filter {
            guard let d = $0.warrantyDaysRemaining else { return false }
            return d >= 0 && d <= 60
        }
        case nil: break
        }
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                ($0.brand?.localizedCaseInsensitiveContains(search) ?? false) ||
                ($0.location?.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
        return sorted(list)
    }

    private func sorted(_ list: [Appliance]) -> [Appliance] {
        switch sort {
        case .name:
            return list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .newest:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .warranty:
            // Soonest-ending valid warranty first, then already expired,
            // then no warranty at all — the triage order.
            return list.sorted { a, b in
                rank(a) == rank(b)
                    ? (a.warrantyDaysRemaining ?? 0) < (b.warrantyDaysRemaining ?? 0)
                    : rank(a) < rank(b)
            }
        }
    }

    private func rank(_ a: Appliance) -> Int {
        guard let d = a.warrantyDaysRemaining else { return 2 }
        return d >= 0 ? 0 : 1
    }

    /// Location buckets in name order; the no-location bucket always last.
    private var groupedByLocation: [(location: String?, items: [Appliance])] {
        let groups = Dictionary(grouping: filtered) { ($0.location ?? "").isEmpty ? nil : $0.location }
        let named = groups.keys.compactMap { $0 }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        var result: [(String?, [Appliance])] = named.map { ($0, groups[$0] ?? []) }
        if let unlocated = groups[nil] { result.append((nil, unlocated)) }
        return result.map { (location: $0.0, items: $0.1) }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if applianceService.isLoading && applianceService.appliances.isEmpty {
                    loadingState
                } else if applianceService.appliances.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
        }
        .navigationTitle("Appliances")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search appliances…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add appliance")
            }
        }
        .sheet(isPresented: $showAdd) {
            ApplianceFormSheet()
                .environment(applianceService)
                .environment(propertyService)
        }
        .sheet(item: $selectedAppliance) { appliance in
            ApplianceDetailSheet(appliance: appliance)
                .environment(applianceService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    // MARK: - Toolbar

    /// One circle, everything (IMG_8544): the category filter that used to
    /// sit as a permanent capsule and the old ↑↓ sort menu merge into a
    /// single aggregated filter popover — same pattern as Inventory.
    private var filterButton: some View {
        // Menu-in-menu (the constitution's 4-facet rule): Category, Warranty
        // and Sort stack as native submenus with the current value on each
        // row — the Photos anatomy — instead of three flat scrolling
        // sections. The location toggle stays at the root: a boolean is a
        // row, not a facet.
        GlassFilterButton(isActive: selectedCategory != nil || warrantySlice != nil,
                          inToolbar: true) {
            GlassDrillMenu(entries: [
                .facet(id: "category", icon: "square.grid.2x2", title: "Category",
                       options: [GlassPickerOption<ApplianceCategory?>(value: nil,
                                                                       title: String(localized: "All"))]
                           + ApplianceCategory.allCases.map {
                               GlassPickerOption<ApplianceCategory?>(value: $0, title: $0.displayName)
                           },
                       selection: $selectedCategory,
                       isNarrowed: selectedCategory != nil),
                // The warranty stat tiles folded in here (IMG_8563).
                .facet(id: "warranty", icon: "checkmark.seal", title: "Warranty",
                       options: [
                           GlassPickerOption<WarrantySlice?>(value: nil,
                                                             title: String(localized: "All")),
                           GlassPickerOption<WarrantySlice?>(value: .inWarranty,
                                                             title: String(localized: "appliance_stat_in_warranty")),
                           GlassPickerOption<WarrantySlice?>(value: .expiringSoon,
                                                             title: String(localized: "appliance_stat_expiring"))
                       ],
                       selection: $warrantySlice,
                       isNarrowed: warrantySlice != nil),
                // A non-default sort reorders, it doesn't narrow — so it
                // never claims the "filtered" accent dot.
                .facet(id: "sort", icon: "arrow.up.arrow.down", title: "inv_sort_by",
                       options: ApplianceSort.allCases.map {
                           GlassPickerOption(value: $0, title: $0.title)
                       },
                       selection: $sort,
                       isNarrowed: false)
            ]) {
                if locationGroupingAvailable {
                    GlassFilterToggleRow(icon: "mappin.and.ellipse",
                                         title: String(localized: "appliance_group_location"),
                                         isOn: $groupByLocation.animation(.smooth(duration: 0.3)))
                }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if filtered.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                } else if groupByLocation && locationGroupingAvailable {
                    groupedList
                } else {
                    flatList
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    // MARK: - Lists

    private var flatList: some View {
        LazyVStack(spacing: 10) {
            ForEach(filtered) { appliance in
                row(appliance)
            }
        }
    }

    private var groupedList: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(groupedByLocation, id: \.location) { group in
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    (group.location.map { Text(verbatim: $0) } ?? Text("appliance_no_location"))
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .textCase(.uppercase)
                }
                .padding(.leading, AppSpacing.xs)
                .padding(.top, AppSpacing.xs)

                ForEach(group.items) { appliance in
                    row(appliance)
                }
            }
        }
    }

    private func row(_ appliance: Appliance) -> some View {
        ApplianceRow(appliance: appliance)
            .onTapGesture {
                selectedAppliance = appliance
                HapticFeedback.impact(.light)
            }
            // ScrollView rows have no swipe actions — the delete affordance
            // lives in the context menu (and on the detail page).
            .contextMenu {
                Button(role: .destructive) {
                    HapticFeedback.warning()
                    Task { await applianceService.delete(appliance) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - States

    private var emptyState: some View {
        EmptyStateView(
            icon: "cube.box.fill",
            title: "No appliances yet",
            message: "Track warranties, model numbers, and maintenance for all your home appliances.",
            actionLabel: "Add your first appliance",
            action: { showAdd = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Warranty presentation (shared by row + detail)
//
// The tri-state truth of the warranty column, computed once from real data:
//   • valid & >60 days   → green  "In warranty until <date>"
//   • valid & ≤60 days   → amber  "Expires in N days"
//   • past               → red    "Expired"
//   • no column value    → quiet  "No Warranty"
struct ApplianceWarrantyPresentation {
    let text: String
    let color: Color
    let isQuiet: Bool

    init(_ appliance: Appliance) {
        if let days = appliance.warrantyDaysRemaining {
            if days < 0 {
                text = String(localized: "Expired")
                color = .brandDanger
                isQuiet = false
            } else if days <= 60 {
                // localizedStringWithFormat resolves the catalog's plural
                // variations (ro: zi/zile/de zile); plain String(format:) won't.
                text = String.localizedStringWithFormat(String(localized: "appliance_warranty_days %lld"), days)
                color = .brandWarning
                isQuiet = false
            } else {
                let date = appliance.warrantyDateValue.map { AppDate.monthDayYear.string(from: $0) } ?? ""
                text = String(format: String(localized: "appliance_warranty_until %@"), date)
                color = .brandSuccess
                isQuiet = false
            }
        } else {
            text = String(localized: "No Warranty")
            color = Color.primary.opacity(AppOpacity.secondaryText)
            isQuiet = true
        }
    }
}

// MARK: - ApplianceRow

private struct ApplianceRow: View {
    let appliance: Appliance

    private var warranty: ApplianceWarrantyPresentation { .init(appliance) }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                thumb

                VStack(alignment: .leading, spacing: 4) {
                    Text(appliance.name)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if let brand = appliance.brand, !brand.isEmpty {
                            Text(brand)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                        if let model = appliance.modelNumber, !model.isEmpty {
                            if appliance.brand?.isEmpty == false {
                                Text(verbatim: "·").foregroundStyle(Color.primary.opacity(0.2))
                            }
                            Text(model)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(verbatim: warranty.text)
                            .font(AppFont.caption2)
                            .foregroundStyle(warranty.color)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 3)
                            .background(
                                warranty.isQuiet
                                    ? Color.primary.opacity(AppOpacity.hairline)
                                    : warranty.color.opacity(0.12),
                                in: Capsule())
                            .lineLimit(1)

                        if let location = appliance.location, !location.isEmpty {
                            Text(location)
                                .font(AppFont.scaled(11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(AppOpacity.hairline), in: Capsule())
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
    }

    /// Photo thumbnail when a real photo_url exists; the category badge
    /// otherwise. Never a placeholder pretending to be a photo.
    @ViewBuilder private var thumb: some View {
        if let urlString = appliance.photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ColoredIconBadge(icon: appliance.categoryIcon, color: appliance.categoryColor, size: 40)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        } else {
            ColoredIconBadge(icon: appliance.categoryIcon, color: appliance.categoryColor, size: 40)
        }
    }
}

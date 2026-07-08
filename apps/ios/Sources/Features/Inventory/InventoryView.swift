import SwiftUI
import VisionKit

// MARK: - Main View

struct InventoryView: View {
    var autoScan: Bool = false
    var autoAdd: Bool = false
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) private var router
    @Environment(InventoryService.self) private var service
    @State private var filter: InvFilter = .all
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var showScanner = false
    @State private var selectedItem: InventoryItem?
    @State private var editItem: InventoryItem?
    @State private var deleteCandidate: InventoryItem?
    @State private var scannedUnknown = false
    @State private var didAutoScan = false
    @State private var didAutoAdd = false
    private let favorites = InventoryFavorites.shared

    enum InvFilter: String, CaseIterable {
        case all = "Toate", favorites = "Favorite", loaned = "Împrumutate", tools = "Unelte"
        case garden = "Grădină", outdoor = "Exterior", electronics = "Electronice", other = "Altele"

        var icon: String {
            switch self {
            case .all:         return "square.grid.2x2.fill"
            case .favorites:   return "star.fill"
            case .loaned:      return "arrow.uturn.right.circle.fill"
            case .tools:       return "wrench.and.screwdriver.fill"
            case .garden:      return "leaf.fill"
            case .outdoor:     return "sun.max.fill"
            case .electronics: return "tv.fill"
            case .other:       return "cube.fill"
            }
        }
    }

    private var filtered: [InventoryItem] {
        let base: [InventoryItem]
        switch filter {
        case .all:         base = service.items
        case .favorites:   base = service.items.filter { favorites.isFavorite($0.id) }
        case .loaned:      base = service.items.filter { $0.isLoaned }
        case .tools:       base = service.items.filter { $0.category == "tools" }
        case .garden:      base = service.items.filter { $0.category == "garden" }
        case .outdoor:     base = service.items.filter { ["outdoor","sports","vehicles"].contains($0.category) }
        case .electronics: base = service.items.filter { $0.category == "electronics" }
        case .other:       base = service.items.filter { !["tools","garden","outdoor","sports","vehicles","electronics"].contains($0.category) }
        }
        return base.filter {
            $0.name.matchesSearch(searchText)
                || $0.brand.matchesSearch(searchText)
                || $0.serialNumber.matchesSearch(searchText)
                || $0.category.matchesSearch(searchText)
                || $0.location.matchesSearch(searchText)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !service.items.isEmpty {
                    summaryBar.padding(.horizontal, AppSpacing.xl).padding(.vertical, 10)
                }
                if service.items.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    VStack {
                        Spacer()
                        Text("No items in this category").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.4))
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
                                            Button { HapticFeedback.impact(.medium); selectedItem = item } label: { Label("Loan Out", systemImage: "arrow.uturn.right.circle") }
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
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 5) {
                    Menu {
                        // One pass builds every badge count for the menu.
                        let counts = filterCounts
                        ForEach(InvFilter.allCases, id: \.self) { f in
                            Button {
                                withAnimation(.spring(response: 0.25)) { filter = f }
                            } label: {
                                Label("\(f.rawValue)  (\(counts[f] ?? 0))", systemImage: filter == f ? "checkmark" : f.icon)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease" : filter.icon)
                            .font(AppFont.subheadline).frame(width: 38, height: 32)
                    }
                    .accessibilityLabel("Filter inventory")
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5, height: 18)
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus").font(AppFont.subheadline).frame(width: 38, height: 32)
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Add item")
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddInventorySheet { item in Task { await service.add(item) } } }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { qrValue in
                showScanner = false
                if let found = service.itemByQR(qrValue) {
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

    // MARK: - Sub-views

    private var summaryBar: some View {
        HStack(spacing: 8) {
            infoTile(CurrencyService.money(service.totalValue, code: "EUR", whole: true), "Value")
            infoTile("\(service.items.count)", "Items")
            infoTile("\(service.loanedCount)", "Loaned", highlight: service.loanedCount > 0)
            infoTile("\(service.expiringWarrantyCount)", "Warranty !", highlight: service.expiringWarrantyCount > 0)
        }
    }

    private func infoTile(_ value: String, _ label: LocalizedStringKey, highlight: Bool = false) -> some View {
        GlassCard(padding: 10) {
            VStack(spacing: 3) {
                // Was `.white`, which is invisible on the light-mode card. Use
                // `.primary` so it's readable in both light and dark.
                Text(value).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(highlight ? .orange : .primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }.frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No inventory yet").font(.system(size: 17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Button("Add first item") { showAdd = true }.font(.system(size: 14)).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One pass over the items builds every badge count — the filter menu
    /// used to re-scan the whole array once per case.
    private var filterCounts: [InvFilter: Int] {
        var counts: [InvFilter: Int] = [.all: service.items.count]
        for item in service.items {
            if favorites.isFavorite(item.id) { counts[.favorites, default: 0] += 1 }
            if item.isLoaned { counts[.loaned, default: 0] += 1 }
            switch item.category {
            case "tools":                          counts[.tools, default: 0] += 1
            case "garden":                         counts[.garden, default: 0] += 1
            case "outdoor", "sports", "vehicles":  counts[.outdoor, default: 0] += 1
            case "electronics":                    counts[.electronics, default: 0] += 1
            default:                               counts[.other, default: 0] += 1
            }
        }
        return counts
    }

}

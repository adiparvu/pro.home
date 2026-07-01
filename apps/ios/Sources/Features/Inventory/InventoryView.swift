import SwiftUI
import VisionKit

// MARK: - Main View

struct InventoryView: View {
    var autoScan: Bool = false
    var autoAdd: Bool = false
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var service: InventoryService
    @State private var filter: InvFilter = .all
    @State private var showAdd = false
    @State private var showScanner = false
    @State private var selectedItem: InventoryItem?
    @State private var scannedUnknown = false
    @State private var didAutoScan = false
    @State private var didAutoAdd = false

    enum InvFilter: String, CaseIterable {
        case all = "Toate", loaned = "Împrumutate", tools = "Unelte"
        case garden = "Grădină", outdoor = "Exterior", electronics = "Electronice", other = "Altele"

        var icon: String {
            switch self {
            case .all:         return "square.grid.2x2.fill"
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
        switch filter {
        case .all:         return service.items
        case .loaned:      return service.items.filter { $0.isLoaned }
        case .tools:       return service.items.filter { $0.category == "tools" }
        case .garden:      return service.items.filter { $0.category == "garden" }
        case .outdoor:     return service.items.filter { ["outdoor","sports","vehicles"].contains($0.category) }
        case .electronics: return service.items.filter { $0.category == "electronics" }
        case .other:       return service.items.filter { !["tools","garden","outdoor","sports","vehicles","electronics"].contains($0.category) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !service.items.isEmpty {
                    summaryBar.padding(.horizontal, 20).padding(.vertical, 10)
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
                                InventoryRow(item: item)
                                    .onTapGesture { selectedItem = item }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { HapticFeedback.warning(); Task { await service.delete(item) } } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); Task { await service.markReturned(item) } } label: { Label("Returned", systemImage: "checkmark.circle") }
                                                .tint(Color(red: 0.2, green: 0.78, blue: 0.45))
                                        } else {
                                            Button { HapticFeedback.impact(.medium); selectedItem = item } label: { Label("Loan Out", systemImage: "arrow.uturn.right.circle") }
                                                .tint(.accentColor)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 110)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(InvFilter.allCases, id: \.self) { f in
                            Button {
                                withAnimation(.spring(response: 0.25)) { filter = f }
                            } label: {
                                Label("\(f.rawValue)  (\(countFor(f)))", systemImage: filter == f ? "checkmark" : f.icon)
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
            infoTile("€\(Int(service.totalValue))", "Value")
            infoTile("\(service.items.count)", "Items")
            infoTile("\(service.loanedCount)", "Loaned", highlight: service.loanedCount > 0)
            infoTile("\(service.expiringWarrantyCount)", "Warranty !", highlight: service.expiringWarrantyCount > 0)
        }
    }

    private func infoTile(_ value: String, _ label: LocalizedStringKey, highlight: Bool = false) -> some View {
        GlassCard(padding: 10) {
            VStack(spacing: 3) {
                Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(highlight ? .orange : .white).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.4))
            }.frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No inventory yet").font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.5))
            Button("Add first item") { showAdd = true }.font(.system(size: 14)).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countFor(_ f: InvFilter) -> Int {
        switch f {
        case .all:         return service.items.count
        case .loaned:      return service.items.filter { $0.isLoaned }.count
        case .tools:       return service.items.filter { $0.category == "tools" }.count
        case .garden:      return service.items.filter { $0.category == "garden" }.count
        case .outdoor:     return service.items.filter { ["outdoor","sports","vehicles"].contains($0.category) }.count
        case .electronics: return service.items.filter { $0.category == "electronics" }.count
        case .other:       return service.items.filter { !["tools","garden","outdoor","sports","vehicles","electronics"].contains($0.category) }.count
        }
    }
}

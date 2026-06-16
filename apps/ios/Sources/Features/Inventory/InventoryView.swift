import SwiftUI
import VisionKit

// MARK: - Main View

struct InventoryView: View {
    var autoScan: Bool = false
    var autoAdd: Bool = false
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @StateObject private var service = InventoryService()
    @State private var filter: InvFilter = .all
    @State private var showAdd = false
    @State private var showScanner = false
    @State private var selectedItem: InventoryItem?
    @State private var scannedUnknown = false
    @State private var didAutoScan = false
    @State private var didAutoAdd = false

    enum InvFilter: String, CaseIterable {
        case all = "All", loaned = "Loaned", tools = "Tools"
        case garden = "Garden", outdoor = "Outdoor", electronics = "Electronics", other = "Other"

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
                                        Button(role: .destructive) { HapticFeedback.warning(); service.delete(item) } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); service.markReturned(item) } label: { Label("Returned", systemImage: "checkmark.circle") }
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
                bottomPadding: 100
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
                            .font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 32)
                    }
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5, height: 18)
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 32)
                    }.buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddInventorySheet { service.add($0) } }
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

    private func infoTile(_ value: String, _ label: String, highlight: Bool = false) -> some View {
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

// MARK: - Row

private struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: item.categoryIcon, color: item.categoryColor, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 5) {
                        if !item.brand.isEmpty {
                            Text(item.brand).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                            Text("·").foregroundStyle(Color.primary.opacity(0.2))
                        }
                        Text(item.location.capitalized).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    if item.isLoaned, let loan = item.currentLoan {
                        Label("Loaned to \(loan.borrowerName) · \(loan.daysOut)d", systemImage: "person.fill")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.purchasePrice > 0 {
                        Text("€\(Int(item.purchasePrice))").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                    }
                    switch item.warrantyStatus {
                    case .expiringSoon: Image(systemName: "exclamationmark.shield.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    case .expired:     Image(systemName: "xmark.shield.fill").font(.system(size: 11)).foregroundStyle(.red.opacity(0.7))
                    default: EmptyView()
                    }
                }
            }
        }
        .overlay {
            if item.isLoaned {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.orange.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Add Item Sheet

private struct AddInventorySheet: View {
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "tools"
    @State private var location = "garage"
    @State private var brand = ""
    @State private var serial = ""
    @State private var condition = "good"
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var price = ""
    @State private var hasWarranty = false
    @State private var warrantyDate = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    @State private var notes = ""

    private let categories = ["tools","garden","outdoor","appliances","electronics","furniture","vehicles","sports","security","other"]
    private let locations = ["garage","garden","basement","attic","shed","balcony","kitchen","living room","bedroom","storage"]
    private let conditions = ["excellent","good","fair","poor"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        card {
                            field("tag.fill", "Item name *", $name)
                            div
                            picker("folder.fill", "Category", $category, categories)
                            div
                            picker("mappin.circle.fill", "Location", $location, locations)
                            div
                            picker("sparkles", "Condition", $condition, conditions)
                        }
                        card {
                            field("building.2.fill", "Brand", $brand)
                            div
                            field("number", "Serial Number", $serial)
                            div
                            field("eurosign.circle.fill", "Value (€)", $price, keyboard: .decimalPad)
                        }
                        card {
                            toggle("calendar", "Purchase Date", $hasPurchaseDate)
                            if hasPurchaseDate {
                                div
                                HStack(spacing: 12) {
                                    Color.clear.frame(width: 28)
                                    DatePicker("", selection: $purchaseDate, in: ...Date(), displayedComponents: .date).tint(.accentColor)
                                }.padding(.horizontal, 16).padding(.vertical, 6)
                            }
                            div
                            toggle("checkmark.shield.fill", "Has Warranty", $hasWarranty)
                            if hasWarranty {
                                div
                                HStack(spacing: 12) {
                                    Color.clear.frame(width: 28)
                                    DatePicker("Until", selection: $warrantyDate, displayedComponents: .date).tint(.accentColor).font(.system(size: 15)).foregroundStyle(.primary)
                                }.padding(.horizontal, 16).padding(.vertical, 6)
                            }
                        }
                        card {
                            HStack(spacing: 12) {
                                Image(systemName: "note.text").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                TextField("Notes (optional)", text: $notes, axis: .vertical)
                                    .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).lineLimit(3...5)
                            }.padding(.horizontal, 16).padding(.vertical, 13)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var item = InventoryItem(name: name)
                        item.category = category; item.location = location; item.brand = brand
                        item.serialNumber = serial; item.condition = condition
                        item.purchaseDate = hasPurchaseDate ? purchaseDate : nil
                        item.purchasePrice = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
                        item.warrantyExpiresAt = hasWarranty ? warrantyDate : nil
                        item.notes = notes
                        onSave(item); HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
    private func field(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private func picker(_ icon: String, _ label: String, _ b: Binding<String>, _ opts: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Picker("", selection: b) { ForEach(opts, id: \.self) { Text($0.capitalized).tag($0) } }.tint(Color.primary.opacity(0.5))
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    private func toggle(_ icon: String, _ label: String, _ b: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: b).tint(.accentColor).labelsHidden()
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var div: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }
}

// MARK: - QR Scanner

private struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                DataScannerRepresentable(onScan: onScan).ignoresSafeArea()
            } else {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.25))
                    Text("Camera scanner not available on this device").font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.5)).multilineTextAlignment(.center)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                            .foregroundStyle(Color.primary.opacity(0.85)).background(Color.black.opacity(0.3), in: Circle())
                    }.padding(20)
                }
                Spacer()
                Text("Point at an item's QR code")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 60)
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var fired = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    fired = true
                    dataScanner.stopScanning()
                    DispatchQueue.main.async { self.onScan(value) }
                    return
                }
            }
        }
    }
}

import SwiftUI
import VisionKit

// MARK: - Row

struct InventoryRow: View {
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
                        Text(LocalizedStringKey(item.location.capitalized)).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
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

struct AddInventorySheet: View {
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
    private func picker(_ icon: String, _ label: LocalizedStringKey, _ b: Binding<String>, _ opts: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Picker("", selection: b) { ForEach(opts, id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) } }.tint(Color.primary.opacity(0.5))
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    private func toggle(_ icon: String, _ label: LocalizedStringKey, _ b: Binding<Bool>) -> some View {
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

struct QRScannerSheet: View {
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

struct DataScannerRepresentable: UIViewControllerRepresentable {
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

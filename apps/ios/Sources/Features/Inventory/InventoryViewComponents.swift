import SwiftUI
import VisionKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Row

struct InventoryRow: View {
    let item: InventoryItem
    var isFavorite: Bool = false

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                if let img = InventoryImageStore.load(for: item.id) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            // Keep the category icon visible alongside the photo.
                            ZStack {
                                Circle()
                                    .fill(item.categoryColor)
                                    .frame(width: 17, height: 17)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
                                Image(systemName: item.categoryIcon)
                                    .font(AppFont.scaled(8, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 4, y: 4)
                        }
                } else {
                    // Category-tinted fallback badge — the same colour mapping
                    // as the long-press preview, so every row carries its
                    // category identity even without a photo.
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(item.categoryColor.opacity(0.15))
                        Image(systemName: item.categoryIcon)
                            .font(AppFont.scaled(18, weight: .medium))
                            .foregroundStyle(item.categoryColor)
                    }
                    .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(item.name).font(AppFont.footnoteEmphasis).foregroundStyle(.primary).lineLimit(1)
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(AppFont.scaled(10))
                                .foregroundStyle(.yellow)
                        }
                    }
                    HStack(spacing: 5) {
                        if !item.brand.isEmpty {
                            Text(item.brand).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
                            Text("·").foregroundStyle(Color.primary.opacity(0.2))
                        }
                        Text(LocalizedStringKey(item.location.capitalized)).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    if item.isLoaned, let loan = item.currentLoan {
                        // "La Vasile · 3 iul." — who has it and since when.
                        Label(String(format: String(localized: "inv_loaned_short"),
                                     loan.borrowerName,
                                     loan.loanedAt.formatted(.dateTime.day().month(.abbreviated))),
                              systemImage: "person.fill")
                            .font(AppFont.scaled(10, weight: .medium)).foregroundStyle(.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.purchasePrice > 0 {
                        Text(CurrencyService.money(item.purchasePrice, code: "EUR", whole: true)).font(AppFont.captionStrong).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    switch item.warrantyStatus {
                    case .expiringSoon: Image(systemName: "exclamationmark.shield.fill").font(AppFont.scaled(11)).foregroundStyle(.orange)
                    case .expired:     Image(systemName: "xmark.shield.fill").font(AppFont.scaled(11)).foregroundStyle(.red.opacity(0.7))
                    default: EmptyView()
                    }
                }
            }
        }
        .overlay {
            if item.isLoaned {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous).strokeBorder(.orange.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Add Item Sheet

struct AddInventorySheet: View {
    var editing: InventoryItem? = nil
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didPopulate = false

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
    @State private var selectedImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var receiptImageData: Data?
    @State private var receiptPhotoItem: PhotosPickerItem?
    @State private var showSerialScanner = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showPhotoMenu = false
    @State private var showLibrary = false
    @State private var isSaving = false

    private let categories = ["tools","garden","outdoor","appliances","electronics","furniture","vehicles","sports","security","other"]
    private let locations = ["garage","garden","basement","attic","shed","balcony","kitchen","living room","bedroom","storage"]
    private let conditions = ["excellent","good","fair","poor"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        photoSection
                        card {
                            field("tag.fill", "Nume articol *", $name)
                            div
                            picker("folder.fill", "Category", $category, categories)
                            div
                            picker("mappin.circle.fill", "Location", $location, locations)
                            div
                            picker("checkmark.seal", "Condition", $condition, conditions)
                        }
                        card {
                            field("building.2.fill", "Brand", $brand)
                            div
                            serialField
                            div
                            field("eurosign.circle.fill", "Valoare (€)", $price, keyboard: .decimalPad)
                        }
                        card {
                            toggle("calendar", "Purchase Date", $hasPurchaseDate)
                            if hasPurchaseDate {
                                div
                                HStack(spacing: 12) {
                                    Color.clear.frame(width: 28)
                                    DatePicker("", selection: $purchaseDate, in: ...Date(), displayedComponents: .date).tint(.accentColor)
                                }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.xs)
                            }
                            div
                            toggle("checkmark.shield.fill", "Has Warranty", $hasWarranty)
                            if hasWarranty {
                                div
                                HStack(spacing: 12) {
                                    Color.clear.frame(width: 28)
                                    DatePicker("Until", selection: $warrantyDate, displayedComponents: .date).tint(.accentColor).font(AppFont.scaled(15)).foregroundStyle(.primary)
                                }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.xs)
                                div
                                receiptRow
                            }
                        }
                        card {
                            HStack(spacing: 12) {
                                Image(systemName: "note.text").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                TextField("Note (opțional)", text: $notes, axis: .vertical)
                                    .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor).lineLimit(3...5)
                            }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle(editing != nil ? String(localized: "Edit Item") : String(localized: "Adaugă articol"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { populateFromEditing() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulează") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") { Task { await save() } }
                        .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    selectedImageData = image.jpegData(compressionQuality: 0.85)
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showSerialScanner) {
                SerialScannerSheet { text in
                    serial = text
                    showSerialScanner = false
                    HapticFeedback.success()
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .jpeg, .png, .heic]
            ) { result in
                if case .success(let url) = result {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    selectedImageData = try? Data(contentsOf: url)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                    }
                }
            }
            .onChange(of: receiptPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        receiptImageData = data
                    }
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(spacing: 0) {
            Button { showPhotoMenu = true } label: {
                ZStack {
                    if let data = selectedImageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(maxWidth: .infinity).frame(height: 180)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(AppFont.scaled(28))
                                        .foregroundStyle(Color.accentColor.opacity(0.7))
                                    Text("Adaugă fotografie")
                                        .font(AppFont.scaled(13, weight: .medium))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                }
                            )
                    }
                    if selectedImageData != nil {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    selectedImageData = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(AppFont.scaled(22))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear photo")
                                .padding(10)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(
                        selectedImageData != nil ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
                        lineWidth: selectedImageData != nil ? 1.5 : 0.5,
                        antialiased: true
                    )
            )
            .confirmationDialog("Fotografie articol", isPresented: $showPhotoMenu) {
                Button("Cameră") { showCamera = true }
                Button("Bibliotecă") { showLibrary = true }
                Button("Fișiere") { showFileImporter = true }
                Button("Anulează", role: .cancel) {}
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $selectedPhotoItem, matching: .images)
    }

    private func populateFromEditing() {
        guard let e = editing, !didPopulate else { return }
        didPopulate = true
        name = e.name; category = e.category; location = e.location
        brand = e.brand; serial = e.serialNumber; condition = e.condition
        if let d = e.purchaseDate { hasPurchaseDate = true; purchaseDate = d }
        if e.purchasePrice > 0 { price = String(Int(e.purchasePrice)) }
        if let w = e.warrantyExpiresAt { hasWarranty = true; warrantyDate = w }
        notes = e.notes
        selectedImageData = InventoryImageStore.load(for: e.id)?
            .jpegData(compressionQuality: 0.85)
        receiptImageData = InventoryImageStore.loadReceipt(for: e.id)?
            .jpegData(compressionQuality: 0.85)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var item = editing ?? InventoryItem(name: name)
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.category = category; item.location = location; item.brand = brand
        item.serialNumber = serial; item.condition = condition
        item.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        item.purchasePrice = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        item.warrantyExpiresAt = hasWarranty ? warrantyDate : nil
        item.notes = notes
        if let data = selectedImageData {
            await InventoryImageStore.save(data, for: item.id)
        } else if editing != nil {
            InventoryImageStore.delete(for: item.id)
        }
        if let data = receiptImageData {
            await InventoryImageStore.saveReceipt(data, for: item.id)
        } else if editing != nil {
            InventoryImageStore.deleteReceipt(for: item.id)
        }
        onSave(item)
        HapticFeedback.success()
        dismiss()
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
    }
    /// Serial-number field with a Live Text scan button — VisionKit reads the
    /// label with the camera and fills the field. Hidden on hardware without
    /// data-scanning support, so the control is never dead.
    private var serialField: some View {
        HStack(spacing: 12) {
            Image(systemName: "number").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField("Număr de serie", text: $serial)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            if DataScannerViewController.isSupported {
                Button { HapticFeedback.impact(.light); showSerialScanner = true } label: {
                    Image(systemName: "text.viewfinder")
                        .font(AppFont.scaled(16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("inv_scan_serial"))
            }
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    /// Warranty proof — an optional receipt/invoice photo kept alongside the
    /// item's other local photos.
    private var receiptRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.image").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            if let data = receiptImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                Text("inv_receipt").font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer()
                Button { receiptImageData = nil; receiptPhotoItem = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(18))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("inv_receipt_remove"))
            } else {
                PhotosPicker(selection: $receiptPhotoItem, matching: .images) {
                    HStack {
                        Text("inv_receipt_attach").font(AppFont.scaled(15)).foregroundStyle(Color.accentColor)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.scaled(16))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
    }

    private func field(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b).font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }
    private func picker(_ icon: String, _ label: LocalizedStringKey, _ b: Binding<String>, _ opts: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(AppFont.scaled(15)).foregroundStyle(.primary)
            Spacer()
            Picker("", selection: b) { ForEach(opts, id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) } }.tint(Color.primary.opacity(AppOpacity.mediumText))
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
    }
    private func toggle(_ icon: String, _ label: LocalizedStringKey, _ b: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(AppFont.scaled(15)).foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: b).tint(.accentColor).labelsHidden()
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
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
                    Image(systemName: "camera.fill").font(AppFont.scaled(44)).foregroundStyle(Color.primary.opacity(0.25))
                    Text("Camera scanner not available on this device").font(AppFont.scaled(15)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText)).multilineTextAlignment(.center)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(AppFont.scaled(30))
                            .foregroundStyle(Color.primary.opacity(0.85)).background(Color.black.opacity(0.3), in: Circle())
                    }
                    .accessibilityLabel("Close scanner")
                    .padding(AppSpacing.xl)
                }
                Spacer()
                Text("Point at an item's QR code")
                    .font(AppFont.body).foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.xl).padding(.vertical, AppSpacing.md)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 60)
            }
        }
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    /// What VisionKit should recognize — defaults to the QR configuration
    /// used by the inventory QR sheet.
    var recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType> = [.barcode(symbologies: [.qr])]
    /// Barcodes fire on first recognition. Freeform text waits for an
    /// explicit tap on the highlighted line instead — auto-filling on first
    /// detection would happily grab the wrong label off a crowded sticker.
    var firesOnFirstRecognition = true
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .accurate,
            recognizesMultipleItems: !firesOnFirstRecognition,
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
    func makeCoordinator() -> Coordinator {
        Coordinator(firesOnFirstRecognition: firesOnFirstRecognition, onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let firesOnFirstRecognition: Bool
        let onScan: (String) -> Void
        private var fired = false

        init(firesOnFirstRecognition: Bool, onScan: @escaping (String) -> Void) {
            self.firesOnFirstRecognition = firesOnFirstRecognition
            self.onScan = onScan
        }

        private func payload(of item: RecognizedItem) -> String? {
            switch item {
            case .barcode(let b): return b.payloadStringValue
            case .text(let t):    return t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            @unknown default:     return nil
            }
        }

        private func deliver(_ value: String, from scanner: DataScannerViewController) {
            guard !fired, !value.isEmpty else { return }
            fired = true
            scanner.stopScanning()
            DispatchQueue.main.async { self.onScan(value) }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard firesOnFirstRecognition else { return }
            for item in addedItems {
                if let value = payload(of: item) {
                    deliver(value, from: dataScanner)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if let value = payload(of: item) { deliver(value, from: dataScanner) }
        }
    }
}

// MARK: - Serial number scanner (Live Text)

/// Camera capture for the serial-number field: VisionKit highlights the text
/// it recognizes and the user taps the correct line to fill the field.
struct SerialScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                DataScannerRepresentable(recognizedDataTypes: [.text()],
                                         firesOnFirstRecognition: false,
                                         onScan: onScan)
                    .ignoresSafeArea()
            } else {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(AppFont.scaled(44)).foregroundStyle(Color.primary.opacity(0.25))
                    Text("Camera scanner not available on this device").font(AppFont.scaled(15)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText)).multilineTextAlignment(.center)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(AppFont.scaled(30))
                            .foregroundStyle(Color.primary.opacity(0.85)).background(Color.black.opacity(0.3), in: Circle())
                    }
                    .accessibilityLabel("Close scanner")
                    .padding(AppSpacing.xl)
                }
                Spacer()
                Text("inv_scan_serial_hint")
                    .font(AppFont.body).foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.xl).padding(.vertical, AppSpacing.md)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 60)
            }
        }
    }
}

// MARK: - Local image store for inventory items

enum InventoryImageStore {
    private static func url(for id: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inventory_\(id.uuidString).jpg")
    }

    /// Recompression is a full decode + JPEG encode — real CPU time that has
    /// no business on the main actor. Same bytes end up on disk as before.
    static func save(_ data: Data, for id: UUID) async {
        let dest = url(for: id)
        await Task.detached(priority: .utility) {
            let compressed: Data
            if let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.75) {
                compressed = jpg
            } else {
                compressed = data
            }
            try? compressed.write(to: dest)
        }.value
    }

    static func load(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// The DB assigns a fresh id on insert, so images saved under the local
    /// draft id must be moved to the persisted id — otherwise the photo is
    /// orphaned and the item never shows it.
    static func migrate(from oldId: UUID, to newId: UUID) {
        guard oldId != newId else { return }
        try? FileManager.default.moveItem(at: url(for: oldId), to: url(for: newId))
        try? FileManager.default.moveItem(at: receiptURL(for: oldId), to: receiptURL(for: newId))
        let oldDir = galleryDir(for: oldId, create: false)
        if FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: galleryDir(for: newId, create: false))
        }
    }

    static func deleteAll(for id: UUID) {
        delete(for: id)
        deleteReceipt(for: id)
        try? FileManager.default.removeItem(at: galleryDir(for: id, create: false))
    }

    // MARK: Receipt / invoice photo (warranty proof)

    private static func receiptURL(for id: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inventory_receipt_\(id.uuidString).jpg")
    }

    static func saveReceipt(_ data: Data, for id: UUID) async {
        let dest = receiptURL(for: id)
        await Task.detached(priority: .utility) {
            let compressed: Data
            if let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.78) {
                compressed = jpg
            } else {
                compressed = data
            }
            try? compressed.write(to: dest)
        }.value
    }

    static func loadReceipt(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: receiptURL(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func deleteReceipt(for id: UUID) {
        try? FileManager.default.removeItem(at: receiptURL(for: id))
    }

    // MARK: Gallery (additional photos, separate from the cover)

    private static func galleryDir(for id: UUID, create: Bool = true) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inventory_gallery", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func galleryURLs(for id: UUID) -> [URL] {
        let dir = galleryDir(for: id, create: false)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        // File names start with a sortable timestamp — lexicographic == chronological.
        return files.filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    static func addGalleryImage(_ data: Data, for id: UUID) async -> URL? {
        let stamp = String(format: "%013.0f", Date().timeIntervalSince1970 * 1000)
        let dest = galleryDir(for: id)
            .appendingPathComponent("\(stamp)-\(UUID().uuidString.lowercased()).jpg")
        return await Task.detached(priority: .utility) { () -> URL? in
            let compressed: Data
            if let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.78) {
                compressed = jpg
            } else {
                compressed = data
            }
            do {
                try compressed.write(to: dest)
                return dest
            } catch {
                return nil
            }
        }.value
    }

    static func removeGalleryImage(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

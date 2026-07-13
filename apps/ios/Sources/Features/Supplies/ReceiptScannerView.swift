import SwiftUI
import PhotosUI
import PDFKit
import VisionKit
import UniformTypeIdentifiers

// MARK: - Receipt Scanner
//
// Photograph (or import) a receipt → on-device OCR with positional row
// reconstruction → parsed items with prices → automatic shopping-list sync
// (bought items are checked off or their quantities decremented) → one tap
// saves everything. Zero manual typing after the photo.

struct ReceiptScannerView: View {
    /// Called after a scanned receipt is saved, so a presenting sheet (e.g. the
    /// manual "New receipt" form) can dismiss itself instead of leaving the
    /// user on an empty form behind the scanner.
    var onSaved: (() -> Void)? = nil

    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(SupplyService.self) private var supplyService: SupplyService?
    @Environment(PantryService.self) private var pantryService: PantryService?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case entry, processing, review }

    @State private var phase: Phase = .entry
    @State private var progress = ScanProgress()
    @State private var parsed: ParsedReceipt? = nil
    @State private var syncActions: [ReceiptListSync.ListSyncAction] = []
    @State private var scanFailed = false
    @State private var isSaving = false

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showDocumentScanner = false
    @State private var showLegacyCamera = false
    @State private var showFileImporter = false

    private var phaseAnimation: Animation? { reduceMotion ? nil : .snappy }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                switch phase {
                case .entry:
                    ScannerEntryView(
                        scanFailed: scanFailed,
                        selectedPhotoItem: $selectedPhotoItem,
                        onCamera: { openCamera() },
                        onImportPDF: { showFileImporter = true }
                    )
                    .transition(.opacity)
                case .processing:
                    ScannerProcessingView(progress: progress)
                        .transition(.opacity)
                case .review:
                    if let receipt = parsed {
                        // Deliberately NOT `Binding($parsed)`: that binding's
                        // getter force-unwraps, and the outgoing review view
                        // (kept alive by the opacity transition) may re-read
                        // it after `parsed` becomes nil — a crash. This
                        // getter falls back to the last snapshot instead.
                        ReceiptReviewView(parsed: Binding(get: { parsed ?? receipt },
                                                          set: { parsed = $0 }),
                                          syncActions: syncActions,
                                          pantryAvailable: pantryService != nil,
                                          isSaving: isSaving) {
                            Task { await save() }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .navigationTitle(String(localized: "scanner_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Review: rescan on the LEFT, cancel on the RIGHT, so the
                // inline title sits centered between them (IMG_8088). The
                // entry phase keeps the single conventional cancel.
                if phase == .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "scanner_rescan")) {
                            // `parsed` must survive the animated exit — the
                            // review view can still read it mid-transition.
                            // The next scan clears it in `process(images:)`.
                            withAnimation(phaseAnimation) {
                                syncActions = []
                                phase = .entry
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    selectedPhotoItem = nil
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    process(images: [image])
                }
            }
            .onChange(of: parsed?.items) { _, items in
                // Edited names/quantities re-run the list matching live.
                guard let items else { return }
                recomputeSync(for: items)
            }
            .fullScreenCover(isPresented: $showDocumentScanner) {
                DocumentScanner { images in
                    showDocumentScanner = false
                    if !images.isEmpty { process(images: images) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showLegacyCamera) {
                CameraCapture { image in
                    showLegacyCamera = false
                    process(images: [image])
                }
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }
                importPDF(from: url)
            }
        }
    }

    // MARK: - Input sources

    private func openCamera() {
        // VisionKit's document camera brings edge detection, perspective
        // correction, auto-capture and multi-page scans (long receipts).
        if VNDocumentCameraViewController.isSupported {
            showDocumentScanner = true
        } else {
            showLegacyCamera = true
        }
    }

    private func importPDF(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        Task {
            let images = await Task.detached(priority: .userInitiated) {
                Self.renderPDFPages(at: url)
            }.value
            if secured { url.stopAccessingSecurityScopedResource() }
            if !images.isEmpty { process(images: images) }
        }
    }

    /// Renders up to 3 PDF pages at 300 dpi for OCR.
    nonisolated private static func renderPDFPages(at url: URL) -> [UIImage] {
        guard let document = PDFDocument(url: url) else { return [] }
        let pageCount = min(document.pageCount, 3)
        guard pageCount > 0 else { return [] }
        let scale: CGFloat = 300.0 / 72.0
        var images: [UIImage] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            images.append(renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            })
        }
        return images
    }

    // MARK: - Processing pipeline

    private func process(images: [UIImage]) {
        guard !images.isEmpty else { return }
        scanFailed = false
        // A stale review result may still be around after "rescan" (kept so
        // the outgoing view never reads a nil) — this is where it dies.
        parsed = nil
        syncActions = []
        progress = ScanProgress(pageCount: images.count)
        withAnimation(phaseAnimation) { phase = .processing }

        Task {
            // 1. OCR — page by page, so the checklist reflects real work.
            var lines: [OCRLine] = []
            for (index, image) in images.enumerated() {
                progress.currentPage = index + 1
                let pageLines = await ReceiptIntelligence.recognize(image: image, pageIndex: index)
                lines.append(contentsOf: pageLines)
            }
            progress.complete(.reading)

            // 2. Parse rows into products, prices, store, date, total.
            let receipt = ReceiptIntelligence.parse(rows: lines)
            await stepBreath()
            progress.complete(.products)

            // 3. Match against the pending shopping list.
            let pendingItems = supplyService?.items.filter { !$0.isCompleted } ?? []
            let plan = ReceiptListSync.plan(receiptItems: receipt.items, listItems: pendingItems)
            await stepBreath()
            progress.complete(.matching)
            await stepBreath()

            if receipt.items.isEmpty && receipt.total == 0 {
                HapticFeedback.error()
                scanFailed = true
                withAnimation(phaseAnimation) { phase = .entry }
            } else {
                HapticFeedback.impact(.light)
                parsed = receipt
                syncActions = plan.actions
                withAnimation(phaseAnimation) { phase = .review }
            }
        }
    }

    /// A short pause so each completed step registers visually instead of
    /// the whole checklist flashing past in one frame.
    private func stepBreath() async {
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 320))
    }

    private func recomputeSync(for items: [ParsedItem]) {
        let pendingItems = supplyService?.items.filter { !$0.isCompleted } ?? []
        syncActions = ReceiptListSync.plan(receiptItems: items, listItems: pendingItems).actions
    }

    // MARK: - Save

    private func save() async {
        guard let parsed, let propId = propertyService.primary?.id, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        // 1. The killer feature: check off / decrement the shopping list.
        if let supplyService {
            await ReceiptListSync.apply(syncActions, via: supplyService)
        }

        // 1b. Grow the pantry: each bought product lands on its stock row,
        // merged by normalized name (fresh load first so merging sees the
        // household's latest numbers).
        if let pantryService {
            await pantryService.load(propertyId: propId)
            // Stock per ITEM category — the detergent from a grocery run
            // belongs on the cleaning shelf, not between the vegetables.
            let byCategory = Dictionary(grouping: parsed.items, by: \.category)
            for (category, group) in byCategory {
                let additions = group.map { item in
                    let display = item.normalizedName.isEmpty ? item.name : item.normalizedName
                    return PantryMerge.Addition(name: display,
                                                normalizedName: display,
                                                quantity: max(item.quantity, 1),
                                                unit: item.unit)
                }
                await pantryService.stock(additions, propertyId: propId, category: category)
            }
        }

        // 2. Persist the receipt and its items. The VAT figure rides the
        // notes column — captured data survives without a schema change.
        let now = ISO8601DateFormatter().string(from: Date())
        let vatNote: String? = parsed.vatAmount.map {
            String(format: String(localized: "scanner_vat_note_fmt"),
                   CurrencyService.money($0, code: parsed.currency, whole: false))
        }
        let currencyNote: String? = parsed.currency == "RON" ? nil : parsed.currency
        let joined = [parsed.notes, vatNote, currencyNote].compactMap { $0 }.joined(separator: " · ")
        let notes: String? = joined.isEmpty ? nil : joined
        let payload = NewReceiptPayload(
            propertyId: propId,
            storeName: parsed.storeName,
            date: parsed.dateString,
            total: parsed.total,
            category: parsed.category,
            imageUrl: nil,
            notes: notes?.isEmpty == true ? nil : notes,
            createdAt: now,
            updatedAt: now
        )
        let items = parsed.items.map { item in
            NewReceiptItemPayload(
                receiptId: UUID(),
                propertyId: propId,
                name: item.normalizedName.isEmpty ? item.name : item.normalizedName,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                // What the line actually cost: printed total minus its
                // attached discount — so saved lines sum to the paid total.
                totalPrice: item.finalPrice,
                category: item.category,
                createdAt: now
            )
        }
        do {
            try await receiptService.addReceipt(payload, items: items)
            HapticFeedback.success()
            onSaved?()
            dismiss()
        } catch {
            HapticFeedback.error()
        }
    }
}

// MARK: - Scan progress model

@MainActor
@Observable
final class ScanProgress {
    enum Step: Int, CaseIterable, Comparable {
        case reading, products, matching
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var pageCount: Int
    var currentPage = 1
    private(set) var completed: Set<Step> = []

    init(pageCount: Int = 1) { self.pageCount = pageCount }

    func complete(_ step: Step) { completed.insert(step) }
    func isDone(_ step: Step) -> Bool { completed.contains(step) }
    var currentStep: Step? { Step.allCases.first { !completed.contains($0) } }
}

// MARK: - Entry state

private struct ScannerEntryView: View {
    let scanFailed: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onCamera: () -> Void
    let onImportPDF: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xxl) {
                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "camera.viewfinder")
                        .font(AppFont.scaled(42, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 104, height: 104)
                        .mediaGlass(in: Circle())
                        .accessibilityHidden(true)

                    Text("scanner_headline")
                        .font(AppFont.title3)
                        .foregroundStyle(.primary)

                    Text("scanner_body")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }
                .padding(.top, AppSpacing.xxl)

                if scanFailed {
                    Label {
                        Text("scanner_failed")
                            .font(AppFont.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Color.brandWarning)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, AppSpacing.xl)
                }

                VStack(spacing: AppSpacing.md) {
                    GlassWideButton(icon: "camera.fill", label: "Fotografiază bon") {
                        onCamera()
                    }

                    HStack(spacing: AppSpacing.md) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            secondaryChipLabel("scanner_choose_photo", icon: "photo.on.rectangle")
                        }
                        .buttonStyle(.plain)

                        Button {
                            HapticFeedback.impact(.light)
                            onImportPDF()
                        } label: {
                            secondaryChipLabel("scanner_import_pdf", icon: "doc.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }

                // What the scanner actually does — honest capabilities only.
                GlassCard(padding: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("scanner_info_title")
                            .font(AppFont.label)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        capabilityRow("text.viewfinder", "scanner_info_ocr")
                        capabilityRow("basket", "scanner_info_products")
                        capabilityRow("checklist", "scanner_info_sync")
                        capabilityRow("clock.arrow.circlepath", "scanner_info_history")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("scanner_tip")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
    }

    private func secondaryChipLabel(_ key: LocalizedStringKey, icon: String) -> some View {
        Label {
            Text(key).font(AppFont.footnoteEmphasis)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .glassCapsule()
    }

    private func capabilityRow(_ icon: String, _ key: LocalizedStringKey) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppFont.footnote)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(key)
                .font(AppFont.footnote)
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle")
                .font(AppFont.footnote)
                .foregroundStyle(Color.brandSuccess)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Processing state

private struct ScannerProcessingView: View {
    let progress: ScanProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(AppFont.scaled(34, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 88, height: 88)
                .mediaGlass(in: Circle())
                .accessibilityHidden(true)

            GlassCard(padding: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    stepRow(.reading, label: readingLabel)
                    stepRow(.products, label: Text("scanner_step_products"))
                    stepRow(.matching, label: Text("scanner_step_matching"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.xl)
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2),
                       value: progress.completed)

            Spacer()
        }
    }

    private var readingLabel: Text {
        if progress.pageCount > 1, !progress.isDone(.reading) {
            let pages = String(format: String(localized: "scanner_step_page"),
                               progress.currentPage, progress.pageCount)
            return Text(verbatim: "\(String(localized: "scanner_step_reading")) \(pages)")
        }
        return Text("scanner_step_reading")
    }

    @ViewBuilder
    private func stepRow(_ step: ScanProgress.Step, label: Text) -> some View {
        let done = progress.isDone(step)
        let isCurrent = progress.currentStep == step
        HStack(spacing: AppSpacing.md) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandSuccess)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else if isCurrent {
                    ProgressView().controlSize(.small)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(AppOpacity.hairline))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 22, height: 22)

            label
                .font(done || isCurrent ? AppFont.subheadline : AppFont.footnote)
                .foregroundStyle(done || isCurrent
                    ? Color.primary
                    : Color.primary.opacity(AppOpacity.disabled))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Review state

private struct ReceiptReviewView: View {
    @Binding var parsed: ParsedReceipt
    let syncActions: [ReceiptListSync.ListSyncAction]
    /// Nil when the pantry module isn't mounted — the note row hides.
    var pantryAvailable: Bool = false
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerCard
                syncSection
                itemsSection
                reductionsSection

                if pantryAvailable, !parsed.items.isEmpty {
                    pantryNote
                }

                GlassWideButton(icon: "checkmark", label: "scanner_save", isBusy: isSaving) {
                    onSave()
                }

                Spacer(minLength: AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The pantry grows on save — say so, quietly.
    private var pantryNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "basket.fill")
                .font(AppFont.scaled(13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(String(format: String(localized: "pantry_stock_note"), parsed.items.count))
                .font(AppFont.scaled(13))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Header

    private var headerCard: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.base) {
                fieldLabel("scanner_field_store")
                TextField(String(localized: "scanner_store_placeholder"), text: $parsed.storeName)
                    .font(AppFont.headline)
                    .padding(AppSpacing.md)
                    .background(Color.subtleFill,
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        fieldLabel("scanner_field_date")
                        DatePicker("", selection: Binding(
                            get: { parsed.dateValue },
                            set: { parsed.dateString = AppDate.dayString(from: $0) }
                        ), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .accessibilityLabel(Text("scanner_field_date"))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                        fieldLabel("scanner_field_total")
                        HStack(spacing: AppSpacing.xs) {
                            TextField("0.00", value: $parsed.total,
                                      format: .number.precision(.fractionLength(2)))
                                .font(AppFont.title2)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .fixedSize()
                                .accessibilityLabel(Text("scanner_field_total"))
                            Text(parsed.currency)
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let vat = parsed.vatAmount {
                            Text("scanner_vat_line \(CurrencyService.money(vat, code: parsed.currency, whole: false))")
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                fieldLabel("scanner_field_category")
                categoryChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(ReceiptCategory.all, id: \.id) { cat in
                    let selected = parsed.category == cat.id
                    Button {
                        parsed.category = cat.id
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: selected ? "checkmark" : ReceiptCategory.icon(for: cat.id))
                                .font(AppFont.caption2)
                            Text(cat.label)
                                .font(AppFont.captionEmphasis)
                        }
                        .foregroundStyle(selected ? Color.primary : Color.primary.opacity(AppOpacity.emphasis))
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(selected ? 0 : AppOpacity.subtleFill), in: Capsule())
                        .overlay(Capsule().strokeBorder(
                            selected ? Color.primary.opacity(AppOpacity.mediumText) : .clear,
                            lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(cat.label))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Shopping-list sync

    @ViewBuilder
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            fieldLabel("Shopping list")
            GlassCard(padding: 0) {
                if syncActions.isEmpty {
                    Text("scanner_sync_none")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .padding(AppSpacing.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(syncActions.enumerated()), id: \.element.id) { index, action in
                            syncRow(action)
                            if index < syncActions.count - 1 {
                                Rectangle().fill(Color.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, AppSpacing.base + 22 + AppSpacing.md)
                            }
                        }
                    }
                }
            }
        }
    }

    private func syncRow(_ action: ReceiptListSync.ListSyncAction) -> some View {
        let text: String
        let icon: String
        switch action {
        case .complete(let item):
            text = String(format: String(localized: "scanner_sync_complete"), item.name)
            icon = "checkmark.circle.fill"
        case .decrement(let item, _, let purchased, let remaining):
            text = String(format: String(localized: "scanner_sync_decrement"),
                          item.name, displayQuantity(purchased), displayQuantity(remaining))
            icon = "minus.circle.fill"
        }
        return HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppFont.footnote)
                .foregroundStyle(Color.brandSuccess)
                .frame(width: 22)
            Text(text)
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    /// Stored quantities keep dot decimals; display follows the locale.
    private func displayQuantity(_ stored: String) -> String {
        guard let separator = Locale.current.decimalSeparator, separator != "." else { return stored }
        return stored.replacingOccurrences(of: ".", with: separator)
    }

    // MARK: Items

    @ViewBuilder
    private var itemsSection: some View {
        if !parsed.items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(String(format: String(localized: "scanner_items_count"), parsed.items.count))
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach($parsed.items) { $item in
                            ReviewItemRow(item: $item,
                                          currency: parsed.currency,
                                          storeName: parsed.storeName,
                                          canConvertToDiscount: parsed.items.first?.id != item.id,
                                          onConvertToDiscount: { convertToDiscount(item.id) },
                                          onDelete: { deleteItem(item.id) })
                            if item.id != parsed.items.last?.id {
                                Rectangle().fill(Color.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, AppSpacing.base)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A row the user says is really a discount re-attaches to the item
    /// above it — exactly what the parser does for recognized promo lines.
    private func convertToDiscount(_ id: UUID) {
        guard let index = parsed.items.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        let row = parsed.items[index]
        let amount = row.totalPrice > 0 ? row.totalPrice : (row.discount?.amount ?? 0)
        guard amount > 0 else { return }
        var target = parsed.items[index - 1]
        let label = row.normalizedName.isEmpty ? row.name : row.normalizedName
        target.discount = ReceiptIntelligence.mergeDiscounts(
            target.discount,
            ParsedDiscount(label: label, percent: nil, amount: amount))
        if !target.flags.contains(.discountAttached) {
            target.flags.append(.discountAttached)
        }
        parsed.items[index - 1] = target
        parsed.items.remove(at: index)
        HapticFeedback.impact(.light)
    }

    private func deleteItem(_ id: UUID) {
        parsed.items.removeAll { $0.id == id }
        HapticFeedback.impact(.light)
    }

    // MARK: Reductions & reconciliation

    /// Receipt-level reductions when the footer printed them; otherwise the
    /// per-item discounts aggregated by label. Parsed values only.
    private var displayReductions: [ReceiptReduction] {
        if !parsed.reductions.isEmpty { return parsed.reductions }
        var order: [String] = []
        var sums: [String: Double] = [:]
        for item in parsed.items {
            guard let discount = item.discount else { continue }
            let label = discount.label
            if sums[label] == nil { order.append(label) }
            sums[label, default: 0] += discount.amount
        }
        return order.map { ReceiptReduction(label: $0, amount: ReceiptIntelligence.roundMoney(sums[$0] ?? 0)) }
    }

    @ViewBuilder
    private var reductionsSection: some View {
        let recon = parsed.reconciliation
        let named = displayReductions
        if !named.isEmpty || recon.itemDiscounts > 0 || parsed.subtotal != nil {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                fieldLabel("scanner_reductions_title")
                GlassCard(padding: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        ForEach(Array(named.enumerated()), id: \.offset) { _, reduction in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: reduction.label.isEmpty
                                     ? String(localized: "scanner_reduction_generic")
                                     : reduction.label)
                                    .font(AppFont.footnote)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: AppSpacing.sm)
                                Text(verbatim: "−" + money(reduction.amount))
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(Color.brandSuccess)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }

                        if !named.isEmpty {
                            Rectangle().fill(Color.hairline).frame(height: 0.5)
                        }

                        reconciliationRow(recon)

                        if let cash = parsed.cashGiven {
                            Text(verbatim: cashCaption(cash: cash, change: parsed.changeGiven))
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func reconciliationRow(_ recon: ReceiptReconciliation) -> some View {
        let subtotal = parsed.subtotal ?? recon.itemsGross
        let namedSum = displayReductions.reduce(0) { $0 + $1.amount }
        let reductionsTotal = namedSum > 0 ? namedSum : recon.itemDiscounts
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: String(format: String(localized: "scanner_reconciliation_fmt"),
                                  money(subtotal), money(reductionsTotal),
                                  money(recon.paidTotal)))
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if recon.paidTotal > 0 {
                if recon.isMatched {
                    Label {
                        Text("scanner_reconciliation_ok")
                            .font(AppFont.caption)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(Color.brandSuccess)
                } else {
                    Label {
                        Text(String(format: String(localized: "scanner_reconciliation_off_fmt"),
                                    money(abs(recon.delta))))
                            .font(AppFont.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Color.brandWarning)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cashCaption(cash: Double, change: Double?) -> String {
        if let change, change > 0 {
            return String(format: String(localized: "scanner_cash_fmt"),
                          money(cash), money(change))
        }
        return String(format: String(localized: "scanner_cash_no_change_fmt"), money(cash))
    }

    private func money(_ value: Double) -> String {
        CurrencyService.money(value, code: parsed.currency, whole: false)
    }

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Review item row

private struct ReviewItemRow: View {
    @Binding var item: ParsedItem
    /// The receipt's detected currency — prices are shown in what was
    /// actually printed, never a bare number.
    let currency: String
    /// The receipt's store — renames learned here are store-scoped.
    let storeName: String
    /// False for the first row (there is nothing above to attach to).
    let canConvertToDiscount: Bool
    let onConvertToDiscount: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var showsReasons = false
    /// The OCR's original name, captured when the editor opens — the
    /// before/after pair is what the lexicon memory learns from.
    @State private var originalName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowAnimation: Animation? { reduceMotion ? nil : .snappy }
    private var displayTitle: String {
        item.normalizedName.isEmpty ? item.name : item.normalizedName
    }
    /// Uncertainty warns (amber); attribution/weight merely informs.
    private var hasWarning: Bool {
        item.uncertain
            || item.flags.contains(.uncertainPrice)
            || item.flags.contains(.uncertainName)
    }
    private var hasBadge: Bool { hasWarning || !item.flags.isEmpty }
    private var isCountedGroup: Bool {
        item.unit == "buc" && item.quantity > 1
            && item.quantity.rounded() == item.quantity
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    withAnimation(rowAnimation) { toggleEditing() }
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)

                if hasBadge {
                    Button {
                        HapticFeedback.selection()
                        withAnimation(rowAnimation) { showsReasons.toggle() }
                    } label: {
                        Image(systemName: hasWarning
                              ? "exclamationmark.circle.fill" : "info.circle")
                            .font(AppFont.footnote)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(hasWarning ? Color.brandWarning : Color.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, AppSpacing.sm)
                    .accessibilityLabel(Text("scanner_reason_badge_ax"))
                    .accessibilityAddTraits(showsReasons ? .isSelected : [])
                }
            }

            if showsReasons {
                reasonPanel
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if isEditing {
                editor
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Row content

    private var rowContent: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: displayTitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if item.sizeText != nil || isCountedGroup || item.discount != nil {
                    HStack(spacing: AppSpacing.xs) {
                        if let size = item.sizeText {
                            metaChip(Text(verbatim: size))
                        }
                        if isCountedGroup {
                            metaChip(Text(verbatim: "×\(Int(item.quantity))"))
                        }
                        if let discount = item.discount {
                            discountChip(discount)
                        }
                    }
                }

                if !item.normalizedName.isEmpty,
                   item.normalizedName.localizedCaseInsensitiveCompare(item.name) != .orderedSame {
                    Text(verbatim: item.name)
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
            }
            Spacer(minLength: AppSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: CurrencyService.money(item.finalPrice, code: currency, whole: false))
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                if item.discount != nil, item.totalPrice > item.finalPrice {
                    // The printed price stays visible — the discount never
                    // silently rewrites it.
                    Text(verbatim: CurrencyService.money(item.totalPrice, code: currency, whole: false))
                        .font(AppFont.caption2)
                        .strikethrough()
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .monospacedDigit()
                        .accessibilityLabel(Text(String(
                            format: String(localized: "scanner_original_price_ax_fmt"),
                            CurrencyService.money(item.totalPrice, code: currency, whole: false))))
                }
                if item.quantity != 1 {
                    Text(verbatim: "\(quantityText) × \(CurrencyService.money(item.unitPrice, code: currency, whole: false))")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .monospacedDigit()
                }
            }
        }
        .padding(.leading, AppSpacing.base)
        .padding(.trailing, hasBadge ? 0 : AppSpacing.base)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func metaChip(_ text: Text) -> some View {
        text
            .font(AppFont.caption2)
            .monospacedDigit()
            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.subtleFill, in: Capsule())
    }

    private func discountChip(_ discount: ParsedDiscount) -> some View {
        let label: String
        if let percent = discount.percent, percent.rounded() == percent {
            label = "−\(Int(percent)) %"
        } else if let percent = discount.percent {
            label = "−\(quantityString(percent)) %"
        } else {
            label = "−" + CurrencyService.money(discount.amount, code: currency, whole: false)
        }
        return Text(verbatim: label)
            .font(AppFont.caption2)
            .monospacedDigit()
            .foregroundStyle(Color.brandSuccess)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.brandSuccess.opacity(AppOpacity.subtleFill), in: Capsule())
            .accessibilityLabel(Text(String(
                format: String(localized: "scanner_discount_ax_fmt"),
                CurrencyService.money(discount.amount, code: currency, whole: false))))
    }

    // MARK: Reasons panel — the badge always explains itself

    private var reasonPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(reasonKeys, id: \.self) { key in
                Label {
                    Text(LocalizedStringKey(key))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: AppSpacing.sm) {
                actionChip("scanner_action_edit", icon: "pencil") {
                    withAnimation(rowAnimation) {
                        if !isEditing { toggleEditing() }
                        showsReasons = false
                    }
                }
                if canConvertToDiscount {
                    actionChip("scanner_action_is_discount", icon: "arrow.up.forward") {
                        withAnimation(rowAnimation) { onConvertToDiscount() }
                    }
                }
                actionChip("scanner_action_delete", icon: "trash",
                           tint: Color.brandDanger) {
                    withAnimation(rowAnimation) { onDelete() }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.bottom, AppSpacing.md)
    }

    /// One plain-language line per structured flag; a generic line when
    /// only the overall confidence was low. Catalog keys (RO+EN).
    private var reasonKeys: [String] {
        var keys: [String] = item.flags.map { flag in
            switch flag {
            case .uncertainPrice:   "scanner_reason_uncertain_price"
            case .uncertainName:    "scanner_reason_uncertain_name"
            case .discountAttached: "scanner_reason_discount"
            case .weightPriced:     "scanner_reason_weight"
            }
        }
        if keys.isEmpty, item.uncertain {
            keys.append("scanner_reason_low_confidence")
        }
        return keys
    }

    private func actionChip(_ key: LocalizedStringKey, icon: String,
                            tint: Color = .primary,
                            action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.selection()
            action()
        } label: {
            Label {
                Text(key).font(AppFont.captionEmphasis)
            } icon: {
                Image(systemName: icon).font(AppFont.caption2)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(Color.subtleFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Quantity formatting

    private var quantityText: String {
        quantityString(item.quantity, unit: item.unit == "buc" ? nil : item.unit)
    }

    /// Stored quantities keep dot decimals; display follows the locale.
    private func quantityString(_ value: Double, unit: String? = nil) -> String {
        let formatted = ReceiptListSync.formatQuantity(value, unit: unit)
        guard let separator = Locale.current.decimalSeparator, separator != "." else { return formatted }
        return formatted.replacingOccurrences(of: ".", with: separator)
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: AppSpacing.sm) {
            TextField(String(localized: "scanner_edit_name"), text: $item.name)
                .font(AppFont.footnote)
                .padding(AppSpacing.sm)
                .background(Color.subtleFill,
                            in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .onChange(of: item.name) { _, newName in
                    item.normalizedName = ReceiptProductLexicon.normalize(newName)
                }
            HStack(spacing: AppSpacing.sm) {
                TextField(String(localized: "scanner_edit_qty"), value: $item.quantity, format: .number)
                    .keyboardType(.decimalPad)
                TextField(String(localized: "scanner_edit_price"), value: $item.totalPrice,
                          format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
            }
            .font(AppFont.footnote)
            .monospacedDigit()
            .textFieldStyle(.plain)
            .padding(AppSpacing.sm)
            .background(Color.subtleFill,
                        in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.bottom, AppSpacing.md)
    }

    private func toggleEditing() {
        if isEditing {
            // Closing the editor counts as the user's review.
            item.uncertain = false
            item.flags.removeAll { $0 == .uncertainName || $0 == .uncertainPrice }
            item.unitPrice = item.quantity > 0
                ? ReceiptIntelligence.roundMoney(item.totalPrice / item.quantity)
                : item.totalPrice
            // Learn the rename — the app must never make the same OCR
            // mistake twice on this household's receipts. Store-scoped:
            // the same shorthand can mean something else elsewhere.
            if !originalName.isEmpty, item.name != originalName {
                ReceiptLexiconMemory.remember(
                    original: originalName,
                    corrected: item.normalizedName.isEmpty ? item.name : item.normalizedName,
                    storeName: storeName)
            }
            isEditing = false
        } else {
            originalName = item.name
            isEditing = true
        }
    }
}

// MARK: - VisionKit document scanner

private struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onFinish([])
        }
    }
}

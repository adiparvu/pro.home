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
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(SupplyService.self) private var supplyService: SupplyService?
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
                    if let binding = Binding($parsed) {
                        ReceiptReviewView(parsed: binding,
                                          syncActions: syncActions,
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
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                if phase == .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "scanner_rescan")) {
                            withAnimation(phaseAnimation) {
                                parsed = nil
                                syncActions = []
                                phase = .entry
                            }
                        }
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

        // 2. Persist the receipt and its items.
        let now = ISO8601DateFormatter().string(from: Date())
        let notes: String? = parsed.currency == "RON"
            ? parsed.notes
            : [parsed.notes, parsed.currency].compactMap { $0 }.joined(separator: " · ")
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
                totalPrice: item.totalPrice,
                category: parsed.category,
                createdAt: now
            )
        }
        do {
            try await receiptService.addReceipt(payload, items: items)
            HapticFeedback.success()
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
                        .font(.system(size: 42, weight: .light))
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
                .font(.system(size: 34, weight: .light))
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
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerCard
                syncSection
                itemsSection

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
                            ReviewItemRow(item: $item)
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
    @State private var isEditing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Button {
                guard item.uncertain || isEditing else { return }
                withAnimation(reduceMotion ? nil : .snappy) { toggleEditing() }
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .disabled(!item.uncertain && !isEditing)

            if isEditing {
                editor
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.normalizedName.isEmpty ? item.name : item.normalizedName)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                if !item.normalizedName.isEmpty,
                   item.normalizedName.localizedCaseInsensitiveCompare(item.name) != .orderedSame {
                    Text(item.name)
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
            }
            Spacer(minLength: AppSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Receipt.format(item.totalPrice))
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                if item.quantity != 1 {
                    Text(verbatim: "\(quantityText) × \(Receipt.format(item.unitPrice))")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .monospacedDigit()
                }
            }
            if item.uncertain {
                Image(systemName: "exclamationmark.circle")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.brandWarning)
                    .accessibilityLabel(Text("scanner_uncertain_badge"))
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.uncertain ? Text("scanner_uncertain_badge") : Text(verbatim: ""))
    }

    private var quantityText: String {
        let formatted = ReceiptListSync.formatQuantity(item.quantity,
                                                       unit: item.unit == "buc" ? nil : item.unit)
        guard let separator = Locale.current.decimalSeparator, separator != "." else { return formatted }
        return formatted.replacingOccurrences(of: ".", with: separator)
    }

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
            item.unitPrice = item.quantity > 0
                ? ReceiptIntelligence.roundMoney(item.totalPrice / item.quantity)
                : item.totalPrice
            isEditing = false
        } else {
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

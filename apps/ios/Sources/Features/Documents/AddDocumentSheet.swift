import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Add Document Sheet

struct AddDocumentSheet: View {
    let propertyId: UUID
    let onSaved: () async -> Void

    @Environment(DocumentService.self) private var documentService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "contract"
    @State private var fields = DocumentFieldState()
    @State private var showFilePicker = false
    @State private var pickedFileData: Data?
    @State private var pickedFileName = ""
    @State private var pickedMimeType = "application/octet-stream"
    @State private var error: String?
    @State private var isSaving = false
    @State private var sharedMemberIds: [String] = []
    @State private var sharedMemberNames: [String] = []
    @State private var showScanCamera = false
    @State private var isScanning = false
    @State private var scanPickerItem: PhotosPickerItem? = nil
    @State private var showDocScanner = false
    /// The fields the last OCR pass filled — shown as a review banner so the
    /// user checks the extraction before saving (nothing is trusted silently).
    @State private var prefillLabels: [String] = []
    @State private var categoryTouched = false
    /// Recognized text accumulated across scans/photos, persisted with the
    /// document so keyword search (D6) can honestly include OCR content.
    @State private var ocrText = ""
    /// The category we last set from OCR, so the picker's onChange can tell a
    /// user's pick from our own programmatic one and stop auto-switching.
    @State private var autoCategory = "contract"

    // MARK: AI Smart Scan (D3, gated)
    //
    // The OCR text can be sent to ARIA for structured extraction + a
    // long-contract summary. It rides the SAME review prefill as D2 — every
    // AI-suggested value lands in the editable form, clearly marked, never saved
    // silently. If the model can't read it, we keep the deterministic prefill
    // and say so; the AI never fabricates a value.
    private enum SmartScanPhase: Equatable { case idle, running, done, lowConfidence, unavailable }
    @State private var smartScan: SmartScanPhase = .idle
    @State private var aiExtraction: DocumentAIExtraction?
    @State private var aiFilledLabels: [String] = []
    @State private var aiSummaryExpanded = false

    // The app language, so ARIA answers (document_type + summary) in the user's
    // tongue — mirrors the ARIA chat's own resolution.
    @AppStorage("prvio.locale")           private var localePref = "en"
    @AppStorage("prvio.followSystemLang") private var followSystemLanguage = true
    private var aiLanguage: String {
        followSystemLanguage ? Language.devicePreferred.rawValue : localePref
    }

    private let categories = ["contract", "legal", "warranty", "insurance", "certificate",
                               "manual", "invoice", "permit", "tax", "utility", "photo", "other"]

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && pickedFileData != nil }

    var body: some View {
        FormScaffold(title: "Add Document", canSave: canSave, isSaving: isSaving,
                     error: $error, onSave: { Task { await save() } }) {
                        FormGroup {
                            HStack(spacing: 0) {
                                FormRow(icon: "doc.text.fill") {
                                    TextField("e.g. Home Insurance 2025", text: $name)
                                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                        .autocorrectionDisabled()
                                }
                                Menu {
                                    if DocumentScannerView.isSupported {
                                        // The real scanner: multi-page, edge
                                        // detection, PDF attached, expiry
                                        // detected — not just a name OCR.
                                        Button { showDocScanner = true } label: {
                                            Label("doc_scan_pdf", systemImage: "doc.viewfinder")
                                        }
                                    }
                                    Button { showScanCamera = true } label: {
                                        Label("Camera", systemImage: "camera.fill")
                                    }
                                    PhotosPicker(selection: $scanPickerItem, matching: .images) {
                                        Label("Photo Library", systemImage: "photo.on.rectangle")
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isScanning { ProgressView().scaleEffect(0.7) }
                                        else { Image(systemName: "camera.viewfinder") }
                                        Text("Scan").font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                                .onChange(of: scanPickerItem) { _, item in
                                    guard let item else { return }
                                    isScanning = true
                                    Task {
                                        defer { isScanning = false; scanPickerItem = nil }
                                        guard let data = try? await item.loadTransferable(type: Data.self),
                                              let uiImage = UIImage(data: data) else { return }
                                        await runOCR(on: uiImage)
                                    }
                                }
                                .padding(.trailing, AppSpacing.lg)
                            }
                        }

                        FormGroup {
                            HStack(spacing: 12) {
                                iconLabel("tag.fill", color: .purple, text: "Category")
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(categories, id: \.self) { c in
                                        Text(LocalizedStringKey(c.capitalized)).tag(c)
                                    }
                                }
                                .tint(Color.primary.opacity(AppOpacity.emphasis))
                                .onChange(of: category) { _, newVal in
                                    if newVal != autoCategory { categoryTouched = true }
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
                        }

                        if !prefillLabels.isEmpty { prefillBanner }

                        if !ocrText.isEmpty { smartScanCard }

                        // The category decides which sections appear — a
                        // Contract asks for issuer + identifiers + value, a
                        // Photo asks for almost nothing.
                        ForEach(DocumentCategorySchema.sections(for: category)) { section in
                            DocSectionView(section: section, state: fields)
                        }

                        FormGroup {
                            Button { showFilePicker = true } label: {
                                HStack(spacing: 12) {
                                    iconLabel("paperclip", color: .blue, text: pickedFileName.isEmpty ? LocalizedStringKey("Attach file") : LocalizedStringKey(pickedFileName))
                                    Spacer()
                                    Image(systemName: pickedFileData != nil ? "checkmark.circle.fill" : "chevron.right")
                                        .font(AppFont.scaled(14))
                                        .foregroundStyle(pickedFileData != nil ? Color.brandSuccess : Color.primary.opacity(0.3))
                                }
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                        }

                        shareSection
        }
        .task { if familyService.members.isEmpty { await familyService.load() } }
        .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .jpeg, .png, .webP, .heic, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .fullScreenCover(isPresented: $showScanCamera) {
                CameraCapture { image in
                    isScanning = true
                    Task {
                        defer { isScanning = false }
                        await runOCR(on: image)
                    }
                }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showDocScanner) {
            DocumentScannerView { result in
                showDocScanner = false
                guard let result else { return }
                applyScan(result)
            }
            .ignoresSafeArea()
        }
    }

    /// A finished scan fills the whole form: the PDF is attached, and the OCR's
    /// proposals (name, dates, issuer, amount, identifiers) land only where the
    /// user hasn't typed — the review banner then lists what was read.
    private func applyScan(_ result: DocumentScanResult) {
        pickedFileData = result.pdfData
        pickedFileName = "scan-\(AppDate.dayString(from: Date())).pdf"
        pickedMimeType = "application/pdf"
        if name.isEmpty, let suggested = result.suggestedName { name = suggested }
        applyPrefill(from: result.lines)
        HapticFeedback.success()
    }

    /// Runs the deterministic D2 extractor over recognized text and fills the
    /// untouched fields, auto-selecting the category only while the user hasn't
    /// picked one themselves.
    private func applyPrefill(from lines: [String]) {
        guard !lines.isEmpty else { return }
        // Keep the raw recognized text for search — nothing here is shown to the
        // user or trusted silently; the review banner still governs the form.
        let joined = lines.joined(separator: "\n")
        ocrText = ocrText.isEmpty ? joined : ocrText + "\n" + joined
        let prefill = DocumentOCR.extract(from: lines)
        if !categoryTouched, let cat = prefill.suggestedCategory,
           categories.contains(cat), cat != category {
            autoCategory = cat
            category = cat
        }
        let written = fields.applyPrefill(prefill)
        if !written.isEmpty { prefillLabels = written }
    }

    // MARK: - OCR review banner
    //
    // Extraction shows what it actually read; the user confirms before saving.
    // This is the visible half of the honesty rule — the form is prefilled, but
    // every value stays editable and is announced here.
    private var prefillBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(AppFont.scaled(15)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("doc_ocr_prefill_title")
                    .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                Text("\(String(localized: "doc_ocr_prefill_body")) \(prefillLabels.joined(separator: ", "))")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { prefillLabels = [] }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(15)).foregroundStyle(Color.primary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.lg)
        .background(Color.accentColor.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - AI Smart Scan (D3)
    //
    // The visible half of the gated feature. It only ever appears once there is
    // OCR text to reason about, always sends that text to a verified-available
    // model, and presents every result as an editable, clearly-labelled AI
    // suggestion — or an honest "couldn't read it" that keeps the on-device
    // extraction. No state here writes a value the user can't see and change.
    @ViewBuilder
    private var smartScanCard: some View {
        switch smartScan {
        case .idle:          smartScanTrigger
        case .running:       smartScanRunning
        case .done:          smartScanResult
        case .lowConfidence: smartScanNotice(title: "doc_ai_lowconf_title", body: "doc_ai_lowconf_body")
        case .unavailable:   smartScanNotice(title: "doc_ai_unavailable_title", body: "doc_ai_unavailable_body")
        }
    }

    private var smartScanTrigger: some View {
        Button { runSmartScan() } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(15)).foregroundStyle(Color.brandIndigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("doc_ai_smartscan").font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Text("doc_ai_smartscan_sub").font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            .aiScanCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("doc_ai_smartscan_sub"))
    }

    private var smartScanRunning: some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView().tint(Color.brandIndigo)
            Text("doc_ai_analyzing").font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .aiScanCard()
        .accessibilityLabel(Text("doc_ai_analyzing"))
    }

    @ViewBuilder
    private var smartScanResult: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(15)).foregroundStyle(Color.brandIndigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("doc_ai_prefill_title")
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    if let ex = aiExtraction, !smartScanHeadline(ex).isEmpty {
                        Text(smartScanHeadline(ex))
                            .font(AppFont.caption).foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { smartScan = .idle }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(15)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }

            if !aiFilledLabels.isEmpty {
                Text("\(String(localized: "doc_ai_prefill_body")) \(aiFilledLabels.joined(separator: ", "))")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }

            // Long-contract summary rides the same call — shown here, and folded
            // into the editable Description field so it is confirmed + persisted.
            if let summary = aiExtraction?.summary, !summary.isEmpty {
                Button {
                    withAnimation(.snappy) { aiSummaryExpanded.toggle() }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "doc.text.magnifyingglass").font(AppFont.scaled(12))
                        Text("doc_ai_summary_title").font(AppFont.captionEmphasis)
                        Image(systemName: aiSummaryExpanded ? "chevron.up" : "chevron.down")
                            .font(AppFont.scaled(10))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.brandIndigo)
                }
                .buttonStyle(.plain)
                if aiSummaryExpanded {
                    Text(summary)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Honesty: everything above is a suggestion to confirm, never saved
            // silently.
            Text("doc_ai_review_hint")
                .font(AppFont.caption2)
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
        }
        .aiScanCard()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func smartScanNotice(title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "sparkles")
                .font(AppFont.scaled(15)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                Text(body).font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer(minLength: 0)
            Button { runSmartScan() } label: {
                Text("doc_ai_retry").font(AppFont.captionEmphasis).foregroundStyle(Color.brandIndigo)
            }
            .buttonStyle(.plain)
        }
        .aiScanCard()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// "Am identificat: Contract Orange · expiră 18.06.2028 · client XXXXX" —
    /// built strictly from values the model returned, never fabricated.
    private func smartScanHeadline(_ ex: DocumentAIExtraction) -> String {
        var parts: [String] = []
        if let type = ex.documentType ?? ex.mappedCategory?.capitalized {
            parts.append(ex.issuer.map { "\(type) \($0)" } ?? type)
        } else if let issuer = ex.issuer {
            parts.append(issuer)
        }
        if let exp = AppDate.day(from: ex.expiresAt ?? "") {
            parts.append(String(format: String(localized: "doc_ai_headline_expires"),
                                AppDate.dayString(from: exp)))
        }
        if let holder = ex.holder {
            parts.append(String(format: String(localized: "doc_ai_headline_client"), holder))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Smart Scan logic

    /// Sends the accumulated OCR text to ARIA off the main actor, then folds any
    /// usable result into the same review prefill D2 uses.
    private func runSmartScan() {
        guard !ocrText.isEmpty else { return }
        withAnimation(.snappy) { smartScan = .running }
        let text = ocrText
        let hint = categoryTouched ? category : nil
        let lang = aiLanguage
        Task {
            let outcome = await DocumentAIExtractor.extract(ocrText: text, categoryHint: hint, language: lang)
            await MainActor.run { applySmartScan(outcome) }
        }
    }

    private func applySmartScan(_ outcome: DocumentAIExtractor.Outcome) {
        switch outcome {
        case .extracted(let ex):
            aiExtraction = ex
            // Only steer the category while the user hasn't chosen one.
            if !categoryTouched, let cat = ex.mappedCategory,
               categories.contains(cat), cat != category {
                autoCategory = cat
                category = cat
            }
            // Fills ONLY untouched fields — an AI guess never clobbers a value
            // the user (or the deterministic pass) already set.
            aiFilledLabels = fields.applyPrefill(ex.toPrefill())
            // Summary → editable Description (only when empty), so it is both
            // reviewable and persisted with the document.
            if let summary = ex.summary, !summary.isEmpty,
               (fields.text[.description] ?? "").isEmpty {
                fields.text[.description] = summary
            }
            withAnimation(.snappy) { smartScan = .done }
            HapticFeedback.success()
        case .lowConfidence:
            withAnimation(.snappy) { smartScan = .lowConfidence }
        case .unavailable:
            withAnimation(.snappy) { smartScan = .unavailable }
        }
    }

    // MARK: - Share with

    // Documents are visible to the whole family by default. Sharing a specific
    // document surfaces it to a scoped member (e.g. a tenant's lease, a worker's
    // plan) without exposing the rest. Writes family_members.id strings into
    // shared_member_ids (RLS: is_shared_with_me, migration 094).
    @ViewBuilder
    private var shareSection: some View {
        if !familyService.members.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Share with")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Spacer()
                    if !sharedMemberIds.isEmpty {
                        Text("\(sharedMemberIds.count)")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                Text("The whole family sees documents. Anyone you add here can also see this one.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                MemberPickerView(selectedIds: $sharedMemberIds, selectedNames: $sharedMemberNames)
            }
            .padding(AppSpacing.lg)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private func runOCR(on image: UIImage) async {
        let lines = await DocumentOCR.recognize(image)
        if name.isEmpty, let suggested = DocumentScanIntelligence.suggestName(from: lines) {
            name = suggested
        }
        applyPrefill(from: lines)
        HapticFeedback.success()
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                error = String(localized: "Could not read the selected file.")
                return
            }
            pickedFileData = data
            pickedFileName = url.lastPathComponent
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
            let ext = url.pathExtension.lowercased()
            pickedMimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func save() async {
        guard let fileData = pickedFileData else { return }
        isSaving = true
        error = nil
        do {
            // Fold any tag still being typed into the list, then build the
            // rich record straight from the dynamic field state.
            let typedTag = fields.string(.tags).trimmingCharacters(in: .whitespacesAndNewlines)
            if !typedTag.isEmpty, !fields.tags.contains(typedTag) { fields.tags.append(typedTag) }

            let extra = DocumentExtra(
                subcategory:   fields.trimmed(.subcategory),
                description:   fields.trimmed(.description),
                priority:      fields.priority,
                issuedAt:      fields.dateString(.issuedAt),
                renewAt:       fields.dateString(.renewAt),
                notifyAt:      fields.dateString(.notifyAt),
                issuerCompany: fields.trimmed(.issuerCompany),
                issuerContact: fields.trimmed(.issuerContact),
                issuerPhone:   fields.trimmed(.issuerPhone),
                issuerEmail:   fields.trimmed(.issuerEmail),
                issuerWebsite: fields.trimmed(.issuerWebsite),
                clientNumber:  fields.trimmed(.clientNumber),
                docNumber:     fields.trimmed(.docNumber),
                series:        fields.trimmed(.series),
                contractCode:  fields.trimmed(.contractCode),
                clientCode:    fields.trimmed(.clientCode),
                fiscalCode:    fields.trimmed(.fiscalCode),
                policyNumber:  fields.trimmed(.policyNumber),
                barcode:       fields.trimmed(.barcode),
                value:         fields.money(.value),
                currency:      fields.money(.value) != nil ? fields.currency : nil,
                vat:           fields.money(.vat),
                recurrence:    fields.recurrence == "one-off" ? nil : fields.recurrence,
                tags:          fields.tags
            )
            try await documentService.add(
                propertyId: propertyId,
                name: name.trimmingCharacters(in: .whitespaces),
                category: category,
                fileData: fileData,
                fileName: pickedFileName,
                mimeType: pickedMimeType,
                expiresAt: fields.dateString(.expiresAt),
                isCritical: DocPriority.isCritical(fields.priority),
                sharedMemberIds: sharedMemberIds,
                ocrText: ocrText.isEmpty ? nil : ocrText,
                extra: extra
            )
            HapticFeedback.success()
            dismiss()
            await onSaved()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }


    private func iconLabel(_ icon: String, color: Color, text: LocalizedStringKey? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(color).frame(width: 22)
            if let text {
                Text(text).font(AppFont.scaled(15)).foregroundStyle(.primary).lineLimit(1)
            }
        }
    }
}

private extension View {
    /// The shared indigo-tinted container for every Smart Scan state, so the
    /// trigger, spinner, result and notices read as one AI surface — distinct
    /// from the accent-tinted deterministic OCR banner above it.
    func aiScanCard() -> some View {
        self
            .padding(AppSpacing.lg)
            .background(Color.brandIndigo.opacity(AppOpacity.subtleFill),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.brandIndigo.opacity(AppOpacity.tintedFill), lineWidth: 0.5))
    }
}

extension ISO8601DateFormatter {
    static let yearMonthDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

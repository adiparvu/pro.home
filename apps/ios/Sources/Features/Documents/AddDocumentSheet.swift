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

extension ISO8601DateFormatter {
    static let yearMonthDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

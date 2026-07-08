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
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasExpiry = false
    @State private var isCritical = false
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
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
                        }

                        FormGroup {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    iconLabel("calendar", color: .orange, text: "Has expiry date")
                                    Spacer()
                                    Toggle("", isOn: $hasExpiry).labelsHidden().tint(.accentColor)
                                }
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)

                                if hasExpiry {
                                    div
                                    DatePicker("", selection: $expiryDate, in: Date()..., displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                                }
                            }
                        }

                        FormGroup {
                            HStack(spacing: 12) {
                                iconLabel("exclamationmark.circle.fill", color: .red, text: "Critical document")
                                Spacer()
                                Toggle("", isOn: $isCritical).labelsHidden().tint(.red)
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
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

    /// A finished scan fills the whole form: the PDF is attached, and the
    /// OCR's title/expiry proposals land only where the user hasn't typed.
    private func applyScan(_ result: DocumentScanResult) {
        pickedFileData = result.pdfData
        pickedFileName = "scan-\(AppDate.dayString(from: Date())).pdf"
        pickedMimeType = "application/pdf"
        if name.isEmpty, let suggested = result.suggestedName { name = suggested }
        if let expiry = result.suggestedExpiry, expiry > Date() {
            hasExpiry = true
            expiryDate = expiry
        }
        HapticFeedback.success()
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
        let lines = await VisionCaptureService.recognizeText(in: image)
        let parsed = VisionCaptureService.parseProduct(from: lines)
        if !parsed.name.isEmpty && name.isEmpty { name = parsed.name }
        if !parsed.brand.isEmpty && name.isEmpty { name = parsed.brand + " " + parsed.model }
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
            let expiryStr: String? = hasExpiry ? ISO8601DateFormatter.yearMonthDay.string(from: expiryDate) : nil
            try await documentService.add(
                propertyId: propertyId,
                name: name.trimmingCharacters(in: .whitespaces),
                category: category,
                fileData: fileData,
                fileName: pickedFileName,
                mimeType: pickedMimeType,
                expiresAt: expiryStr,
                isCritical: isCritical,
                sharedMemberIds: sharedMemberIds
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

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.5).padding(.leading, 52)
    }
}

extension ISO8601DateFormatter {
    static let yearMonthDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

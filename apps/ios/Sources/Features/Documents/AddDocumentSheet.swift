import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Add Document Sheet

struct AddDocumentSheet: View {
    let propertyId: UUID
    let onSaved: () async -> Void

    @EnvironmentObject private var documentService: DocumentService
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
    @State private var showScanCamera = false
    @State private var isScanning = false
    @State private var scanPickerItem: PhotosPickerItem? = nil

    private let categories = ["contract", "warranty", "insurance", "certificate",
                               "manual", "invoice", "photo", "other"]

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && pickedFileData != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        fieldGroup {
                            HStack(spacing: 0) {
                                rowField("doc.text.fill", "Document name") {
                                    TextField("e.g. Home Insurance 2025", text: $name)
                                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                                        .autocorrectionDisabled()
                                }
                                Menu {
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
                                .padding(.trailing, 16)
                            }
                        }

                        fieldGroup {
                            HStack(spacing: 12) {
                                iconLabel("tag.fill", color: .purple, text: "Category")
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(categories, id: \.self) { c in
                                        Text(LocalizedStringKey(c.capitalized)).tag(c)
                                    }
                                }
                                .tint(Color.primary.opacity(0.7))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        fieldGroup {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    iconLabel("calendar", color: .orange, text: "Has expiry date")
                                    Spacer()
                                    Toggle("", isOn: $hasExpiry).labelsHidden().tint(.accentColor)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)

                                if hasExpiry {
                                    div
                                    DatePicker("", selection: $expiryDate, in: Date()..., displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                }
                            }
                        }

                        fieldGroup {
                            HStack(spacing: 12) {
                                iconLabel("exclamationmark.circle.fill", color: .red, text: "Critical document")
                                Spacer()
                                Toggle("", isOn: $isCritical).labelsHidden().tint(.red)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        fieldGroup {
                            Button { showFilePicker = true } label: {
                                HStack(spacing: 12) {
                                    iconLabel("paperclip", color: .blue, text: pickedFileName.isEmpty ? LocalizedStringKey("Attach file") : LocalizedStringKey(pickedFileName))
                                    Spacer()
                                    Image(systemName: pickedFileData != nil ? "checkmark.circle.fill" : "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(pickedFileData != nil ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.primary.opacity(0.3))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                        }

                        if let err = error {
                            Text(err).font(.system(size: 13)).foregroundStyle(.red)
                                .multilineTextAlignment(.center).padding(.horizontal, 8)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.accentColor)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                            .disabled(!canSave)
                    }
                }
            }
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
                isCritical: isCritical
            )
            HapticFeedback.success()
            dismiss()
            await onSaved()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func fieldGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func rowField<Content: View>(_ icon: String, _ placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            iconLabel(icon, color: .blue)
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func iconLabel(_ icon: String, color: Color, text: LocalizedStringKey? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 22)
            if let text {
                Text(text).font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1)
            }
        }
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 52)
    }
}

extension ISO8601DateFormatter {
    static let yearMonthDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

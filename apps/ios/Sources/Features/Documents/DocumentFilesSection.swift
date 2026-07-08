import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// MARK: - Document files section (Document Intelligence D2)
//
// The multi-file layer on the document page: the primary file lives above in
// the file card; this lists every additional attachment (scans, photos, PDFs,
// Files-app imports) and lets the user add or remove them. Reads go through
// signed URLs; adds reuse the private `documents` bucket.

struct DocumentFilesSection: View {
    let documentId: UUID

    @State private var service = DocumentFilesService()
    @State private var previewURL: URL?
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showFileImporter = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var pendingDelete: DocumentFile?
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "paperclip").font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                Text("doc_sec_files").font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                if !service.files.isEmpty {
                    Text("\(service.files.count)")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                addMenu
            }
            .padding(.leading, AppSpacing.sm)

            GlassCard {
                if service.isLoading && service.files.isEmpty {
                    HStack { Spacer(); ProgressView().padding(.vertical, AppSpacing.lg); Spacer() }
                } else if service.files.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.files.enumerated()), id: \.element.id) { idx, file in
                            if idx > 0 { divider }
                            fileRow(file)
                        }
                    }
                }
            }
        }
        .task { await service.load(documentId: documentId) }
        .quickLookPreview($previewURL)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in Task { await addImage(image) } }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { result in
                showScanner = false
                guard let result else { return }
                Task { await addScan(result) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .jpeg, .png, .webP, .heic, .plainText, .data],
                      allowsMultipleSelection: true) { handleFiles($0) }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                defer { libraryItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) { await addImage(img) }
            }
        }
        .confirmationDialog("doc_file_delete_q", isPresented: .init(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let f = pendingDelete { Task { await service.delete(f) } }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var addMenu: some View {
        Menu {
            if DocumentScannerView.isSupported {
                Button { showScanner = true } label: { Label("doc_scan_pdf", systemImage: "doc.viewfinder") }
            }
            Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill") }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button { showFileImporter = true } label: { Label("doc_import_file", systemImage: "folder") }
        } label: {
            HStack(spacing: 4) {
                if service.isUploading { ProgressView().scaleEffect(0.7) }
                else { Image(systemName: "plus") }
                Text("doc_add_file").font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .disabled(service.isUploading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.doc").font(AppFont.scaled(22)).foregroundStyle(Color.primary.opacity(0.25))
            Text("doc_files_empty").font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.lg)
    }

    private func fileRow(_ file: DocumentFile) -> some View {
        Button {
            HapticFeedback.selection()
            open(file)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: file.glyph).font(AppFont.scaled(18)).foregroundStyle(.blue).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    if !file.sizeDisplay.isEmpty {
                        Text(file.sizeDisplay).font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                }
                Spacer()
                if isOpening { ProgressView().scaleEffect(0.7) }
                else {
                    Image(systemName: "chevron.right").font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = file } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button(role: .destructive) { pendingDelete = file } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 46)
    }

    // MARK: Actions

    private func open(_ file: DocumentFile) {
        isOpening = true
        Task {
            defer { isOpening = false }
            if file.isPreviewable, let local = await DocumentFilesService.localCopy(of: file) {
                previewURL = local
            } else if let remote = await DocumentFilesService.resolve(file.url) {
                await UIApplication.shared.open(remote)
            }
        }
    }

    private func addImage(_ image: UIImage) async {
        guard let data = image.uploadJPEG(quality: 0.85, maxDimension: 2400) else { HapticFeedback.error(); return }
        let ok = await service.add(documentId: documentId,
                                   data: data,
                                   name: "photo-\(AppDate.dayString(from: Date())).jpg",
                                   mimeType: "image/jpeg", kind: "photo")
        ok ? HapticFeedback.success() : HapticFeedback.error()
    }

    private func addScan(_ result: DocumentScanResult) async {
        let ok = await service.add(documentId: documentId,
                                   data: result.pdfData,
                                   name: "scan-\(AppDate.dayString(from: Date())).pdf",
                                   mimeType: "application/pdf", kind: "scan",
                                   pageCount: result.pageCount)
        ok ? HapticFeedback.success() : HapticFeedback.error()
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let ext = url.pathExtension.lowercased()
                let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
                let kind = mime == "application/pdf" ? "pdf" : (mime.hasPrefix("image/") ? "photo" : "file")
                await service.add(documentId: documentId, data: data,
                                  name: url.lastPathComponent, mimeType: mime, kind: kind)
            }
            HapticFeedback.success()
        }
    }
}

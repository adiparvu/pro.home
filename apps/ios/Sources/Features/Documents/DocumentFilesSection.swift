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
    /// When the parent document is read-only (D6), every add/replace/delete
    /// affordance in this section is genuinely disabled.
    var readOnly: Bool = false

    @State private var service = DocumentFilesService()
    @State private var previewURL: URL?
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showFileImporter = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var pendingDelete: DocumentFile?
    @State private var isOpening = false
    // Versioning (D5): when set, the next imported file replaces this one
    // instead of being added as a new attachment.
    @State private var replaceTarget: DocumentFile?
    @State private var showReplaceSource = false
    @State private var showReplacePhoto = false
    // Version groups whose history disclosure is expanded.
    @State private var expandedGroups: Set<UUID> = []

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
                if !readOnly { addMenu }
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
        .photosPicker(isPresented: $showReplacePhoto, selection: $libraryItem, matching: .images)
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
        .confirmationDialog("doc_ver_replace_source", isPresented: $showReplaceSource,
                            titleVisibility: .visible) {
            if DocumentScannerView.isSupported {
                Button("doc_scan_pdf") { showScanner = true }
            }
            Button("Camera") { showCamera = true }
            Button("Photo Library") { showReplacePhoto = true }
            Button("doc_import_file") { showFileImporter = true }
            Button("Cancel", role: .cancel) { replaceTarget = nil }
        } message: {
            Text("doc_ver_replace_hint")
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
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassCapsule()
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

    @ViewBuilder
    private func fileRow(_ file: DocumentFile) -> some View {
        let priors = service.priorVersions(of: file)
        let hasHistory = !priors.isEmpty
        let isExpanded = expandedGroups.contains(file.groupId)
        VStack(spacing: 0) {
            mainRow(file, hasHistory: hasHistory)
            if hasHistory {
                historyDisclosure(file, count: priors.count, isExpanded: isExpanded)
                if isExpanded {
                    ForEach(priors) { prior in
                        historyRow(prior)
                    }
                }
            }
        }
    }

    private func mainRow(_ file: DocumentFile, hasHistory: Bool) -> some View {
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
                if hasHistory {
                    Text(file.versionLabel).font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
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
        .swipeActions(edge: .leading) {
            if !readOnly {
                Button { beginReplace(file) } label: { Label("doc_ver_replace", systemImage: "arrow.2.squarepath") }
                    .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            if !readOnly {
                Button(role: .destructive) { pendingDelete = file } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .contextMenu {
            if !readOnly {
                Button { beginReplace(file) } label: { Label("doc_ver_replace", systemImage: "arrow.2.squarepath") }
                Button(role: .destructive) { pendingDelete = file } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    /// The "N older versions" toggle bar shown under a file that carries history.
    private func historyDisclosure(_ file: DocumentFile, count: Int, isExpanded: Bool) -> some View {
        Button {
            HapticFeedback.selection()
            withAnimation(.snappy) {
                if isExpanded { expandedGroups.remove(file.groupId) }
                else { expandedGroups.insert(file.groupId) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppFont.scaled(10, weight: .semibold))
                Text("doc_ver_history").font(AppFont.scaled(11, weight: .medium))
                Text("\(count)").font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Spacer()
            }
            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            .padding(.leading, 46).padding(.trailing, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One older version, openable through the same QuickLook path as current.
    private func historyRow(_ prior: DocumentFile) -> some View {
        Button {
            HapticFeedback.selection()
            open(prior)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath").font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(0.35)).frame(width: 34)
                Text(prior.versionLabel).font(AppFont.scaled(12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                if !prior.sizeDisplay.isEmpty {
                    Text(prior.sizeDisplay).font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                Spacer()
                Image(systemName: "chevron.right").font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.2))
            }
            .padding(.leading, 46).padding(.trailing, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 46)
    }

    private func beginReplace(_ file: DocumentFile) {
        replaceTarget = file
        showReplaceSource = true
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

    /// Routes an imported file to `replace` when a target is armed, otherwise
    /// `add` — the one place the versioning branch lives, so every source
    /// (camera, scan, photo, Files) behaves identically.
    private func ingest(data: Data, name: String, mimeType: String,
                        kind: String, pageCount: Int? = nil) async {
        let ok: Bool
        if let target = replaceTarget {
            ok = await service.replace(target, with: data, name: name,
                                       mimeType: mimeType, kind: kind, pageCount: pageCount)
            replaceTarget = nil
        } else {
            ok = await service.add(documentId: documentId, data: data, name: name,
                                   mimeType: mimeType, kind: kind, pageCount: pageCount)
        }
        ok ? HapticFeedback.success() : HapticFeedback.error()
    }

    private func addImage(_ image: UIImage) async {
        guard let data = image.uploadJPEG(quality: 0.85, maxDimension: 2400) else { HapticFeedback.error(); return }
        await ingest(data: data,
                     name: "photo-\(AppDate.dayString(from: Date())).jpg",
                     mimeType: "image/jpeg", kind: "photo")
    }

    private func addScan(_ result: DocumentScanResult) async {
        await ingest(data: result.pdfData,
                     name: "scan-\(AppDate.dayString(from: Date())).pdf",
                     mimeType: "application/pdf", kind: "scan",
                     pageCount: result.pageCount)
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        // A replace targets exactly one file, so only the first import applies;
        // a plain add ingests every selected file.
        let selected = replaceTarget != nil ? Array(urls.prefix(1)) : urls
        Task {
            for url in selected {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let ext = url.pathExtension.lowercased()
                let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
                let kind = mime == "application/pdf" ? "pdf" : (mime.hasPrefix("image/") ? "photo" : "file")
                await ingest(data: data, name: url.lastPathComponent, mimeType: mime, kind: kind)
            }
        }
    }
}

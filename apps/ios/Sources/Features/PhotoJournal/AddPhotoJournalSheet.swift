import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase

// MARK: - Add photos to the renovation journal
//
// Supports picking several photos at once (library, camera, files), a shared
// title/caption/tags and a "taken on" date. Uploads go to the public
// `documents` bucket — the previously used `photos` bucket never existed,
// which is why saving always failed.

struct AddPhotoJournalSheet: View {
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    private struct PickedPhoto: Identifiable, Equatable {
        let id = UUID()
        let data: Data
        let image: UIImage
    }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [PickedPhoto] = []
    @State private var title = ""
    @State private var caption = ""
    @State private var tagsText = ""
    @State private var takenOn = Date()

    @State private var isUploading = false
    @State private var uploadProgress = 0
    @State private var uploadError: String? = nil
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showLibrary = false
    @State private var showSourceDialog = false

    private let maxPhotos = 12
    private let gridColumns = [GridItem(.flexible(), spacing: AppSpacing.sm),
                               GridItem(.flexible(), spacing: AppSpacing.sm),
                               GridItem(.flexible(), spacing: AppSpacing.sm)]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.lg) {
                        photosSection
                        infoSection
                        detailsSection
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .disabled(isUploading)
                }
            }
            .interactiveDismissDisabled(isUploading)
            .alert("Upload failed", isPresented: .init(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadError ?? "")
            }
            .confirmationDialog("Add photos", isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill") }
                Button { showLibrary = true } label: { Label("Library", systemImage: "photo.on.rectangle") }
                Button { showFileImporter = true } label: { Label("Files", systemImage: "folder.fill") }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItems,
                          maxSelectionCount: maxPhotos - photos.count, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    appendImage(image)
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.image, .jpeg, .png, .heic],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls.prefix(maxPhotos - photos.count) {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                            photos.append(PickedPhoto(data: data, image: img))
                        }
                    }
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: data), photos.count < maxPhotos {
                            photos.append(PickedPhoto(data: data, image: img))
                        }
                    }
                    pickerItems = []
                }
            }
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionLabel("Photos", count: photos.isEmpty ? nil : photos.count)

            if photos.isEmpty {
                emptyPickerCard
            } else {
                LazyVGrid(columns: gridColumns, spacing: AppSpacing.sm) {
                    ForEach(photos) { photo in
                        photoTile(photo)
                    }
                    if photos.count < maxPhotos {
                        addTile
                    }
                }
            }
        }
    }

    private var emptyPickerCard: some View {
        Button { showSourceDialog = true } label: {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.accentColor.opacity(0.25),
                                                    Color.accentColor.opacity(0.08)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(spacing: 4) {
                    Text("Tap to add photos")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text("Camera, library or files")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(Color.primary.opacity(AppOpacity.subtleFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    private func photoTile(_ photo: PickedPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    photos.removeAll { $0.id == photo.id }
                }
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(5)
            .accessibilityLabel("Remove photo")
        }
    }

    private var addTile: some View {
        Button { showSourceDialog = true } label: {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.primary.opacity(AppOpacity.subtleFill))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add photos")
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionLabel("Info", count: nil)
            VStack(spacing: 0) {
                fieldRow("tag.fill", String(localized: "Title (optional)"), $title)
                divider
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .padding(.top, 2)
                    TextField("Caption (optional)…", text: $caption, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(3...6)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 13)
                divider
                fieldRow("number.sign", String(localized: "Tags (comma-separated)"), $tagsText)
            }
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionLabel("Details", count: nil)
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                DatePicker("Taken on", selection: $takenOn,
                           in: ...Date(), displayedComponents: .date)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 8) {
                if isUploading {
                    ProgressView().tint(.white).controlSize(.small)
                    Text(String(format: String(localized: "Uploading %1$d of %2$d…"),
                                min(uploadProgress + 1, photos.count), photos.count))
                } else {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save")
                }
            }
            .font(AppFont.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(photos.isEmpty || isUploading
                          ? AnyShapeStyle(Color.primary.opacity(0.18))
                          : AnyShapeStyle(LinearGradient(colors: [Color.accentColor,
                                                                  Color.accentColor.opacity(0.75)],
                                                         startPoint: .top, endPoint: .bottom)))
            )
        }
        .buttonStyle(.plain)
        .disabled(photos.isEmpty || isUploading)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: LocalizedStringKey, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let count {
                Text("\(count)/\(maxPhotos)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.leading, AppSpacing.sm)
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func appendImage(_ image: UIImage) {
        guard photos.count < maxPhotos,
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        photos.append(PickedPhoto(data: data, image: image))
    }

    // MARK: - Save

    private func save() async {
        guard let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id,
              !photos.isEmpty else { return }

        isUploading = true
        uploadProgress = 0
        defer { isUploading = false }

        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let fallbackTitle = takenOn.formatted(date: .abbreviated, time: .omitted)
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let takenAt = ISO8601DateFormatter().string(from: takenOn)
        let createdAt = ISO8601DateFormatter().string(from: Date())

        for (index, photo) in photos.enumerated() {
            uploadProgress = index
            do {
                let compressed = UIImage(data: photo.data)
                    .flatMap { $0.jpegData(compressionQuality: 0.8) } ?? photo.data
                // The public `documents` bucket allows any authenticated insert;
                // lowercase ids keep paths consistent with auth.uid()::text.
                let path = "\(ownerId.uuidString.lowercased())/journal/\(propertyId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                try await supabase.storage
                    .from("documents")
                    .upload(path, data: compressed,
                            options: FileOptions(contentType: "image/jpeg", upsert: false))
                let publicURL = try supabase.storage.from("documents").getPublicURL(path: path)

                let payload = NewPhotoJournalPayload(
                    propertyId: propertyId,
                    ownerId: ownerId,
                    zoneId: nil,
                    title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
                    caption: caption.isEmpty ? nil : caption,
                    photoUrl: publicURL.absoluteString,
                    takenAt: takenAt,
                    tags: tags.isEmpty ? nil : tags,
                    createdAt: createdAt
                )
                try await photoJournalService.add(payload)
            } catch {
                uploadError = String(format: String(localized: "Upload failed: %@"),
                                     error.localizedDescription)
                HapticFeedback.warning()
                return
            }
        }

        HapticFeedback.success()
        dismiss()
    }
}

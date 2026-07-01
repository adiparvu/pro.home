import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase

struct AddPhotoJournalSheet: View {
    @EnvironmentObject private var photoJournalService: PhotoJournalService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var title = ""
    @State private var caption = ""
    @State private var tagsText = ""
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showPhotoSourceMenu = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        photoPicker
                        formSection("Info") {
                            fieldRow("tag.fill", "Title (required)", $title)
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            divider
                            fieldRow("number.sign", "Tags (comma-separated)", $tagsText)
                        }

                        if let error = uploadError {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                if isUploading {
                    uploadingOverlay
                }
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedImageData == nil || isUploading)
                }
            }
        }
    }

    // MARK: - Photo Picker

    private var photoPicker: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                selectedImageData == nil ? Color.primary.opacity(0.15) : Color.accentColor.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1.5, dash: selectedImageData == nil ? [6, 3] : [])
                            )
                    )

                if let data = selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.primary.opacity(0.3))
                        Text("Tap to choose a photo")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
            }
            .onTapGesture { showPhotoSourceMenu = true }

            HStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.primary)
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder.fill")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                selectedImageData = image.jpegData(compressionQuality: 0.9)
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .jpeg, .png, .heic, .pdf]
        ) { result in
            if case .success(let url) = result {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                selectedImageData = try? Data(contentsOf: url)
            }
        }
    }

    // MARK: - Uploading Overlay

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Uploading photo…")
                    .font(AppFont.body)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Helpers

    private func formSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func save() async {
        guard let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id,
              let imageData = selectedImageData else { return }

        isUploading = true
        uploadError = nil
        defer { isUploading = false }

        do {
            let fileName = "\(UUID().uuidString).jpg"
            let path = "\(propertyId.uuidString)/journal/\(fileName)"

            let compressedData: Data
            if let uiImage = UIImage(data: imageData),
               let jpeg = uiImage.jpegData(compressionQuality: 0.8) {
                compressedData = jpeg
            } else {
                compressedData = imageData
            }

            try await supabase.storage
                .from("photos")
                .upload(path, data: compressedData, options: FileOptions(contentType: "image/jpeg", upsert: false))

            let publicURL = try supabase.storage
                .from("photos")
                .getPublicURL(path: path)

            let tags = tagsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let now = ISO8601DateFormatter().string(from: Date())
            let payload = NewPhotoJournalPayload(
                propertyId: propertyId,
                ownerId: ownerId,
                zoneId: nil,
                title: title.trimmingCharacters(in: .whitespaces),
                caption: caption.isEmpty ? nil : caption,
                photoUrl: publicURL.absoluteString,
                takenAt: now,
                tags: tags.isEmpty ? nil : tags,
                createdAt: now
            )

            await photoJournalService.add(payload)
            HapticFeedback.success()
            dismiss()
        } catch {
            uploadError = String(format: String(localized: "Upload failed: %@"), error.localizedDescription)
            HapticFeedback.warning()
        }
    }
}

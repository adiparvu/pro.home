import SwiftUI
import PhotosUI

// MARK: - PhotoJournalView

struct PhotoJournalView: View {
    @EnvironmentObject private var photoJournalService: PhotoJournalService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var showAdd = false
    @State private var selectedEntry: PhotoJournalEntry? = nil

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if photoJournalService.isLoading && photoJournalService.entries.isEmpty {
                loadingState
            } else if photoJournalService.entries.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .navigationTitle("Photo Journal")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPhotoJournalSheet()
                .environmentObject(photoJournalService)
                .environmentObject(propertyService)
        }
        .sheet(item: $selectedEntry) { entry in
            PhotoEntryDetailSheet(entry: entry)
                .environmentObject(photoJournalService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await photoJournalService.load(propertyId: id)
            }
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photoJournalService.entries) { entry in
                    PhotoGridCell(entry: entry)
                        .onTapGesture {
                            selectedEntry = entry
                            HapticFeedback.impact(.light)
                        }
                }
            }
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await photoJournalService.load(propertyId: id)
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("Start your renovation diary")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Capture before and after photos, track progress, and document every improvement to your home.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add first photo", systemImage: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PhotoGridCell

private struct PhotoGridCell: View {
    let entry: PhotoJournalEntry

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                AsyncImage(url: URL(string: entry.photoUrl)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(ProgressView().tint(.primary.opacity(0.4)))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.primary.opacity(0.3))
                            )
                    @unknown default:
                        Rectangle().fill(Color.primary.opacity(0.05))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.65), Color.clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let date = entry.takenDate {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - PhotoEntryDetailSheet

private struct PhotoEntryDetailSheet: View {
    let entry: PhotoJournalEntry
    @EnvironmentObject private var photoJournalService: PhotoJournalService
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        AsyncImage(url: URL(string: entry.photoUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                            case .empty:
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 300)
                                    .overlay(ProgressView())
                            default:
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 300)
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(entry.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)

                            if let date = entry.takenDate {
                                Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                            }

                            if let caption = entry.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white.opacity(0.8))
                            }

                            if !entry.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(entry.tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(.white.opacity(0.12), in: Capsule())
                                        }
                                    }
                                }
                            }

                            Button {
                                showDeleteConfirm = true
                                HapticFeedback.warning()
                            } label: {
                                Label("Delete Photo", systemImage: "trash")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                        .padding(20)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await photoJournalService.delete(entry)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
}

// MARK: - AddPhotoJournalSheet

private struct AddPhotoJournalSheet: View {
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedImageData == nil || isUploading)
                }
            }
        }
    }

    // MARK: - Photo Picker

    private var photoPicker: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
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
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Helpers

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
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
            uploadError = "Upload failed: \(error.localizedDescription)"
            HapticFeedback.warning()
        }
    }
}

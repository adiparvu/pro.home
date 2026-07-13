import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import Supabase

// MARK: - Add photos to the renovation journal
//
// Supports picking several photos at once (library, camera, files), a shared
// title/caption, tag chips with autocomplete from previously used tags, an
// optional space (property zone) link, and a "taken on" date that prefills
// itself from the photos' EXIF creation date (earliest wins when they
// differ; today stays the honest fallback). Uploads go to the public
// `documents` bucket — the previously used `photos` bucket never existed,
// which is why saving always failed.

struct AddPhotoJournalSheet: View {
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private struct PickedPhoto: Identifiable, Equatable {
        let id = UUID()
        let data: Data
        let image: UIImage
        /// EXIF/TIFF creation date, when the file carries one. nil = unknown
        /// (the shared date falls back to today — never invented).
        let exifDate: Date?
    }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [PickedPhoto] = []
    @State private var title = ""
    @State private var caption = ""
    @State private var takenOn = Date()
    @State private var selectedZoneId: UUID? = nil

    // Tags-as-chips: committed tags + the in-progress free text. The stored
    // format is unchanged — a plain [String] in the `tags` column.
    @State private var tags: [String] = []
    @State private var tagInput = ""

    // EXIF auto-date bookkeeping: the last programmatically applied date, so
    // a user edit (any other change) permanently wins over auto-fill.
    @State private var autoAppliedDate: Date? = nil
    @State private var dateEditedManually = false

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

    private static let badgeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.lg) {
                        photosSection
                        infoSection
                        tagsSection
                        detailsSection
                        if !zoneService.zones.isEmpty {
                            zoneSection
                        }
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
                Text(verbatim: uploadError ?? "")
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
                            photos.append(PickedPhoto(data: data, image: img,
                                                      exifDate: Self.exifCreationDate(from: data)))
                        }
                    }
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        guard photos.count < maxPhotos,
                              let data = try? await item.loadTransferable(type: Data.self) else { continue }
                        // Decode + EXIF parse off the main actor: image data
                        // can be tens of MB and this runs per picked photo.
                        let decoded = await Task.detached(priority: .userInitiated) {
                            (UIImage(data: data), Self.exifCreationDate(from: data))
                        }.value
                        if let img = decoded.0 {
                            photos.append(PickedPhoto(data: data, image: img, exifDate: decoded.1))
                        }
                    }
                    pickerItems = []
                }
            }
            .onChange(of: photos) { _, _ in
                syncAutoDate()
            }
            .onChange(of: takenOn) { _, newValue in
                // Any change that isn't the one we just applied ourselves is
                // a manual edit — from then on the auto-fill stays hands-off.
                if newValue != autoAppliedDate {
                    dateEditedManually = true
                }
            }
        }
    }

    // MARK: - EXIF creation date

    /// Reads DateTimeOriginal (falling back to DateTimeDigitized / TIFF
    /// DateTime) from the image bytes. No photo-library permission is needed
    /// — the pickers hand us the full original data.
    private static func exifCreationDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    /// The earliest EXIF date across the picked photos, never in the future.
    private var earliestExifDate: Date? {
        photos.compactMap(\.exifDate).min().map { min($0, Date()) }
    }

    /// True when the picked photos carry EXIF dates on different days.
    private var hasMixedExifDays: Bool {
        let calendar = Calendar.current
        let days = Set(photos.compactMap(\.exifDate).map { calendar.startOfDay(for: $0) })
        return days.count > 1
    }

    private func syncAutoDate() {
        guard !dateEditedManually, let earliest = earliestExifDate else { return }
        guard takenOn != earliest else { return }
        autoAppliedDate = earliest
        takenOn = earliest
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
                        .font(AppFont.scaled(26, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(spacing: 4) {
                    Text("Tap to add photos")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text("Camera, library or files")
                        .font(AppFont.scaled(13))
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
                .overlay(alignment: .bottomLeading) {
                    // The photo's own EXIF day — shown only when it exists.
                    if let date = photo.exifDate {
                        Text(verbatim: Self.badgeDateFormatter.string(from: date))
                            .font(AppFont.scaled(9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    photos.removeAll { $0.id == photo.id }
                }
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.scaled(10, weight: .bold))
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
                        .font(AppFont.scaled(22, weight: .medium))
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
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .padding(.top, 2)
                    TextField("Caption (optional)…", text: $caption, axis: .vertical)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(3...6)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 13)
            }
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Tags (chips + autocomplete from previously used tags)

    /// Previously used tags across the journal, most frequent first, minus
    /// the ones already committed, narrowed by the free text as you type.
    private var tagSuggestions: [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for entry in photoJournalService.entries {
            for tag in entry.tags ?? [] {
                let key = tag.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = tag }
            }
        }
        let committed = Set(tags.map { $0.lowercased() })
        let query = tagInput.trimmingCharacters(in: .whitespaces)
        return counts
            .filter { !committed.contains($0.key) }
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .compactMap { display[$0.key] }
            .filter { query.isEmpty || $0.matchesSearch(query) }
            .prefix(8)
            .map { $0 }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionLabel("journal_tags_label", count: nil)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if !tags.isEmpty {
                    ChipFlow(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            committedTagChip(tag)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "number")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    TextField(String(localized: "journal_tag_placeholder"), text: $tagInput)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { commitTagInput() }
                        .onChange(of: tagInput) { _, newValue in
                            // The classic "separate prin virgulă" gesture now
                            // commits a chip the moment the comma is typed.
                            if newValue.contains(",") { commitTagInput() }
                        }
                }

                if !tagSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("journal_suggested_tags")
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.secondaryTextColor)
                            .textCase(.uppercase)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tagSuggestions, id: \.self) { tag in
                                    suggestionChip(tag)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
        }
    }

    private func committedTagChip(_ tag: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: "#\(tag)")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                }
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.scaled(9, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("journal_remove_tag \(tag)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }

    private func suggestionChip(_ tag: String) -> some View {
        Button {
            appendTag(tag)
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(AppFont.scaled(9, weight: .semibold))
                Text(verbatim: tag)
                    .font(AppFont.captionEmphasis)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("journal_add_tag \(tag)"))
    }

    private func appendTag(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame })
        else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            tags.append(clean)
        }
    }

    private func commitTagInput() {
        let parts = tagInput.split(separator: ",").map(String.init)
        for part in parts { appendTag(part) }
        tagInput = ""
    }

    // MARK: - Details (taken-on date with EXIF auto-fill)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionLabel("Details", count: nil)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    DatePicker("Taken on", selection: $takenOn,
                               in: ...Date(), displayedComponents: .date)
                        .font(AppFont.scaled(15))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)

                if !dateEditedManually, autoAppliedDate != nil, takenOn == autoAppliedDate {
                    VStack(alignment: .leading, spacing: 3) {
                        Label {
                            Text("journal_date_from_photo")
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(Color.secondaryTextColor)

                        if hasMixedExifDays {
                            Text("journal_date_earliest_note")
                                .font(AppFont.caption)
                                .foregroundStyle(Color.secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.sm)
                }
            }
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Space (property zone) — the model's zone_id column, no fakes

    private var selectedZoneName: String? {
        selectedZoneId.flatMap { id in zoneService.zones.first { $0.id == id }?.name }
    }

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionLabel("journal_space_section", count: nil)
            Menu {
                Button {
                    selectedZoneId = nil
                } label: {
                    if selectedZoneId == nil {
                        Label("journal_space_none", systemImage: "checkmark")
                    } else {
                        Text("journal_space_none")
                    }
                }
                Divider()
                ForEach(zoneService.zones) { zone in
                    Button {
                        selectedZoneId = zone.id
                    } label: {
                        if selectedZoneId == zone.id {
                            Label(zone.name, systemImage: "checkmark")
                        } else {
                            Label(zone.name, systemImage: zone.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    if let selectedZoneName {
                        Text(verbatim: selectedZoneName)
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                    } else {
                        Text("journal_space_none")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
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
                    ProgressView().controlSize(.small)
                    Text(String(format: String(localized: "Uploading %1$d of %2$d…"),
                                min(uploadProgress + 1, photos.count), photos.count))
                } else {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save")
                }
            }
            .font(AppFont.subheadline)
            .foregroundStyle(photos.isEmpty || isUploading
                             ? AnyShapeStyle(.secondary)
                             : AnyShapeStyle(.white))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glassProminent(in: Capsule(), enabled: !photos.isEmpty && !isUploading)
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
                Text(verbatim: "\(count)/\(maxPhotos)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.leading, AppSpacing.sm)
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(AppFont.scaled(15))
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
              let data = image.uploadJPEG(quality: 0.9) else { return }
        // A fresh camera capture happens now; today's default date is honest.
        photos.append(PickedPhoto(data: data, image: image, exifDate: nil))
    }

    // MARK: - Save

    private func save() async {
        guard let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id,
              !photos.isEmpty else { return }

        // Anything still sitting in the free-text field counts too.
        commitTagInput()

        isUploading = true
        uploadProgress = 0
        defer { isUploading = false }

        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let fallbackTitle = takenOn.formatted(date: .abbreviated, time: .omitted)
        let cleanTags = tags
        let takenAt = ISO8601DateFormatter().string(from: takenOn)
        let createdAt = ISO8601DateFormatter().string(from: Date())

        for (index, photo) in photos.enumerated() {
            uploadProgress = index
            do {
                let compressed = UIImage(data: photo.data)
                    .flatMap { $0.uploadJPEG(quality: 0.8) } ?? photo.data
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
                    zoneId: selectedZoneId,
                    title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
                    caption: caption.isEmpty ? nil : caption,
                    photoUrl: publicURL.absoluteString,
                    takenAt: takenAt,
                    tags: cleanTags.isEmpty ? nil : cleanTags,
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

// MARK: - ChipFlow
//
// A minimal wrapping layout for the committed tag chips (variable-width
// capsules that flow onto new lines) — the same local pattern used by
// GuestInfoCard and PlantHealthView for their chip rows.

private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxWidth == .infinity ? widest : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

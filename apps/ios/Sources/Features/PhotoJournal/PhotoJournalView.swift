import SwiftUI
import PhotosUI
import Supabase

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
                .accessibilityLabel("Add photo")
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
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Capture before and after photos, track progress, and document every improvement to your home.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add first photo", systemImage: "camera.fill")
                    .font(AppFont.subheadline)
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
                        .font(AppFont.captionStrong)
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

                            if let entryTags = entry.tags, !entryTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(entryTags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(AppFont.caption)
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
                                    .font(AppFont.body)
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

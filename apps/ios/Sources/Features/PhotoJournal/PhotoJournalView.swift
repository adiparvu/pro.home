import SwiftUI
import PhotosUI
import Supabase

// MARK: - PhotoJournalView
//
// Renovation photo diary: photos grouped by month in a tight three-column
// grid (Photos-app style), with tag filtering, context-menu actions and a
// full detail viewer.

struct PhotoJournalView: View {
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false
    @State private var selectedEntry: PhotoJournalEntry? = nil
    @Namespace private var zoomNamespace
    @State private var activeTag: String? = nil
    @State private var showSearch = false
    @State private var searchText = ""

    private let columns = [GridItem(.flexible(), spacing: 2),
                           GridItem(.flexible(), spacing: 2),
                           GridItem(.flexible(), spacing: 2)]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return f
    }()

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if photoJournalService.isLoading && photoJournalService.entries.isEmpty {
                loadingState
            } else if photoJournalService.entries.isEmpty {
                emptyState
            } else {
                journalContent
            }
        }
        .navigationTitle("Photo Journal")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SearchIconButton(isActive: $showSearch)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add photo")
            }
        }
        .onChange(of: showSearch) { _, on in
            if !on { searchText = "" }
        }
        .sheet(isPresented: $showAdd) {
            AddPhotoJournalSheet()
                .environment(photoJournalService)
                .environment(propertyService)
        }
        .sheet(item: $selectedEntry) { entry in
            PhotoEntryDetailSheet(entry: entry)
                .environment(photoJournalService)
                // Photos-style hero: the image grows out of its grid cell
                // (iOS 18); older systems keep the plain sheet.
                .zoomTransition(sourceID: entry.id, in: zoomNamespace)
        }
        .task {
            if let id = propertyService.primary?.id {
                await photoJournalService.load(propertyId: id)
            }
        }
    }

    // MARK: - Filtering & grouping

    private var allTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in photoJournalService.entries {
            for tag in entry.tags ?? [] where seen.insert(tag.lowercased()).inserted {
                ordered.append(tag)
            }
        }
        return ordered
    }

    private var filteredEntries: [PhotoJournalEntry] {
        photoJournalService.entries.filter { entry in
            if let tag = activeTag,
               !(entry.tags ?? []).contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                return false
            }
            return entry.title.matchesSearch(searchText)
                || (entry.caption ?? "").matchesSearch(searchText)
                || (entry.tags ?? []).contains { $0.matchesSearch(searchText) }
        }
    }

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let entries: [PhotoJournalEntry]
    }

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        var groups: [(key: Date, entries: [PhotoJournalEntry])] = []
        for entry in filteredEntries {
            let date = entry.takenDate ?? .distantPast
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            if let idx = groups.firstIndex(where: { $0.key == month }) {
                groups[idx].entries.append(entry)
            } else {
                groups.append((month, [entry]))
            }
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { group in
                MonthGroup(
                    id: String(group.key.timeIntervalSinceReferenceDate),
                    title: Self.monthFormatter.string(from: group.key).capitalized,
                    entries: group.entries
                )
            }
    }

    // MARK: - Content

    private var journalContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg, pinnedViews: []) {
                if showSearch {
                    PageSearchField(text: $searchText)
                        .padding(.horizontal, AppSpacing.lg)
                }
                if allTags.count > 1 {
                    tagFilterBar
                }
                ForEach(monthGroups) { group in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                            Text(group.title)
                                .font(AppFont.headline)
                                .foregroundStyle(.primary)
                            Text("\(group.entries.count)")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(Color.secondaryTextColor)
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(group.entries) { entry in
                                PhotoGridCell(entry: entry)
                                    .zoomTransitionSource(id: entry.id, in: zoomNamespace)
                                    .onTapGesture {
                                        selectedEntry = entry
                                        HapticFeedback.impact(.light)
                                    }
                                    .contextMenu {
                                        Button {
                                            selectedEntry = entry
                                        } label: {
                                            Label("View", systemImage: "eye")
                                        }
                                        Button(role: .destructive) {
                                            Task { await photoJournalService.delete(entry) }
                                        } label: {
                                            Label("Delete Photo", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                Spacer(minLength: 110)
            }
            .padding(.top, AppSpacing.xs)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await photoJournalService.load(propertyId: id)
            }
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                tagChip(nil, label: String(localized: "All"))
                ForEach(allTags, id: \.self) { tag in
                    tagChip(tag, label: "#\(tag)")
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func tagChip(_ tag: String?, label: String) -> some View {
        let isActive = activeTag?.caseInsensitiveCompare(tag ?? "") == .orderedSame
            || (tag == nil && activeTag == nil)
        return Button {
            withAnimation(.snappy(duration: 0.25)) { activeTag = tag }
            HapticFeedback.impact(.light)
        } label: {
            Text(label)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    isActive ? AnyShapeStyle(Color.accentColor)
                             : AnyShapeStyle(Color.primary.opacity(AppOpacity.subtleFill)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: "photo.on.rectangle.angled",
                title: "Start your renovation diary",
                message: "Capture before and after photos, track progress, and document every improvement to your home.",
                actionLabel: "Add first photo",
                action: { showAdd = true }
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                AsyncImage(url: URL(string: entry.photoUrl)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(ProgressView().controlSize(.small).tint(.primary.opacity(0.4)))
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
            )
            .clipped()
            .contentShape(Rectangle())
    }
}

// MARK: - PhotoEntryDetailSheet

private struct PhotoEntryDetailSheet: View {
    let entry: PhotoJournalEntry
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
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
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 300)
                                    .overlay(ProgressView().tint(.white))
                            default:
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
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
                                    .padding(.vertical, AppSpacing.base)
                                    .background(Color.red.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, AppSpacing.sm)
                        }
                        .padding(AppSpacing.xl)

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
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = URL(string: entry.photoUrl) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.white)
                        }
                    }
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
